class_name HexRF32
## 32-bit float arithmetic for the glove encoder.
##
## The Unity package computes intensity, speed and peak-ratio bytes in 32-bit floats; GDScript
## floats are 64-bit, and the difference changes real bytes (a speed of 0.23 encodes as 22 in
## float32 and 23 in float64). Every step here is rounded through a 4-byte float so the frames
## match the Unity package, and tools/gen_golden_frames.py does the same in Python.


## Rounds [param x] to the nearest float32.
static func r(x: float) -> float:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_float(0, x)
	return b.decode_float(0)


## Unity's LinerMapping in float32: (b2 - b1) * (x - pre1) / (pre2 - pre1) + b1.
static func lin_map(pre1: float, pre2: float, x: float, b1: float, b2: float) -> float:
	pre1 = r(pre1)
	pre2 = r(pre2)
	x = r(x)
	b1 = r(b1)
	b2 = r(b2)
	if pre1 == pre2:
		return 0.0
	var t := r(r(b2 - b1) * r(x - pre1))
	t = r(t / r(pre2 - pre1))
	return r(t + b1)


## Unity's Clamp(lower, upper, input) in float32.
static func clamp32(lower: float, upper: float, x: float) -> float:
	lower = r(lower)
	upper = r(upper)
	x = r(x)
	if x > upper:
		return upper
	if x < lower:
		return lower
	return x


## C# (byte)float: truncates toward zero.
static func to_byte(x: float) -> int:
	return int(x) & 0xFF
