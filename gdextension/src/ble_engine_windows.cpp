// Windows Bluetooth LE for HexR gloves, on WinRT (C++/WinRT, Windows 10 1803 or later).
//
// Modelled on adabru/BleWinrtDll (WTFPL), which the Unity package ships as a binary, but written
// for two gloves at once and for a game loop that must never block:
//   - one MTA worker thread runs scans, connects and closes, so blocking .get() / wait_for()
//     never touches Godot's threads (WinRT asserts when a single-threaded apartment blocks);
//   - each connected glove has its own writer thread, so a slow connect on one glove never
//     holds up haptics on the other;
//   - WinRT callbacks (advertisements, notifications, link changes) only push to an event queue,
//     which Godot drains on its main thread through poll_events().
//
// The glove's firmware rules: subscribe to notifications exactly once per connection, write with
// response, and cut every write to fit MTU - 3 on frame boundaries.
#ifdef _WIN32

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN

#include "ble_engine.h"
#include "frame_chunker.h"

#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <functional>
#include <future>
#include <map>
#include <mutex>
#include <thread>

#pragma comment(lib, "windowsapp")

using namespace winrt;
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace winrt::Windows::Devices::Radios;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Storage::Streams;
using namespace std::chrono_literals;

namespace hexr {

namespace {

const guid SERVICE_UUID{ 0x000000ff, 0x0000, 0x1000, { 0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb } };
const guid CHARACTERISTIC_UUID{ 0x0000ff01, 0x0000, 0x1000, { 0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb } };

constexpr auto REPORT_EVERY = 1000ms;
constexpr auto FIND_TIMEOUT = 10s;
constexpr auto GATT_TIMEOUT = 10s;
constexpr auto SUBSCRIBE_TIMEOUT = 5s;
constexpr auto WRITE_TIMEOUT = 2s;
constexpr auto CLOSE_DRAIN = 2500ms;
constexpr int DEFAULT_MTU = 23;
constexpr int ATT_OVERHEAD = 3;

std::string address_to_id(uint64_t a) {
	char buf[18];
	std::snprintf(buf, sizeof(buf), "%02X:%02X:%02X:%02X:%02X:%02X",
			unsigned((a >> 40) & 0xFF), unsigned((a >> 32) & 0xFF), unsigned((a >> 24) & 0xFF),
			unsigned((a >> 16) & 0xFF), unsigned((a >> 8) & 0xFF), unsigned(a & 0xFF));
	return buf;
}

bool id_to_address(const std::string &id, uint64_t &out) {
	uint64_t a = 0;
	int digits = 0;
	for (char c : id) {
		int v;
		if (c >= '0' && c <= '9') {
			v = c - '0';
		} else if (c >= 'a' && c <= 'f') {
			v = c - 'a' + 10;
		} else if (c >= 'A' && c <= 'F') {
			v = c - 'A' + 10;
		} else if (c == ':' || c == '-') {
			continue;
		} else {
			return false;
		}
		a = (a << 4) | uint64_t(v);
		digits++;
	}
	out = a;
	return digits == 12;
}

// Waits for a WinRT operation without blocking forever. Cancels it on timeout.
template <typename Op>
bool finish(Op const &op, std::chrono::milliseconds timeout) {
	if (op.wait_for(timeout) == AsyncStatus::Completed) {
		return true;
	}
	try {
		op.Cancel();
	} catch (...) {
	}
	return false;
}

IBuffer to_buffer(const std::vector<uint8_t> &bytes) {
	DataWriter writer;
	writer.WriteBytes(array_view<uint8_t const>(bytes.data(), bytes.data() + bytes.size()));
	return writer.DetachBuffer();
}

std::vector<uint8_t> from_buffer(IBuffer const &buffer) {
	std::vector<uint8_t> out(buffer.Length());
	if (!out.empty()) {
		DataReader::FromBuffer(buffer).ReadBytes(out);
	}
	return out;
}

struct Session {
	std::string id;
	uint64_t address = 0;
	BluetoothLEDevice device{ nullptr };
	GattSession gatt_session{ nullptr };
	GattDeviceService service{ nullptr };
	GattCharacteristic characteristic{ nullptr };
	GattCharacteristic::ValueChanged_revoker value_revoker;
	BluetoothLEDevice::ConnectionStatusChanged_revoker status_revoker;
	GattSession::MaxPduSizeChanged_revoker pdu_revoker;

