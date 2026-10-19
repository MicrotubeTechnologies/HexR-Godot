#include "hexr_ble_winrt.h"

#include "frame_chunker.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <algorithm>
#include <mutex>
#include <vector>

using namespace godot;

namespace {

std::mutex live_mutex;
std::vector<std::weak_ptr<hexr::BleEngine>> live_engines;

std::string to_std(const String &s) {
	CharString utf8 = s.utf8();
	return std::string(utf8.get_data(), utf8.length());
}

String to_godot(const std::string &s) {
	return String::utf8(s.c_str(), static_cast<int64_t>(s.size()));
}

std::vector<uint8_t> to_bytes(const PackedByteArray &data) {
	return std::vector<uint8_t>(data.ptr(), data.ptr() + data.size());
}

PackedByteArray to_packed(const std::vector<uint8_t> &bytes) {
	PackedByteArray out;
	out.resize(static_cast<int64_t>(bytes.size()));
	if (!bytes.empty()) {
		std::copy(bytes.begin(), bytes.end(), out.ptrw());
	}
	return out;
}

} // namespace

HexRBleWinRT::HexRBleWinRT() {
	engine = hexr::BleEngine::create();
	std::lock_guard lock(live_mutex);
	live_engines.push_back(engine);
}

HexRBleWinRT::~HexRBleWinRT() {
	if (engine) {
		engine->shutdown();
	}
}

void HexRBleWinRT::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &HexRBleWinRT::is_available);
	ClassDB::bind_method(D_METHOD("get_last_error"), &HexRBleWinRT::get_last_error);
	ClassDB::bind_method(D_METHOD("start_scan", "timeout_ms"), &HexRBleWinRT::start_scan);
	ClassDB::bind_method(D_METHOD("stop_scan"), &HexRBleWinRT::stop_scan);
	ClassDB::bind_method(D_METHOD("connect_device", "id"), &HexRBleWinRT::connect_device);
	ClassDB::bind_method(D_METHOD("disconnect_device", "id"), &HexRBleWinRT::disconnect_device);
	ClassDB::bind_method(D_METHOD("is_device_connected", "id"), &HexRBleWinRT::is_device_connected);
	ClassDB::bind_method(D_METHOD("write", "id", "data", "purge"), &HexRBleWinRT::write);
	ClassDB::bind_method(D_METHOD("get_mtu", "id"), &HexRBleWinRT::get_mtu);
	ClassDB::bind_method(D_METHOD("poll_events"), &HexRBleWinRT::poll_events);
	ClassDB::bind_method(D_METHOD("shutdown"), &HexRBleWinRT::shutdown);
	ClassDB::bind_static_method("HexRBleWinRT", D_METHOD("chunk_for_mtu", "data", "max_payload"), &HexRBleWinRT::chunk_for_mtu);
}

bool HexRBleWinRT::is_available() {
	return engine->available();
}

String HexRBleWinRT::get_last_error() {
	return to_godot(engine->last_error());
}

void HexRBleWinRT::start_scan(int timeout_ms) {
	engine->start_scan(timeout_ms);
}

void HexRBleWinRT::stop_scan() {
	engine->stop_scan();
}

void HexRBleWinRT::connect_device(const String &id) {
	engine->connect(to_std(id));
}

void HexRBleWinRT::disconnect_device(const String &id) {
	engine->disconnect(to_std(id));
}

bool HexRBleWinRT::is_device_connected(const String &id) {
	return engine->connected(to_std(id));
}

bool HexRBleWinRT::write(const String &id, const PackedByteArray &data, bool purge) {
	return engine->write(to_std(id), to_bytes(data), purge);
}

int HexRBleWinRT::get_mtu(const String &id) {
	return engine->mtu(to_std(id));
}

Array HexRBleWinRT::poll_events() {
	Array out;
	for (const hexr::Event &e : engine->drain()) {
		Dictionary d;
		d["type"] = to_godot(e.type);
		d["id"] = to_godot(e.id);
		if (e.type == "device_found") {
			d["name"] = to_godot(e.name);
			d["rssi"] = e.rssi;
		} else if (e.type == "connected") {
			d["mtu"] = e.mtu;
		} else if (e.type == "notified") {
			d["data"] = to_packed(e.data);
		} else if (e.type == "scan_finished") {
			d["error"] = to_godot(e.reason);
		} else {
			d["reason"] = to_godot(e.reason);
		}
		out.push_back(d);
	}
	return out;
}

void HexRBleWinRT::shutdown() {
	engine->shutdown();
}

Array HexRBleWinRT::chunk_for_mtu(const PackedByteArray &data, int max_payload) {
	Array out;
	for (const auto &chunk : hexr::chunk_for_mtu(to_bytes(data), max_payload)) {
		out.push_back(to_packed(chunk));
	}
	return out;
}

void HexRBleWinRT::shutdown_all() {
	std::lock_guard lock(live_mutex);
	for (auto &weak : live_engines) {
		if (auto e = weak.lock()) {
			e->shutdown();
		}
	}
	live_engines.clear();
}
