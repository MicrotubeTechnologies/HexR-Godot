class_name HexRDeviceStore
extends RefCounted
## Remembers which physical glove each hand uses, so a reconnect skips the scan and a second
## glove for the same hand in range is not picked by mistake. Kept per transport, since a
## glove's id differs between Android and Windows.

const DEFAULT_PATH := "user://hexr.cfg"
const SECTION := "devices"

## Empty path keeps everything in memory (tests).
var path: String
var _cfg := ConfigFile.new()


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	if not path.is_empty():
		_cfg.load(path)


func get_device(kind: String, hand: int) -> String:
	return _cfg.get_value(SECTION, _key(kind, hand), "")


func set_device(kind: String, hand: int, id: String) -> void:
	if id.is_empty():
		if _cfg.has_section_key(SECTION, _key(kind, hand)):
			_cfg.erase_section_key(SECTION, _key(kind, hand))
	else:
		_cfg.set_value(SECTION, _key(kind, hand), id)
	if not path.is_empty():
		_cfg.save(path)


static func _key(kind: String, hand: int) -> String:
	return "%s_%s" % [kind, HexRTypes.hand_name(hand)]
