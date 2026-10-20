#!/usr/bin/env python3
"""Generate docs/API.md, the addon's API reference, from its GDScript doc comments.

Godot shows the same ## comments in its built-in help (F1), so the editor and this file can't
disagree. Only top-level members are read: signals, exported and plain properties, methods,
enums, and constants that carry a doc comment. Names starting with "_" are private and left out.

Stdlib only. Run:  python tools/gen_api_docs.py  [--check]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "addons" / "hexr"
OUT = ROOT / "docs" / "API.md"

# The classes a game uses, in reading order. Everything else is listed under "Internals".
SECTIONS = [
    ("Gloves and connection", ["HexRManager", "HexRGlove", "HexRHaptics", "HexRTypes", "HexRFrameDecoder"]),
    ("Hands", ["HexRRig", "HexRTrackedHand", "HexRTouchPoint", "HexRFingerUseTracking"]),
    ("Haptics", ["HexRPressureController"]),
    ("Scene nodes", ["HexRGrabbable", "HexRPhysicalButton", "HexRSpecialHaptics", "HexRUsable",
                     "HexRProximityCheck", "HexRInteractableHaptics", "HexRXRToolsBinding"]),
    ("Menu and HexR Remote", ["HexRFloatingMenu", "HexRRemote"]),
]
AUTOLOADS = {"HexRManager": "HexR"}


class Member:
    def __init__(self, kind: str, name: str, decl: str, doc: list[str]):
        self.kind, self.name, self.decl, self.doc = kind, name, decl, doc


class GdClass:
    def __init__(self, path: Path):
        self.path = path
        self.name = ""
        self.extends = ""
        self.doc: list[str] = []
        self.members: list[Member] = []


def strip_comment(line: str) -> str:
    """Drops a trailing # comment that is not inside a string."""
    quote = ""
    for i, ch in enumerate(line):
        if quote:
            if ch == quote and line[i - 1] != "\\":
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:i].rstrip()
    return line.rstrip()


def depth(text: str) -> int:
    d = 0
    for ch in strip_comment(text):
        d += ch in "([{"
        d -= ch in ")]}"
    return d


def parse(path: Path) -> GdClass:
    c = GdClass(path)
    lines = path.read_text(encoding="utf-8").splitlines()
    pending: list[str] = []
    seen_member = False
    annotation = ""
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if line.startswith("##"):
            pending.append(line[3:] if line.startswith("## ") else line[2:])
            continue
        if not line.strip():
            if pending and not c.doc and not seen_member:
                c.doc = pending
            pending = []
            continue
        if line[0] in " \t":
            continue  # bodies, inner classes, setters
        if line.startswith("#"):
            continue
        # Gather a declaration that runs over several lines (long signatures, enums).
        text = line
        while depth(text) > 0 and i < len(lines):
            text += " " + lines[i].strip()
            i += 1
        text = strip_comment(text)
        doc, pending = pending, []

        m = re.match(r"class_name\s+(\w+)", text)
        if m:
            c.name = m.group(1)
            continue
        m = re.match(r"extends\s+(\S+)", text)
        if m:
            c.extends = m.group(1)
            if doc and not c.doc:
                c.doc = doc
            continue
        if text.startswith("@") and not re.search(r"\bvar\s", text):
            # An annotation on a line of its own (@tool, @icon, or @export above its var).
            if text.startswith("@export") and not re.match(r"@export_(group|subgroup|category)\b", text):
                annotation = text
                pending = doc
            continue
        m = re.match(r"(@export\w*(?:\(.*?\))?\s+)?(@onready\s+)?(static\s+)?var\s+(\w+)(.*)$", text)
        if m:
            exported = bool(m.group(1)) or bool(annotation)
            annotation = ""
            name = m.group(4)
            seen_member = True
            if not name.startswith("_"):
                decl = ("static " if m.group(3) else "") + (name + m.group(5)).rstrip().rstrip(":").rstrip()
                c.members.append(Member("export" if exported else "var", name, decl, doc))
            continue
        annotation = ""
        m = re.match(r"signal\s+(\w+)(.*)$", text)
        if m:
            seen_member = True
            if not m.group(1).startswith("_"):
                c.members.append(Member("signal", m.group(1), (m.group(1) + m.group(2)).strip(), doc))
            continue
        m = re.match(r"(static\s+)?func\s+(\w+)\s*(\(.*)$", text)
        if m:
            seen_member = True
            name = m.group(2)
            if not name.startswith("_"):
                sig = re.sub(r"\s+", " ", m.group(3)).rstrip().rstrip(":").rstrip()
                sig = sig.replace("( ", "(").replace(" )", ")").replace(", )", ")")
                decl = ("static " if m.group(1) else "") + name + sig
                c.members.append(Member("func", name, decl, doc))
            continue
        m = re.match(r"enum\s+(\w+)\s*\{(.*)\}", text)
        if m:
            seen_member = True
            values = [v.split("=")[0].strip() for v in m.group(2).split(",") if v.strip()]
            c.members.append(Member("enum", m.group(1), m.group(1) + " { " + ", ".join(values) + " }", doc))
            continue
        m = re.match(r"const\s+(\w+)(.*)$", text)
        if m:
            seen_member = True
            if doc and not m.group(1).startswith("_"):
                c.members.append(Member("const", m.group(1), (m.group(1) + m.group(2)).strip(), doc))
            continue
        seen_member = seen_member or text.startswith("class ")
    return c


