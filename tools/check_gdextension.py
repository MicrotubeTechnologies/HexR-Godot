#!/usr/bin/env python3
"""Checks that every library the Bluetooth extension lists is in the addon, so a release zip
cannot ship an extension that fails to load on one platform. Stdlib only.

A macOS framework must hold a binary named after the framework: without an Info.plist, that is
where Godot looks for it.

    python tools/check_gdextension.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXTENSION = ROOT / "addons/hexr/bin/hexr_ble_win.gdextension"


def main():
    text = EXTENSION.read_text(encoding="utf-8")
    libraries = text.split("[libraries]", 1)[1].split("\n[", 1)[0]
    missing = []
    count = 0
    for key, res_path in re.findall(r'^(\S+)\s*=\s*"res://([^"]+)"', libraries, re.M):
        count += 1
        path = ROOT / res_path
        if path.suffix == ".framework":
            path = path / path.stem
        if not path.is_file():
            missing.append(f"  {key}: {path.relative_to(ROOT)}")
    if count == 0:
        print(f"No libraries found in {EXTENSION.name}.", file=sys.stderr)
        return 1
    if missing:
        print(f"{len(missing)} of {count} libraries missing:", file=sys.stderr)
        print("\n".join(missing), file=sys.stderr)
        return 1
    print(f"All {count} libraries present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
