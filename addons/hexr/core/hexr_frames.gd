class_name HexRFrames
## Splitting concatenated outbound frames.
##
## Several frames can go in one Bluetooth write; the glove walks them by their length byte.
## But the glove ignores a write longer than one packet (MTU - 3 bytes), so a batch is cut
## into packets on frame boundaries, never through a frame.


## Splits [param data] into frames by their length byte, the way the firmware walks a write.
## Stops at the first impossible length; the rest is discarded, as the firmware would.
static func split_frames(data: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var i := 0
	while i < data.size():
		var length := data[i]
		if length <= 0 or length > data.size() - i:
			break
		out.append(data.slice(i, i + length))
		i += length
	return out


## Packs whole frames from [param data] into writes of at most [param max_payload] bytes.
## A single frame longer than [param max_payload] goes alone; the glove will drop it, which
## only happens on links stuck at the minimum MTU.
static func chunk_for_mtu(data: PackedByteArray, max_payload: int) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if data.is_empty():
		return out
	if max_payload <= 0 or data.size() <= max_payload:
		out.append(data)
		return out
	var current := PackedByteArray()
	for frame in split_frames(data):
		if not current.is_empty() and current.size() + frame.size() > max_payload:
			out.append(current)
			current = PackedByteArray()
		current.append_array(frame)
	if not current.is_empty():
		out.append(current)
	return out


static func to_hex(data: PackedByteArray, sep: String = " ") -> String:
	var parts := PackedStringArray()
	for b in data:
		parts.append("%02x" % b)
	return sep.join(parts)


static func from_hex(text: String) -> PackedByteArray:
	return text.replace(" ", "").hex_decode()
