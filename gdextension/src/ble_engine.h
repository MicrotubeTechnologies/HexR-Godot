// Bluetooth LE engine behind the HexRBleWinRT Godot class. Plain C++ so the WinRT code never
// shares a translation unit with godot-cpp's headers.
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace hexr {

struct Event {
	std::string type; // device_found, scan_finished, connected, connect_failed, disconnected, notified
	std::string id;
	std::string name;
	std::string reason; // connect_failed / disconnected reason, scan_finished error
	int rssi = 0;
	int mtu = 0;
	std::vector<uint8_t> data;
};

class BleEngine {
public:
	// The Windows engine on Windows; elsewhere one that reports Bluetooth as unavailable.
	static std::shared_ptr<BleEngine> create();

	virtual ~BleEngine() = default;

	virtual bool available() = 0;
	virtual std::string last_error() = 0;

	virtual void start_scan(int timeout_ms) = 0;
	virtual void stop_scan() = 0;

	// Connects, subscribes to notifications once, and reports "connected" with the MTU.
	virtual void connect(const std::string &id) = 0;
	// Sends what is queued, then closes. Reports nothing.
	virtual void disconnect(const std::string &id) = 0;
	virtual bool connected(const std::string &id) = 0;
	// Queues data, cut on frame boundaries to fit MTU - 3. purge drops what is queued first.
	virtual bool write(const std::string &id, const std::vector<uint8_t> &data, bool purge) = 0;
	virtual int mtu(const std::string &id) = 0;

	// Events since the last call, oldest first.
	virtual std::vector<Event> drain() = 0;
	virtual void shutdown() = 0;
};

} // namespace hexr