def bbcode(text: str, known: set[str]) -> str:
    """Godot doc-comment BBCode to Markdown, for one paragraph or a list item."""
    def ref(name: str) -> str:
        return f"[`{name}`](#{name.lower()})" if name in known else f"`{name}`"

    text = re.sub(r"\[code\](.*?)\[/code\]", r"`\1`", text)
    text = re.sub(r"\[b\](.*?)\[/b\]", r"**\1**", text)
    text = re.sub(r"\[i\](.*?)\[/i\]", r"*\1*", text)
    text = re.sub(r"\[method ([\w.]+)\]", r"`\1()`", text)
    text = re.sub(r"\[(?:member|signal|param|constant|enum|annotation) ([\w.]+)\]", r"`\1`", text)
    text = re.sub(r"\s*\[br\]\s*", "\n", text).strip("\n")
    text = re.sub(r"\[([A-Z]\w*)\]", lambda mm: ref(mm.group(1)), text)
    return text


def doc_blocks(doc: list[str], known: set[str]) -> list[str]:
    """Paragraphs of Markdown; [codeblock] sections become fenced GDScript."""
    out, para, code = [], [], None
    for raw in doc:
        line = raw.rstrip()
        if code is not None:
            if line.strip() == "[/codeblock]":
                out.append("```gdscript\n" + "\n".join(code).replace("\t", "    ") + "\n```")
                code = None
            else:
                code.append(line)
            continue
        if line.strip() == "[codeblock]":
            if para:
                out.append(bbcode(" ".join(para), known))
                para = []
            code = []
        elif not line.strip():
            if para:
                out.append(bbcode(" ".join(para), known))
                para = []
        else:
            para.append(line.strip())
    if para:
        out.append(bbcode(" ".join(para), known))
    return out


def first_sentence(doc: list[str], known: set[str]) -> str:
    blocks = doc_blocks(doc, known)
    if not blocks:
        return ""
    m = re.match(r"(.+?[.!?])(\s|$)", blocks[0])
    return m.group(1) if m else blocks[0]


def short_decl(decl: str) -> str:
    """Keeps a long default value (a table of offsets, say) out of the heading."""
    if len(decl) <= 90:
        return decl
    m = re.match(r"(.*?)\s*:?=\s*", decl)
    return (m.group(1) if m else decl[:90]) + " = …"


def item(m: Member, known: set[str]) -> str:
    blocks = doc_blocks(m.doc, known)
    decl = short_decl(m.decl) if m.kind in ("var", "export", "const") else m.decl
    head = f"- **`{decl}`**"
    if not blocks:
        return head
    lines = [head + " — " + blocks[0]]
    for b in blocks[1:]:
        lines.append("")
        lines.extend(("  " + l) if l else "" for l in b.splitlines())
    return "\n".join(lines)


GROUPS = [("signal", "Signals"), ("export", "Inspector properties"), ("var", "Properties"),
          ("func", "Methods"), ("enum", "Enums"), ("const", "Constants")]


def render(classes: dict[str, GdClass], version: str) -> str:
    known = set(classes)
    listed = [n for _, names in SECTIONS for n in names]
    missing = [n for n in listed if n not in classes]
    if missing:
        raise SystemExit("gen_api_docs: no such class in the addon: " + ", ".join(missing))

    out = [
        "# HexR Godot addon: API reference",
        "",
        f"Addon {version}. Generated from the addon's doc comments by `tools/gen_api_docs.py`;",
        "edit those, not this file. The same text is in Godot's built-in help: press **F1** in the",
        "editor and search for `HexR`.",
        "",
        "Hands and fingers are the `HexRTypes.Hand` and `HexRTypes.Finger` enums (`int` in",
        "signatures). Intensities are 0.1–1 (about 15–50 kPa); frequencies are in Hz.",
        "",
        "## Contents",
        "",
    ]
    for title, names in SECTIONS:
        links = ", ".join(f"[`{n}`](#{n.lower()})" for n in names)
        out.append(f"- **{title}**: {links}")
    out.append("- [Internals](#internals)")
    out.append("")

    for title, names in SECTIONS:
        out += ["---", "", f"# {title}", ""]
        for n in names:
            c = classes[n]
            rel = c.path.relative_to(ROOT).as_posix()
            meta = f"*extends `{c.extends or 'RefCounted'}` · `{rel}`"
            if n in AUTOLOADS:
                meta += f" · autoload `{AUTOLOADS[n]}`"
            out += [f"## {n}", "", meta + "*", ""]
            for b in doc_blocks(c.doc, known):
                out += [b, ""]
            for kind, heading in GROUPS:
                ms = [m for m in c.members if m.kind == kind]
                if ms:
                    out += [f"### {heading}", ""]
                    out += [item(m, known) for m in ms]
                    out.append("")

    out += ["---", "", "# Internals", "",
            "Used by the classes above; most games never touch them. Their doc comments are in the",
            "source and in Godot's built-in help.", "",
            "| Class | File | What it is |", "|---|---|---|"]
    for n in sorted(set(classes) - set(listed)):
        c = classes[n]
        out.append(f"| `{n}` | `{c.path.relative_to(ROOT).as_posix()}` | {first_sentence(c.doc, known)} |")
    out.append("")
    return "\n".join(out)


def main(argv: list[str]) -> int:
    classes = {}
    for p in sorted(ADDON.rglob("*.gd")):
        if "editor" in p.relative_to(ADDON).parts:
            continue
        c = parse(p)
        if c.name:
            classes[c.name] = c
    m = re.search(r'^version="([^"]+)"', (ADDON / "plugin.cfg").read_text(encoding="utf-8"), re.M)
    text = render(classes, m.group(1) if m else "?")
    if "--check" in argv:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != text:
            print(f"{OUT.relative_to(ROOT)} is out of date: run python tools/gen_api_docs.py")
            return 1
        print(f"{OUT.relative_to(ROOT)} is current")
        return 0
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"Wrote {OUT.relative_to(ROOT)}: {len(classes)} classes")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
