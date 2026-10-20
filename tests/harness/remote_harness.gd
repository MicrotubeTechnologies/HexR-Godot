extends Node
## A headless app for tools/remote_conformance.py: the HexR autoload with two simulated gloves,
## and a HexR Remote announcing on 127.0.0.1 with a command and two scenes exposed.
##
##   godot --headless --path . res://tests/harness/remote_harness.tscn


func _ready() -> void:
	var sim := HexRSimulatedTransport.new()
	sim.add_glove(HexRSimulatedGlove.new("SIM:LEFT", HexRTypes.NAME_LEFT))
	sim.add_glove(HexRSimulatedGlove.new("SIM:RIGHT", HexRTypes.NAME_RIGHT))
	var hub := HexRManager.get_instance()
	hub.setup(sim, HexRDeviceStore.new(""))
	HexRRemote.register_command("reset", "Reset demo", func() -> void: print("[harness] reset ran"))
	var remote := HexRRemote.new()
	remote.announce_address = "127.0.0.1"
	remote.expose_scenes = true
	ProjectSettings.set_setting(SceneLoader.SETTING,
			PackedStringArray(["res://tests/harness/remote_harness.tscn", "res://tests/smoke/ble_smoke.tscn"]))
	add_child(remote)
	print("[harness] ready on %d" % remote.get_control_port())
