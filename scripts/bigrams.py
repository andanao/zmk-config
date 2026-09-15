#!/usr/bin/env python3
"""Measure how often a candidate combo's key pair occurs in normal typing.

A horizontal combo sits on two adjacent columns, so two *different* fingers can
roll it at speed -- if the letter pair is common, the combo misfires while
typing. A vertical combo sits in one column, so the same finger must travel
between the keys and can't beat the combo timeout; verticals need no check.

Measured against Adrian's own org/markdown, not English generally, because the
corpus that matters is what he types. Empirical threshold: `ds` at ~6 per 10k
has never misfired, `io` at 30 would be unusable.

Usage:
    bigrams.py            # report the pairs currently used in combos.dtsi
    bigrams.py fg tg zx   # report specific pairs
"""

from __future__ import annotations

import collections
import pathlib
import sys

CORPUS_ROOTS = [pathlib.Path.home() / "git/org", pathlib.Path.home() / "git/konfig"]
SUFFIXES = {".org", ".md"}

# Below this, no combo has ever misfired for Adrian; above it, expect trouble.
SAFE = 1.5
BORDERLINE = 6.0


def load() -> str:
    parts = []
    for root in CORPUS_ROOTS:
        if not root.exists():
            continue
        for p in root.rglob("*"):
            if p.suffix.lower() in SUFFIXES and p.is_file():
                try:
                    parts.append(p.read_text(errors="ignore").lower())
                except OSError:
                    pass
    return "\n".join(parts)


def main() -> int:
    blob = load()
    if not blob:
        print("no corpus found", file=sys.stderr)
        return 1

    counts: collections.Counter = collections.Counter()
    prev = None
    for ch in blob:
        if prev is not None:
            counts[tuple(sorted((prev, ch)))] += 1
        prev = ch
    total = sum(counts.values())

    pairs = [a.lower() for a in sys.argv[1:]]
    if not pairs:
        print("usage: bigrams.py <pair>...   e.g. bigrams.py fg tg zx", file=sys.stderr)
        return 1

    print(f"corpus: {len(blob):,} chars\n")
    print(f"{'pair':<8}{'per 10k':>9}  verdict")
    print("-" * 30)
    for pair in pairs:
        if len(pair) != 2:
            print(f"{pair:<8}{'?':>9}  not a pair")
            continue
        v = counts[tuple(sorted(pair))] / total * 10000
        verdict = "safe" if v < SAFE else ("borderline" if v < BORDERLINE else "RISKY")
        print(f"{pair:<8}{v:>9.1f}  {verdict}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
