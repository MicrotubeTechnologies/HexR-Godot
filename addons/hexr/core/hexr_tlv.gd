class_name HexRTlv
## Type-length-value field encoder for glove frames (port of Encode.cs).
##
## A frame is [code][len][func][field...][/code], where len counts the whole frame including
## itself. Each field is a one-byte type tag followed by a little-endian value. Outbound
## frames carry no checksum.

const TAG_U8 := 0x01
const TAG_U16 := 0x02
const TAG_U32 := 0x03
const TAG_U64 := 0x04
const TAG_I8 := 0x05
const TAG_I16 := 0x06
const TAG_I32 := 0x07
const TAG_I64 := 0x08
const TAG_F32 := 0x09
const TAG_F64 := 0x0A
const TAG_BOOL := 0x0B


static func u8(v: int) -> PackedByteArray:
	return PackedByteArray([TAG_U8, v & 0xFF])


static func u16(v: int) -> PackedByteArray:
	var b := PackedByteArray([TAG_U16, 0, 0])
	b.encode_u16(1, v & 0xFFFF)
	return b


static func u32(v: int) -> PackedByteArray:
	var b := PackedByteArray([TAG_U32, 0, 0, 0, 0])
	b.encode_u32(1, v & 0xFFFFFFFF)
	return b


static func u64(v: int) -> PackedByteArray:
	var b := PackedByteArray([TAG_U64])
	b.resize(9)
	b.encode_u64(1, v)
	return b


static func i8(v: int) -> PackedByteArray:
	var b := PackedByteArray([TAG_I8, 0])
	b.encode_s8(1, v)
	return b


static func i16(v: int) -> PackedByteArray:
	var b := PackedByteArray([TAG_I16, 0, 0])
	b.encode_s16(1, v)
	return b


static func i32(v: int) -> PackedByteArray:
	var b := PackedByteArray([TAG_I32, 0, 0, 0, 0])
	b.encode_s32(1, v)
	return b


static func i64(v: int) -> PackedByteArray:
	var b := PackedByteArray([TAG_I64])
	b.resize(9)
	b.encode_s64(1, v)
	return b


static func f32(v: float) -> PackedByteArray:
	var b := PackedByteArray([TAG_F32, 0, 0, 0, 0])
	b.encode_float(1, v)
	return b


static func f64(v: float) -> PackedByteArray:
	var b := PackedByteArray([TAG_F64])
	b.resize(9)
	b.encode_double(1, v)
	return b


static func b1(v: bool) -> PackedByteArray:
	return PackedByteArray([TAG_BOOL, 1 if v else 0])


## Prepends [len][func] to [param payload]. len includes these two bytes.
static func frame(op: int, payload: PackedByteArray) -> PackedByteArray:
	var total := payload.size() + 2
	assert(total <= 255, "HexR frame longer than 255 bytes")
	var out := PackedByteArray([total & 0xFF, op & 0xFF])
	out.append_array(payload)
	return out