	std::atomic<bool> ready{ false };
	std::atomic<bool> closing{ false };
	std::atomic<int> mtu{ DEFAULT_MTU };

	std::mutex queue_mutex;
	std::condition_variable queue_cv;
	std::deque<std::vector<uint8_t>> queue;
	bool writer_quit = false;
	std::chrono::steady_clock::time_point drain_deadline{};
	std::thread writer;
};

class WindowsEngine : public BleEngine, public std::enable_shared_from_this<WindowsEngine> {
public:
	WindowsEngine() {
		probed_ = probe_done_.get_future().share();
		worker_ = std::thread([this] { run_worker(); });
		post([this] { probe_adapter(); });
	}

	~WindowsEngine() override { shutdown(); }

	bool available() override {
		std::shared_future<void> probed = probed_;
		if (probed.valid()) {
			probed.wait_for(3s);
		}
		return available_.load();
	}

	std::string last_error() override {
		std::lock_guard lock(error_mutex_);
		return error_;
	}

	void start_scan(int timeout_ms) override {
		post([this, timeout_ms] { start_scan_on_worker(timeout_ms); });
	}

	void stop_scan() override {
		post([this] { stop_scan_on_worker(""); });
	}

	void connect(const std::string &id) override {
		post([this, id] { connect_on_worker(id); });
	}

	void disconnect(const std::string &id) override {
		std::shared_ptr<Session> s = find(id);
		if (s) {
			// Seen at once by a connect still in progress, which then stops quietly.
			s->closing = true;
			std::lock_guard lock(s->queue_mutex);
			s->drain_deadline = std::chrono::steady_clock::now() + CLOSE_DRAIN;
			s->queue_cv.notify_all();
		}
		post([this, id] { close_on_worker(id); });
	}

	bool connected(const std::string &id) override {
		std::shared_ptr<Session> s = find(id);
		return s && s->ready;
	}

	bool write(const std::string &id, const std::vector<uint8_t> &data, bool purge) override {
		std::shared_ptr<Session> s = find(id);
		if (!s || !s->ready || s->closing || data.empty()) {
			return false;
		}
		std::lock_guard lock(s->queue_mutex);
		if (purge) {
			s->queue.clear();
		}
		for (auto &chunk : chunk_for_mtu(data, s->mtu - ATT_OVERHEAD)) {
			s->queue.push_back(std::move(chunk));
		}
		s->queue_cv.notify_all();
		return true;
	}

	int mtu(const std::string &id) override {
		std::shared_ptr<Session> s = find(id);
		return s && s->ready ? s->mtu.load() : 0;
	}

	std::vector<Event> drain() override {
		std::lock_guard lock(events_mutex_);
		std::vector<Event> out;
		out.swap(events_);
		return out;
	}

	void shutdown() override {
		if (shut_down_.exchange(true)) {
			return;
		}
		std::vector<std::string> ids;
		{
			std::lock_guard lock(sessions_mutex_);
			for (auto &kv : sessions_) {
				ids.push_back(kv.first);
			}
		}
		for (auto &id : ids) {
			disconnect(id);
		}
		post([this] { stop_scan_on_worker(""); });
		{
			std::lock_guard lock(jobs_mutex_);
			quit_ = true;
		}
		jobs_cv_.notify_all();
		if (worker_.joinable()) {
			worker_.join();
		}
	}

private:
	// -- worker --------------------------------------------------------------------------

	void post(std::function<void()> job) {
		{
			std::lock_guard lock(jobs_mutex_);
			if (quit_) {
				return;
			}
			jobs_.push_back(std::move(job));
		}
		jobs_cv_.notify_all();
	}

	void run_worker() {
		init_apartment(apartment_type::multi_threaded);
		for (;;) {
			std::function<void()> job;
			{
				std::unique_lock lock(jobs_mutex_);
				auto until = scanning_ ? scan_deadline_ : std::chrono::steady_clock::now() + 1h;
				jobs_cv_.wait_until(lock, until, [this] { return quit_ || !jobs_.empty(); });
				if (!jobs_.empty()) {
					job = std::move(jobs_.front());
					jobs_.pop_front();
				} else if (quit_) {
					break;
				}
			}
			if (job) {
				run_guarded(job);
			}
			if (scanning_ && std::chrono::steady_clock::now() >= scan_deadline_) {
				run_guarded([this] { stop_scan_on_worker(""); });
			}
		}
		// Close whatever is left, in case shutdown raced a connect.
		std::vector<std::string> ids;
		{
			std::lock_guard lock(sessions_mutex_);
			for (auto &kv : sessions_) {
				ids.push_back(kv.first);
			}
		}
		for (auto &id : ids) {
			run_guarded([this, &id] { close_on_worker(id); });
		}
		uninit_apartment();
	}

