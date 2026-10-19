#!/usr/bin/env python3
"""Generate tests/fixtures/golden_frames.json: the bytes the Unity package sends.

This is an independent reimplementation of the Unity encoder
(com.microtube.hexr Runtime/HaptGlove/Haptics.cs and Encode.cs) in strict IEEE
float32. Unity does the intensity, speed and peak-ratio maths in 32-bit floats;
doing it in 64-bit changes some bytes (a speed of 0.23 encodes as 22 in float32
and 23 in float64). Every arithmetic step here is rounded to float32, the same
way the GDScript encoder does it, so the two can be compared byte for byte.

Stdlib only. Run:  python tools/gen_golden_frames.py  [--check]
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "golden_frames.json"


def f(x: float) -> float:
    """Round to float32."""
    return struct.unpack("<f", struct.pack("<f", x))[0]


F01 = f(0.1)
F02 = f(0.2)
F08 = f(0.8)


def lin_map(pre1, pre2, x, b1, b2):
    pre1, pre2, x, b1, b2 = f(pre1), f(pre2), f(x), f(b1), f(b2)
    if pre1 == pre2:
        return 0.0
    t = f(f(b2 - b1) * f(x - pre1))
    t = f(t / f(pre2 - pre1))
    return f(t + b1)


def clamp(lower, upper, x):
    lower, upper, x = f(lower), f(upper), f(x)
    if x > upper:
        return upper
    if x < lower:
        return lower
    return x


def to_byte(x: float) -> int:
    # C# (byte)float truncates toward zero.
    return int(x) & 0xFF


# -- TLV (Encode.cs) ---------------------------------------------------------

def u8(n):
    return bytes([0x01, n & 0xFF])


def u16(n):
    return bytes([0x02, n & 0xFF, (n >> 8) & 0xFF])


def f32(x):
    return bytes([0x09]) + struct.pack("<f", x)


def frame(op, payload: bytes) -> bytes:
    return bytes([len(payload) + 2, op]) + payload


def state_byte(on):
    return 0 if on else 2


# -- encoders (Haptics.cs) ---------------------------------------------------

def pressure(finger, on, intensity, speed):
    intensity = clamp(F01, 1, intensity)
    kpa = lin_map(F01, 1, intensity, 15, 50)
    speed = clamp(F01, 1, speed)
    speed = lin_map(F01, 1, speed, F01, 1)
    speed = f(speed * 100)
    return frame(0x04, f32(0.0) + u8(finger) + u8(state_byte(on)) + f32(kpa) + u8(to_byte(speed)))


def vib_intensity(frequency, fake):
    kpa = 0.0
    peak = 0
    fake = clamp(F01, 1, fake)
    if frequency >= 10:
        kpa = 50.0
        peak = to_byte(lin_map(F01, 1, fake, 20, 50))
    elif frequency >= 5:
        kpa = 50.0
        bound1 = to_byte(lin_map(5, 10, frequency, 20, 20))
        peak = to_byte(lin_map(F01, 1, fake, bound1, 50))
    elif frequency >= F01:
        peak = 50
        kpa = lin_map(F01, 1, fake, 15, 50)
    return kpa, peak


def vibration(finger, on, frequency, intensity):
    frequency = clamp(F01, 40, frequency)
    kpa, peak = vib_intensity(frequency, intensity)
    return frame(0x07, f32(frequency) + u8(finger) + u8(state_byte(on)) + f32(kpa) + u8(peak))


def pulse(finger, on, frequency, intensity, count):
    frequency = clamp(F01, 40, frequency)
    kpa, peak = vib_intensity(frequency, intensity)
    count = max(1, min(1000, int(count)))
    return frame(0x08, f32(frequency) + u8(finger) + u8(state_byte(on)) + f32(kpa) + u8(peak) + u16(count))


def _end_kpa(end_intensity):
    end_intensity = f(end_intensity)
    if end_intensity < F01:
        return 0.0
    return lin_map(F01, 1, clamp(F01, 1, end_intensity), 15, 50)


def vibration_ramped(finger, on, frequency, intensity, peak_ratio, speed, end_intensity):
    frequency = clamp(F01, 2, frequency)
    intensity = clamp(F01, 1, intensity)
    kpa = lin_map(F01, 1, intensity, 15, 50)
    peak = to_byte(f(clamp(F02, F08, peak_ratio) * 100))
    speed = f(lin_map(F01, 1, clamp(F01, 1, speed), F01, 1) * 100)
    return frame(0x09, f32(frequency) + u8(finger) + u8(state_byte(on)) + f32(kpa) + u8(peak)
                 + u8(to_byte(speed)) + f32(_end_kpa(end_intensity)))


def pulse_ramped(finger, on, frequency, intensity, peak_ratio, speed, count, end_intensity):
    frequency = clamp(F01, 2, frequency)
    intensity = clamp(F01, 1, intensity)
    kpa = lin_map(F01, 1, intensity, 15, 50)
    peak = to_byte(f(clamp(F02, F08, peak_ratio) * 100))
    count = max(1, min(1000, int(count)))
    speed = f(lin_map(F01, 1, clamp(F01, 1, speed), F01, 1) * 100)
    return frame(0x0A, f32(frequency) + u8(finger) + u8(state_byte(on)) + f32(kpa) + u8(peak)
                 + u16(count) + u8(to_byte(speed)) + f32(_end_kpa(end_intensity)))


def pump(start, source_kpa=80):
    return frame(0x02, u8(1 if start else 0) + u8(source_kpa if start else 0))


def release(fingers=range(6)):
    out = b""
    for ch in fingers:
        out += vibration(ch, False, 1.0, 0.1) + pressure(ch, False, 0.0, 1.0)
    return out


# -- reference frames from other sources (must agree) -----------------------

REFERENCES = {
    # HexR - Companion tests/test_protocol.py: Index, on, full intensity, full speed.
    "companion_index_full": (pressure(1, True, 1.0, 1.0), "12040900000000010101000900004842 0164"),
    "index_press_0.8": (pressure(1, True, 0.8, 1.0), "120409000000000101010009 8ee32842 0164"),
    "index_pressure_release": (pressure(1, False, 0.0, 1.0), "12040900000000010101020900007041 0164"),
    "palm_vibration_release": (vibration(5, False, 1.0, 0.1), "1207090000803f010501020900007041 0132"),
    "index_vibration_18hz_0.8": (vibration(1, True, 18.0, 0.8), "12070900009041010101000900004842 012b"),
    "pump_start": (pump(True), "060201010150"),
    "pump_stop": (pump(False), "060201000100"),
}


def check_references() -> bool:
    ok = True
    for name, (got, want) in REFERENCES.items():
        want_b = bytes.fromhex(want.replace(" ", ""))
        if got != want_b:
            ok = False
            print(f"MISMATCH {name}: got {got.hex(' ')} want {want_b.hex(' ')}")
    rel = release()
    if len(rel) != 216:
        ok = False
        print(f"MISMATCH release-all length {len(rel)} != 216")
    return ok


def build_cases():
    cases = []

    def add(kind, args, data):
        cases.append({"kind": kind, "args": args, "hex": data.hex()})

    # Pressure: every finger, both states, intensity and speed swept in 0.01 steps
    # (the steps where float32 and float64 disagree are the point of this file).
    for i in range(0, 121, 1):
        v = round(-0.1 + i * 0.01, 2)  # -0.10 .. 1.10, exercises the clamps
        add("pressure", [1, True, v, 1.0], pressure(1, True, v, 1.0))
        add("pressure", [2, True, 0.5, v], pressure(2, True, 0.5, v))
    for finger in range(6):
        for on in (True, False):
            add("pressure", [finger, on, 0.7, 0.4], pressure(finger, on, 0.7, 0.4))

    # Vibration (0x07): frequency sweep across the 1 / 5 / 10 Hz branches and intensities.
    freqs = [0.0, 0.05, 0.1, 0.5, 0.99, 1.0, 2.0, 4.99, 5.0, 7.5, 9.99, 10.0, 18.0, 25.0, 40.0, 55.0]
    for fr in freqs:
        for inten in (0.0, 0.1, 0.25, 0.5, 0.8, 1.0, 1.5):
            add("vibration", [3, True, fr, inten], vibration(3, True, fr, inten))
    add("vibration", [0, False, 1.0, 0.1], vibration(0, False, 1.0, 0.1))

    # Pulse (0x08).
    for fr in (0.5, 3.0, 6.0, 12.0, 40.0):
        for count in (0, 1, 2, 250, 1000, 5000):
            add("pulse", [4, True, fr, 0.6, count], pulse(4, True, fr, 0.6, count))

    # Ramped vibration (0x09) and ramped pulse (0x0A).
    for fr in (0.05, 0.5, 1.0, 2.0, 3.0):
        for peak in (0.1, 0.2, 0.33, 0.5, 0.8, 0.9):
            for end in (0.0, 0.05, 0.1, 0.5, 1.0):
                add("vibration_ramped", [5, True, fr, 0.6, peak, 0.37, end],
                    vibration_ramped(5, True, fr, 0.6, peak, 0.37, end))
    for count in (1, 3, 1000, 2000):
        add("pulse_ramped", [0, True, 1.5, 0.9, 0.4, 0.23, count, 0.3],
            pulse_ramped(0, True, 1.5, 0.9, 0.4, 0.23, count, 0.3))

    add("pump", [True, 80], pump(True))
    add("pump", [False, 80], pump(False))
    add("release", [[0, 1, 2, 3, 4, 5]], release())
    add("release", [[1, 5]], release([1, 5]))
    return cases


# -- write splitting (shared by the GDScript, Java and C++ chunkers) ---------

SPLIT_OUT = OUT.parent / "frames_split.json"


def split_frames(data: bytes):
    out, i = [], 0
    while i < len(data):
        n = data[i]
        if n <= 0 or n > len(data) - i:
            break
        out.append(data[i:i + n])
        i += n
    return out


def chunk_for_mtu(data: bytes, max_payload: int):
    if not data:
        return []
    if max_payload <= 0 or len(data) <= max_payload:
        return [data]
    out, cur = [], b""
    for fr in split_frames(data):
        if cur and len(cur) + len(fr) > max_payload:
            out.append(cur)
            cur = b""
        cur += fr
    if cur:
        out.append(cur)
    return out


def build_split_cases():
    rel = release()
    mixed = pressure(1, True, 0.8, 1.0) + pulse_ramped(0, True, 1.5, 0.9, 0.4, 0.23, 3, 0.3) \
        + vibration(2, True, 18.0, 0.5) + vibration_ramped(5, True, 1.0, 0.6, 0.5, 0.5, 0.2)
    cases = []
    for name, data in (("release_all", rel), ("mixed", mixed), ("single", pressure(0, True, 0.5, 0.5))):
        for mtu in (23, 27, 64, 185, 247, 512):
            chunks = chunk_for_mtu(data, mtu - 3)
            cases.append({"name": f"{name}@mtu{mtu}", "hex": data.hex(), "max_payload": mtu - 3,
                          "chunks": [c.hex() for c in chunks]})
    # The firmware stops walking at an impossible length; so does split_frames.
    bad = pressure(1, True, 0.5, 0.5) + bytes([0x40, 0x04, 0x01])
    cases.append({"name": "truncated_tail", "hex": bad.hex(), "max_payload": 20,
                  "chunks": [c.hex() for c in chunk_for_mtu(bad, 20)]})
    return cases


def _emit(path: Path, data, check: bool) -> bool:
    text = json.dumps(data, indent=1) + "\n"
    if check:
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            print(f"{path} is out of date; run tools/gen_golden_frames.py")
            return False
        print(f"{path.name} is current")
        return True
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {path}")
    return True


def main(argv):
    if not check_references():
        print("Reference frames do not match; the float32 emulation is wrong.")
        return 1
    check = "--check" in argv
    ok = _emit(OUT, {
        "generator": "tools/gen_golden_frames.py",
        "source": "com.microtube.hexr 0.10.5 Runtime/HaptGlove/Haptics.cs (float32)",
        "cases": build_cases(),
    }, check)
    ok = _emit(SPLIT_OUT, {
        "generator": "tools/gen_golden_frames.py",
        "note": "Writes are cut on frame boundaries to fit MTU - 3. Shared by the GDScript, Java and C++ tests.",
        "cases": build_split_cases(),
    }, check) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
