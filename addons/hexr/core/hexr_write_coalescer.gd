class_name HexRWriteCoalescer
extends RefCounted
## Batches haptic commands into at most one Bluetooth write per interval.
##
## Headsets drop or delay writes sent faster than the link drains them, and a grab can produce
## a dozen commands in one frame. Like the Unity package's Quest buffer, commands queue here and
## go out together, at most once every [member min_interval_ms] (strictly more than that since
## the last write). Releases skip the queue: see [method take_all].

## Minimum time between writes. 100 matches the Unity package; 0 sends every frame.
var min_interval_ms: int = 100

var _pending := PackedByteArray()
var _last_write_ms: int = -1


func push(data: PackedByteArray) -> void:
	_pending.append_array(data)


func has_pending() -> bool:
	return not _pending.is_empty()


func pending_size() -> int:
	return _pending.size()


## Returns the queued bytes if a write is due at [param now_ms], else an empty array.
func take_due(now_ms: int) -> PackedByteArray:
	if _pending.is_empty():
		return PackedByteArray()
	if _last_write_ms >= 0 and min_interval_ms > 0 and now_ms - _last_write_ms <= min_interval_ms:
		return PackedByteArray()
	_last_write_ms = now_ms
	var out := _pending
	_pending = PackedByteArray()
	return out


## Drops the queue: the commands in it belong to a grab that is already over.
func clear() -> void:
	_pending = PackedByteArray()


## Takes everything queued without waiting, and counts it as a write.
func take_all(now_ms: int) -> PackedByteArray:
	var out := _pending
	_pending = PackedByteArray()
	if not out.is_empty():
		_last_write_ms = now_ms
	return out