	void run_guarded(const std::function<void()> &job) {
		try {
			job();
		} catch (hresult_error const &e) {
			set_error(to_string(e.message()));
		} catch (std::exception const &e) {
			set_error(e.what());
		} catch (...) {
			set_error("unexpected error");
		}
	}

	void probe_adapter() {
		try {
			auto op = BluetoothAdapter::GetDefaultAsync();
			if (!finish(op, 5s) || op.GetResults() == nullptr) {
				set_error("No Bluetooth adapter found");
			} else {
				BluetoothAdapter adapter = op.GetResults();
				if (!adapter.IsLowEnergySupported()) {
					set_error("This Bluetooth adapter does not support Bluetooth LE");
				} else {
					auto radio_op = adapter.GetRadioAsync();
					Radio radio = finish(radio_op, 5s) ? radio_op.GetResults() : nullptr;
					if (radio != nullptr && radio.State() != RadioState::On) {
						set_error("Bluetooth is off");
					} else {
						available_ = true;
					}
				}
			}
		} catch (hresult_error const &e) {
			set_error(to_string(e.message()));
		}
		probe_done_.set_value();
	}

	// -- scanning ------------------------------------------------------------------------

	void start_scan_on_worker(int timeout_ms) {
		scan_deadline_ = std::chrono::steady_clock::now() + std::chrono::milliseconds(std::max(1000, timeout_ms));
		if (scanning_) {
			return;
		}
		{
			std::lock_guard lock(report_mutex_);
			last_report_.clear();
		}
		watcher_ = BluetoothLEAdvertisementWatcher();
		watcher_.ScanningMode(BluetoothLEScanningMode::Active);
		std::weak_ptr<WindowsEngine> weak = weak_from_this();
		received_revoker_ = watcher_.Received(auto_revoke,
				[weak](BluetoothLEAdvertisementWatcher const &, BluetoothLEAdvertisementReceivedEventArgs const &args) {
					if (auto self = weak.lock()) {
						self->on_advertisement(args);
					}
				});
		stopped_revoker_ = watcher_.Stopped(auto_revoke,
				[weak](BluetoothLEAdvertisementWatcher const &, BluetoothLEAdvertisementWatcherStoppedEventArgs const &args) {
					if (auto self = weak.lock()) {
						if (args.Error() != BluetoothError::Success) {
							self->post([self] { self->stop_scan_on_worker("The Bluetooth scan stopped (is Bluetooth on?)"); });
						}
					}
				});
		try {
			watcher_.Start();
		} catch (hresult_error const &e) {
			watcher_ = nullptr;
			push({ "scan_finished", "", "", to_string(e.message()) });
			return;
		}
		scanning_ = true;
	}

	void on_advertisement(BluetoothLEAdvertisementReceivedEventArgs const &args) {
		std::string name = to_string(args.Advertisement().LocalName());
		if (name.empty()) {
			return;
		}
		uint64_t address = args.BluetoothAddress();
		auto now = std::chrono::steady_clock::now();
		{
			std::lock_guard lock(report_mutex_);
			auto it = last_report_.find(address);
			if (it != last_report_.end() && now - it->second < REPORT_EVERY) {
				return;
			}
			last_report_[address] = now;
		}
		Event e;
		e.type = "device_found";
		e.id = address_to_id(address);
		e.name = name;
		e.rssi = args.RawSignalStrengthInDBm();
		push(std::move(e));
	}

	void stop_scan_on_worker(const std::string &error) {
		if (!scanning_) {
			return;
		}
		scanning_ = false;
		received_revoker_.revoke();
		stopped_revoker_.revoke();
		if (watcher_ != nullptr) {
			try {
				watcher_.Stop();
			} catch (...) {
			}
			watcher_ = nullptr;
		}
		push({ "scan_finished", "", "", error });
	}

	// -- connecting ----------------------------------------------------------------------

