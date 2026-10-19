// Everywhere but Windows: the class loads, so the editor raises no errors, but has no Bluetooth.
// Android uses the HexRBle Java plugin instead, and the addon falls back to simulated gloves.
#ifndef _WIN32

#include "ble_engine.h"

namespace hexr {

namespace {

class StubEngine : public BleEngine {
public:
	bool available() override { return false; }
	std::string last_error() override { return "Bluetooth through HexRBleWinRT is Windows only"; }
	void start_scan(int) override {}
	void stop_scan() override {}
	void connect(const std::string &) override {}
	void disconnect(const std::string &) override {}
	bool connected(const std::string &) override { return false; }
	bool write(const std::string &, const std::vector<uint8_t> &, bool) override { return false; }
	int mtu(const std::string &) override { return 0; }
	std::vector<Event> drain() override { return {}; }
	void shutdown() override {}
};

} // namespace

std::shared_ptr<BleEngine> BleEngine::create() {
	return std::make_shared<StubEngine>();
}

} // namespace hexr

#endif
