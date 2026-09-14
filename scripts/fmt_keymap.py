#!/usr/bin/env python3
"""Re-align the ZMK_BASE_LAYER grids in this repo's keymaps.

The layer bodies are hand-aligned so each column of source lines up with a
column of keys on the keyboard. Editing a binding to a longer or shorter name
breaks that, and nothing else in the toolchain restores it: dts-format, the
devicetree formatter, deliberately leaves C-preprocessor macro invocations
alone -- and a ZMK_BASE_LAYER call is nothing but one.

Deliberately conservative. Any row whose bindings it cannot group with
confidence is passed through untouched rather than guessed at. The Admin
layer's `_BT_SEL_KEYS_` -- one token standing in for five bindings -- is the
motivating case.

Usage:
    fmt_keymap.py [--check] [files...]      default: config/*.keymap
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Column geometry of the hand-aligned grids. Both shapes put the separating
# comma at column 72 and start the right half at 76:
#   alpha  4 + 4*14 + 12 = 72
#   thumb 30 + 3*14      = 72
LEFT_ALPHA = 4
LEFT_THUMB = 30
RIGHT_START = 76
CELL = 14
ALPHA_LAST = 12

# Tokens that are a whole binding rather than an argument to the preceding one.
# Anything else is treated as an argument (`LALT` in `&mt LALT ESC`), which is
# why an unrecognised bare macro makes a row unformattable instead of mangled.
STANDALONE = {"XXX", "___"}

LAYER_RE = re.compile(r"^ZMK_BASE_LAYER\(")


def group_bindings(tokens: list[str]) -> list[str] | None:
    """Group tokens into bindings, or None if it can't be done confidently."""
    out: list[str] = []
    for tok in tokens:
        if tok.startswith("&") or tok in STANDALONE:
            out.append(tok)
        elif out and out[-1].startswith("&"):
            out[-1] += " " + tok
        else:
            return None
    return out or None


def pad(text: str, width: int) -> str:
    return text + " " * max(1, width - len(text))


def format_row(line: str) -> str | None:
    trailing_comma = line.rstrip().endswith(",")
    body = line.strip()[:-1] if trailing_comma else line.strip()
    if body.count(",") != 1:
        return None
    left_src, right_src = body.split(",")

    left = group_bindings(left_src.split())
    right = group_bindings(right_src.split())
    if left is None or right is None or len(left) != len(right):
        return None
    if len(left) == 5:
        start, widths = LEFT_ALPHA, [CELL] * 4 + [ALPHA_LAST]
    elif len(left) == 3:
        start, widths = LEFT_THUMB, [CELL] * 3
    else:
        return None

    out = " " * start
    for cell, width in zip(left, widths):
        out += pad(cell, width)
    out = out.rstrip().ljust(start + sum(widths)) + ","
    out = out.ljust(RIGHT_START)
    for cell, width in zip(right[:-1], widths[:-1]):
        out += pad(cell, width)
    out += pad(right[-1], widths[-1]) + "," if trailing_comma else right[-1]
    return out


def format_text(text: str) -> tuple[str, int]:
    out: list[str] = []
    skipped = 0
    inside = False
    for line in text.split("\n"):
        stripped = line.strip()
        if LAYER_RE.match(line):
            inside = True
        elif inside and stripped == ")":
            inside = False
        elif inside and stripped and not stripped.startswith("//"):
            new = format_row(line)
            if new is None:
                skipped += 1
            else:
                out.append(new)
                continue
        out.append(line)
    return "\n".join(out), skipped


def main() -> int:
    args = sys.argv[1:]
    check = "--check" in args
    paths = [Path(a) for a in args if not a.startswith("--")]
    if not paths:
        paths = sorted(Path("config").glob("*.keymap"))

    failed = False
    for path in paths:
        original = path.read_text()
        formatted, skipped = format_text(original)
        note = f"  ({skipped} row(s) left alone)" if skipped else ""
        if formatted == original:
            print(f"ok        {path}{note}")
        elif check:
            print(f"NEEDS FMT {path}{note}", file=sys.stderr)
            failed = True
        else:
            path.write_text(formatted)
            print(f"formatted {path}{note}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