	void connect_on_worker(const std::string &id) {
		std::shared_ptr<Session> s = find(id);
		if (s) {
			if (s->ready) {
				Event e{ "connected", id };
				e.mtu = s->mtu;
				push(std::move(e));
			}
			return;
		}
		s = std::make_shared<Session>();
		s->id = id;
		if (!id_to_address(id, s->address)) {
			push({ "connect_failed", id, "", "Not a Bluetooth address: " + id });
			return;
		}
		{
			std::lock_guard lock(sessions_mutex_);
			sessions_[id] = s;
		}

		auto fail = [&](const std::string &why) {
			bool asked = s->closing.load();
			release_session(s);
			if (!asked) {
				push({ "connect_failed", id, "", why });
			}
		};

		auto device_op = BluetoothLEDevice::FromBluetoothAddressAsync(s->address);
		if (!finish(device_op, FIND_TIMEOUT) || device_op.GetResults() == nullptr) {
			return fail("not found");
		}
		s->device = device_op.GetResults();
		if (s->closing) {
			return fail("cancelled");
		}

		auto session_op = GattSession::FromDeviceIdAsync(s->device.BluetoothDeviceId());
		if (finish(session_op, GATT_TIMEOUT) && session_op.GetResults() != nullptr) {
			s->gatt_session = session_op.GetResults();
			s->gatt_session.MaintainConnection(true);
			std::weak_ptr<Session> ws = s;
			s->pdu_revoker = s->gatt_session.MaxPduSizeChanged(auto_revoke, [ws](GattSession const &gs, IInspectable const &) {
				if (auto session = ws.lock()) {
					session->mtu = gs.MaxPduSize();
				}
			});
		}

		auto services_op = s->device.GetGattServicesForUuidAsync(SERVICE_UUID, BluetoothCacheMode::Uncached);
		if (!finish(services_op, GATT_TIMEOUT)) {
			return fail("timed out");
		}
		auto services = services_op.GetResults();
		if (services.Status() != GattCommunicationStatus::Success) {
			return fail("could not reach the glove (GATT status " + std::to_string(int(services.Status())) + ")");
		}
		if (services.Services().Size() == 0) {
			return fail("this device has no HexR service");
		}
		s->service = services.Services().GetAt(0);

		auto chars_op = s->service.GetCharacteristicsForUuidAsync(CHARACTERISTIC_UUID, BluetoothCacheMode::Uncached);
		if (!finish(chars_op, GATT_TIMEOUT)) {
			return fail("timed out");
		}
		auto chars = chars_op.GetResults();
		if (chars.Status() != GattCommunicationStatus::Success || chars.Characteristics().Size() == 0) {
			return fail("this device has no HexR characteristic");
		}
		s->characteristic = chars.Characteristics().GetAt(0);

		std::weak_ptr<WindowsEngine> weak = weak_from_this();
		std::string sid = id;
		s->value_revoker = s->characteristic.ValueChanged(auto_revoke,
				[weak, sid](GattCharacteristic const &, GattValueChangedEventArgs const &args) {
					if (auto self = weak.lock()) {
						Event e{ "notified", sid };
						e.data = from_buffer(args.CharacteristicValue());
						self->push(std::move(e));
					}
				});

		// The one subscription for this connection. Done even when cancelled at this point: a
		// glove disconnected without ever having been subscribed can fault.
		auto cccd_op = s->characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
				GattClientCharacteristicConfigurationDescriptorValue::Notify);
		if (!finish(cccd_op, SUBSCRIBE_TIMEOUT) || cccd_op.GetResults() != GattCommunicationStatus::Success) {
			// Haptics still work without readings; carry on.
			set_error("Could not subscribe to the glove's readings");
		}
		if (s->closing) {
			return fail("cancelled");
		}

		if (s->gatt_session != nullptr) {
			s->mtu = s->gatt_session.MaxPduSize();
		}
		std::weak_ptr<Session> ws = s;
		s->status_revoker = s->device.ConnectionStatusChanged(auto_revoke,
				[weak, ws](BluetoothLEDevice const &d, IInspectable const &) {
					auto self = weak.lock();
					auto session = ws.lock();
					if (!self || !session || d.ConnectionStatus() != BluetoothConnectionStatus::Disconnected) {
						return;
					}
					if (session->ready && !session->closing) {
						self->post([self, session] { self->on_link_lost(session); });
					}
				});

		s->ready = true;
		s->writer = std::thread([s] { run_writer(s); });
		Event e{ "connected", id };
		e.mtu = s->mtu;
		push(std::move(e));
	}

