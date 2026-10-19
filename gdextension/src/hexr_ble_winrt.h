// HexRBleWinRT: the Godot face of the Windows Bluetooth engine. GDScript reaches it through
// addons/hexr/transport/hexr_windows_transport.gd.
#pragma once

#include "ble_engine.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>

class HexRBleWinRT : public godot::RefCounted {
	GDCLASS(HexRBleWinRT, godot::RefCounted)

	std::shared_ptr<hexr::BleEngine> engine;

protected:
	static void _bind_methods();

public:
	HexRBleWinRT();
	~HexRBleWinRT() override;

	bool is_available();
	godot::String get_last_error();

	void start_scan(int timeout_ms);
	void stop_scan();

	void connect_device(const godot::String &id);
	void disconnect_device(const godot::String &id);
	bool is_device_connected(const godot::String &id);
	bool write(const godot::String &id, const godot::PackedByteArray &data, bool purge);
	int get_mtu(const godot::String &id);

	// Events since the last call, as Dictionaries with a "type" key.
	godot::Array poll_events();
	void shutdown();

	// The write splitter, exposed for the shared fixture test.
	static godot::Array chunk_for_mtu(const godot::PackedByteArray &data, int max_payload);

	// Closes every engine when the extension unloads.
	static void shutdown_all();
};
