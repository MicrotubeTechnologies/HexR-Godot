#!/usr/bin/env python3
"""Checks that the addon's version agrees everywhere it is written, and prints it.

plugin.cfg, HexRManager.VERSION and the top entry of CHANGELOG.md must match. On a tag build,
the tag (vX.Y.Z) must match too. Stdlib only.

    python tools/check_version.py [--tag v0.1.0]
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main(argv):
    plugin = re.search(r'^version="([^"]+)"', (ROOT / "addons/hexr/plugin.cfg").read_text(encoding="utf-8"), re.M)
    manager = re.search(r'^const VERSION := "([^"]+)"',
                        (ROOT / "addons/hexr/core/hexr_manager.gd").read_text(encoding="utf-8"), re.M)
    changelog = re.search(r"^## \[?(\d+\.\d+\.\d+)", (ROOT / "CHANGELOG.md").read_text(encoding="utf-8"), re.M)
    found = {
        "plugin.cfg": plugin.group(1) if plugin else None,
        "HexRManager.VERSION": manager.group(1) if manager else None,
        "CHANGELOG.md": changelog.group(1) if changelog else None,
    }
    if "--tag" in argv:
        found["tag"] = argv[argv.index("--tag") + 1].lstrip("v")
    versions = set(found.values())
    if len(versions) != 1 or None in versions:
        for k, v in found.items():
            print(f"{k}: {v}", file=sys.stderr)
        print("Versions disagree.", file=sys.stderr)
        return 1
    print(versions.pop())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