	static void run_writer(std::shared_ptr<Session> s) {
		init_apartment(apartment_type::multi_threaded);
		for (;;) {
			std::vector<uint8_t> chunk;
			{
				std::unique_lock lock(s->queue_mutex);
				s->queue_cv.wait(lock, [&] { return s->writer_quit || s->closing || !s->queue.empty(); });
				if (s->writer_quit) {
					break;
				}
				if (s->queue.empty()) {
					if (s->closing) {
						break; // drained
					}
					continue;
				}
				if (s->closing && std::chrono::steady_clock::now() > s->drain_deadline) {
					break;
				}
				chunk = std::move(s->queue.front());
				s->queue.pop_front();
			}
			try {
				auto op = s->characteristic.WriteValueWithResultAsync(to_buffer(chunk), GattWriteOption::WriteWithResponse);
				finish(op, WRITE_TIMEOUT);
			} catch (...) {
				// A failed write is lost, as on the other platforms. The link check reports drops.
			}
		}
		uninit_apartment();
	}

	void on_link_lost(std::shared_ptr<Session> s) {
		{
			std::lock_guard lock(sessions_mutex_);
			auto it = sessions_.find(s->id);
			if (it == sessions_.end() || it->second != s) {
				return;
			}
		}
		if (s->closing) {
			return;
		}
		s->closing = true;
		release_session(s);
		push({ "disconnected", s->id, "", "link lost" });
	}

	void close_on_worker(const std::string &id) {
		std::shared_ptr<Session> s = find(id);
		if (s) {
			s->closing = true;
			release_session(s);
		}
	}

	// Lets the writer finish (it drains what is queued, up to CLOSE_DRAIN), then lets go of
	// every WinRT object so Windows drops the link.
	void release_session(std::shared_ptr<Session> s) {
		{
			std::lock_guard lock(s->queue_mutex);
			if (s->drain_deadline == std::chrono::steady_clock::time_point{}) {
				s->drain_deadline = std::chrono::steady_clock::now() + CLOSE_DRAIN;
			}
			s->queue_cv.notify_all();
		}
		if (s->writer.joinable()) {
			s->writer.join();
		}
		s->ready = false;
		s->value_revoker.revoke();
		s->status_revoker.revoke();
		s->pdu_revoker.revoke();
		try {
			if (s->gatt_session != nullptr) {
				s->gatt_session.MaintainConnection(false);
				s->gatt_session.Close();
			}
			if (s->service != nullptr) {
				s->service.Close();
			}
			if (s->device != nullptr) {
				s->device.Close();
			}
		} catch (...) {
		}
		s->characteristic = nullptr;
		s->service = nullptr;
		s->gatt_session = nullptr;
		s->device = nullptr;
		std::lock_guard lock(sessions_mutex_);
		auto it = sessions_.find(s->id);
		if (it != sessions_.end() && it->second == s) {
			sessions_.erase(it);
		}
	}

	// -- helpers -------------------------------------------------------------------------

	std::shared_ptr<Session> find(const std::string &id) {
		std::lock_guard lock(sessions_mutex_);
		auto it = sessions_.find(id);
		return it == sessions_.end() ? nullptr : it->second;
	}

	void push(Event e) {
		std::lock_guard lock(events_mutex_);
		events_.push_back(std::move(e));
	}

	void set_error(const std::string &message) {
		std::lock_guard lock(error_mutex_);
		error_ = message;
	}

	std::thread worker_;
	std::mutex jobs_mutex_;
	std::condition_variable jobs_cv_;
	std::deque<std::function<void()>> jobs_;
	bool quit_ = false;
	std::atomic<bool> shut_down_{ false };

	std::promise<void> probe_done_;
	std::shared_future<void> probed_;
	std::atomic<bool> available_{ false };
	std::mutex error_mutex_;
	std::string error_;

	BluetoothLEAdvertisementWatcher watcher_{ nullptr };
	BluetoothLEAdvertisementWatcher::Received_revoker received_revoker_;
	BluetoothLEAdvertisementWatcher::Stopped_revoker stopped_revoker_;
	bool scanning_ = false;
	std::chrono::steady_clock::time_point scan_deadline_{};
	std::mutex report_mutex_;
	std::map<uint64_t, std::chrono::steady_clock::time_point> last_report_;

	std::mutex sessions_mutex_;
	std::map<std::string, std::shared_ptr<Session>> sessions_;

	std::mutex events_mutex_;
	std::vector<Event> events_;
};

} // namespace

std::shared_ptr<BleEngine> BleEngine::create() {
	return std::make_shared<WindowsEngine>();
}

} // namespace hexr

#endif
