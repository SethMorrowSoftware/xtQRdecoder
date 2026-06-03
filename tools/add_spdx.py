#!/usr/bin/env python3
"""
add_spdx.py — one-shot: insert the SPDX/copyright header into every source file.

Idempotent: a file that already contains an "SPDX-License-Identifier" line is
left untouched. For .lc files the block is inserted right after the leading
"<?lc" line (which must remain the very first line for xTalk server); for
.py files it goes after the shebang.

Run from the repo root:  python3 tools/add_spdx.py
"""
import pathlib
import sys

YEAR = "2026"
HOLDER = "Seth Morrow"

LC_HEADER = [
    "-- SPDX-License-Identifier: Apache-2.0",
    f"-- Copyright {YEAR} {HOLDER}",
    "-- Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.",
    "-- ZXing is Apache-2.0; see the NOTICE file for full attribution.",
]
PY_HEADER = [
    "# SPDX-License-Identifier: Apache-2.0",
    f"# Copyright {YEAR} {HOLDER}",
    "# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.",
]

ROOT = pathlib.Path(__file__).resolve().parent.parent


def process(path: pathlib.Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if "SPDX-License-Identifier" in text:
        return False
    lines = text.split("\n")
    if path.suffix == ".lc":
        if not lines or lines[0].strip() != "<?lc":
            print(f"  SKIP (no leading <?lc): {path}", file=sys.stderr)
            return False
        new = [lines[0]] + LC_HEADER + lines[1:]
    elif path.suffix == ".py":
        if lines and lines[0].startswith("#!"):
            new = [lines[0]] + PY_HEADER + lines[1:]
        else:
            new = PY_HEADER + lines
    else:
        return False
    path.write_text("\n".join(new), encoding="utf-8")
    return True


def main() -> int:
    targets = sorted((ROOT / "qr").glob("*.lc")) + sorted((ROOT / "tools").glob("*.py"))
    changed = 0
    for p in targets:
        if p.name == "add_spdx.py":
            continue
        if process(p):
            changed += 1
    print(f"SPDX: added to {changed} file(s), {len(targets)} scanned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
