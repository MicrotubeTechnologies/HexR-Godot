#!/usr/bin/env python3
"""Checks the Godot HexR Remote against the protocol, using the Unity package's own probe.

Starts tests/harness/remote_harness.tscn in a headless Godot, then talks to it the way the HexR
Companion does: hears its announcement, says hello, reads status and haptics lines, connects a
glove, runs a command, switches scene and asks for the view. Exits non-zero on any mismatch.

    python tools/remote_conformance.py --godot path/to/godot
"""

import argparse
import json
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import hexr_remote_probe as probe  # noqa: E402  (Microtube's own tool, copied from the Unity package)

STATUS_KEYS = ["type", "protocol", "id", "name", "model", "platform", "app", "appVersion", "hexrVersion",
               "paused", "headsetBatteryPct", "scene", "scenes", "gloves", "stream", "commands",
               "allowGloveControl", "allowVideo", "exposeScenes", "controllers", "haptics", "clockUs"]
ANNOUNCE_KEYS = ["hexr", "type", "id", "name", "model", "platform", "app", "appId", "hexrVersion", "control",
                 "video", "startedAt"]

failures = []


def check(cond, what):
    print(("  ok    " if cond else "  FAIL  ") + what)
    if not cond:
        failures.append(what)


class Control:
    def __init__(self, port):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        self.buf = b""
        self.lines = []

    def send(self, obj):
        self.sock.sendall((json.dumps(obj, separators=(",", ":")) + "\n").encode())

    def wait(self, pred, seconds=5):
        end = time.time() + seconds
        while time.time() < end:
            for i, (raw, msg) in enumerate(self.lines):
                if pred(msg):
                    del self.lines[: i + 1]
                    return raw, msg
            self.sock.settimeout(max(0.05, end - time.time()))
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                break
            self.buf += chunk
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                text = line.decode("utf-8")
                ordered = json.loads(text, object_pairs_hook=lambda pairs: pairs)
                self.lines.append((ordered, json.loads(text)))
        return None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", required=True)
    args = ap.parse_args()

    proc = subprocess.Popen([args.godot, "--headless", "--path", str(ROOT), "res://tests/harness/remote_harness.tscn"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    port = None
    output = []

    def pump():
        for line in proc.stdout:
            output.append(line)

    threading.Thread(target=pump, daemon=True).start()
    end = time.time() + 60
    while time.time() < end and port is None:
        for line in list(output):
            if line.startswith("[harness] ready on "):
                port = int(line.split()[-1])
        time.sleep(0.2)
    if port is None:
        print("".join(output[-40:]))
        proc.kill()
        print("The harness did not start.")
        return 1
    try:
        print("discovery")
        seen = probe.discover(4)
        check(len(seen) >= 1, "an announcement was heard on UDP 47800")
        if seen:
            msg = next(iter(seen.values()))
            check(list(msg.keys()) == ANNOUNCE_KEYS, "announce fields in order")
            check(msg.get("control") == port and msg.get("hexrVersion") == "0.10.5", "announce control port and version")

        print("control")
        c = Control(port)
        c.send({"type": "hello", "protocol": 1, "client": "conformance"})
        raw, welcome = c.wait(lambda m: m.get("type") == "hello")
        check(welcome is not None and [k for k, _ in raw] == ["type", "protocol", "id", "control", "video"], "welcome")
        _, left = c.wait(lambda m: m.get("type") == "haptics" and m.get("hand") == "left")
        _, right = c.wait(lambda m: m.get("type") == "haptics" and m.get("hand") == "right")
        check(left and len(left["channels"]) == 6 and right and len(right["channels"]) == 6, "haptics snapshot for both hands")
        raw, status = c.wait(lambda m: m.get("type") == "status")
        check(status is not None and [k for k, _ in raw] == STATUS_KEYS, "status fields in order")
        check(status and [g["hand"] for g in status["gloves"]] == ["left", "right"], "gloves left then right")
        check(status and status["stream"]["state"] == "unsupported", "no view sharing off a headset")
        check(status and status["commands"] == [{"id": "reset", "label": "Reset demo"}], "command listed")
        check(status and [s["index"] for s in status["scenes"]] == [0, 1], "scenes listed")
        print("  " + probe.describe(status) if status else "")

        c.send({"type": "glove", "action": "connect", "hand": "left"})
        _, st = c.wait(lambda m: m.get("type") == "status" and m["gloves"][0]["state"] == "connected", 10)
        check(st is not None, "left glove connects from a phone")
        if st:
            check(len(st["gloves"][0]["pressureDeciKPa"]) == 7, "seven pressure readings")
        c.send({"type": "release", "hand": "left"})
        c.send({"type": "command", "id": "reset"})
        c.send({"type": "command", "id": "nope"})
        _, err = c.wait(lambda m: m.get("type") == "error")
        check(err is not None and err["request"] == "command" and "nope" in err["message"], "unknown command refused")
        c.send({"type": "stream", "action": "start"})
        c.send({"type": "glove", "action": "disconnect", "hand": "left"})
        _, st = c.wait(lambda m: m.get("type") == "status" and m["gloves"][0]["state"] == "disconnected", 5)
        check(st is not None, "left glove disconnects from a phone")
        check(any("[harness] reset ran" in line for line in output), "the command ran in the app")
        c.send({"type": "scene", "index": 1})
        _, st = c.wait(lambda m: m.get("type") == "status" and m["scene"]["index"] == 1, 5)
        check(st is not None, "scene switch from a phone")
        c.sock.close()
    finally:
        proc.kill()
    print()
    print("PASS" if not failures else f"FAIL: {len(failures)} check(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
