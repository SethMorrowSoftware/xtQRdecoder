#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
sync_demo_embeds.py - the showcase demo carries the library and the suite's
two UI blocks; this tool keeps all three copies exact.

    python3 tools/sync_demo_embeds.py            # rewrite the carried regions
    python3 tools/sync_demo_embeds.py --check    # CI gate: refuse a stale copy

lib/examples/xtQRdecoder-demo.livecodescript is ONE paste-and-run file, the
way the xTalk Suite's demos are (its tools/sync-demo-embeds.py is the model
for this tool). Three regions of it are carried from masters and never
edited by hand:

  * between `>>> BEGIN EMBEDDED LIBRARIES` and `<<< END EMBEDDED LIBRARIES`:
    lib/xtQRdecoder.livecodescript, the combined library, with its leading
    `script "..."` line dropped (a second script-name line mid-file would put
    everything after it outside the demo's own declaration scope). It goes
    ABOVE the demo's own code because OpenXTalk resolves script-level
    constants and locals by lexical position.
  * between the `SUITE UI KIT v2 BEGIN/END` marker lines: the suite's UI kit
    block, from tools/ui-kit.livecodescript (vendored byte-identical from
    SethMorrowSoftware/xtalk-suite; the suite's check-ui-kit-drift.py would
    accept this copy).
  * between the `DEMO SELF-CHECK v1 BEGIN/END` marker lines: the suite's boot
    self-check block, from tools/demo-selfcheck.livecodescript (vendored the
    same way).

It also DERIVES the demo's control list: `constant kQdScControls = "..."`
names every control the demo's own code builds or references (the first
string argument of each kit builder and of the demo's wrappers, plus every
literal `field "x"` / `button "x"` / `graphic "x"` reference, plus the chrome
the kit creates for the handlers the demo actually calls), so the boot
self-check can assert they all exist. A hand-kept list is right on the day it
is written; this one is regenerated on every sync and checked in CI.

Before writing, the assembled text goes through the combined-stack validator
(tools/build_livecodescript.py): duplicate handlers or script-level names
between the demo and what it carries, a handler imbalance, a script-level
name referenced above its declaration, or any non-ASCII byte refuse the
write and name the problem. Collisions are refused, never merged.

Exit status: 0 clean, 1 stale or refused, 2 a master is missing.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from build_livecodescript import validate_combined  # noqa: E402

DEMO = os.path.join(ROOT, "lib", "examples", "xtQRdecoder-demo.livecodescript")
LIB = os.path.join(ROOT, "lib", "xtQRdecoder.livecodescript")
KIT = os.path.join(HERE, "ui-kit.livecodescript")
SELFCHECK = os.path.join(HERE, "demo-selfcheck.livecodescript")

EMBED_BEGIN = "-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync_demo_embeds.py) >>>"
EMBED_END = "-- <<< END EMBEDDED LIBRARIES <<<"
KIT_BEGIN = ("-- ==== SUITE UI KIT v2 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; "
             "gate: tools/check-ui-kit-drift.py) ====")
KIT_END = "-- ==== SUITE UI KIT v2 END ===="
SC_BEGIN = ("-- ==== DEMO SELF-CHECK v1 BEGIN (verbatim copy; master: tools/demo-selfcheck.livecodescript; "
            "gate: tools/check-demo-selfcheck-drift.py) ====")
SC_END = "-- ==== DEMO SELF-CHECK v1 END ===="

# The wording inside the sentinels deliberately avoids the phrase the suite's
# drift gates treat as "skip this file" (see the suite's sync-demo-embeds.py).
EMBED_BANNER = """-- Pasted from lib/xtQRdecoder.livecodescript so this demo runs with NO
-- `start using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync_demo_embeds.py` instead. The qr/*.lc modules stay
-- the single source of truth, and lib/xtQRdecoder.livecodescript is the
-- right dependency for a real project.
--
-- The library comes FIRST because OpenXTalk resolves script-level
-- constants and locals by lexical position.

-- ---- lib/xtQRdecoder.livecodescript ----
"""

# kit handlers whose first argument names the control they create
KIT_BUILDERS = ("uiLabel", "uiWrap", "uiCap", "uiSection", "uiInput", "uiArea", "uiTable",
                "uiButton", "uiCheckbox", "uiGfx", "uiPanel", "uiPill")
# the demo's own wrappers with the same contract
DEMO_BUILDERS = ("qdLabel", "qdButton", "qdCheckbox")
CONTROL_WORDS = ("field", "button", "graphic", "image")


def read(path):
    if not os.path.isfile(path):
        print("missing master: %s" % os.path.relpath(path, ROOT), file=sys.stderr)
        sys.exit(2)
    return open(path, encoding="utf-8").read()


def between(text, begin, end, what):
    """The block from the BEGIN line to the END line, both inclusive."""
    i = text.find(begin)
    j = text.find(end)
    if i < 0 or j < 0 or j < i:
        raise SystemExit("%s: could not find the %s marker lines" % (what, begin.split()[2]))
    j = text.find("\n", j)
    return text[i:j + 1]


def strip_script_line(text):
    lines = text.split("\n")
    if lines and lines[0].startswith('script "'):
        lines = lines[1:]
    return "\n".join(lines).lstrip("\n")


def cut_comments(text):
    """Remove `--` comments with a string-state-aware scan (a `--` inside a
    literal is not a comment); string literals are KEPT, because the
    control-name derivation reads them."""
    out = []
    for line in text.split("\n"):
        inq = False
        cut = len(line)
        k = 0
        while k < len(line):
            ch = line[k]
            if ch == '"':
                inq = not inq
            elif not inq and line.startswith("--", k):
                cut = k
                break
            k += 1
        out.append(line[:cut])
    return "\n".join(out)


def demo_own_code(text):
    """The demo's own code: everything outside the three carried regions."""
    for begin, end in ((EMBED_BEGIN, EMBED_END), (KIT_BEGIN, KIT_END), (SC_BEGIN, SC_END)):
        i = text.find(begin)
        j = text.find(end)
        if i >= 0 and j > i:
            text = text[:i] + text[j + len(end):]
    return text


def derive_controls(text):
    code = cut_comments(demo_own_code(text))
    names = set()
    for builder in KIT_BUILDERS + DEMO_BUILDERS:
        for m in re.finditer(r'\b%s\s+"([^"]+)"' % builder, code):
            names.add(m.group(1))
            if builder == "uiSection":
                names.add(m.group(1) + "Line")
            if builder == "uiPill":
                names.add(m.group(1) + "Bg")
    for word in CONTROL_WORDS:
        for m in re.finditer(r'\b%s\s+"([^"]+)"' % word, code):
            names.add(m.group(1))
    if re.search(r"\buiChrome\b", code):
        names.update(("uiBand", "uiTitle", "uiStatus"))
    if re.search(r"\buiFooter\b", code):
        names.add("uiFooter")
    return sorted(names)


def splice(text, begin, end, block, inclusive):
    i = text.find(begin)
    j = text.find(end)
    if i < 0 or j < 0 or j < i:
        raise SystemExit("demo: could not find the %s region" % begin.split()[2])
    if inclusive:
        j_end = text.find("\n", j) + 1
        return text[:i] + block + text[j_end:]
    i_end = text.find("\n", i) + 1
    return text[:i_end] + block + text[j:]


def assemble(demo_text):
    lib = strip_script_line(read(LIB))
    kit = between(read(KIT), KIT_BEGIN, KIT_END, "ui-kit master")
    sc = between(read(SELFCHECK), SC_BEGIN, SC_END, "self-check master")
    text = splice(demo_text, EMBED_BEGIN, EMBED_END, EMBED_BANNER + lib.rstrip("\n") + "\n", False)
    text = splice(text, KIT_BEGIN, KIT_END, kit, True)
    text = splice(text, SC_BEGIN, SC_END, sc, True)
    controls = derive_controls(text)
    text, n = re.subn(r'^constant kQdScControls = "[^"\n]*"$',
                      'constant kQdScControls = "%s"' % ",".join(controls), text, count=1, flags=re.M)
    if n != 1:
        raise SystemExit("demo: the `constant kQdScControls = ...` line is missing")
    return text, controls


def main(argv):
    check = "--check" in argv
    demo_text = read(DEMO)
    text, controls = assemble(demo_text)
    problems = validate_combined(text)
    if problems:
        print("REFUSED: the assembled demo would not compile as one script:", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        return 1
    if check:
        if text != demo_text:
            print("lib/examples/xtQRdecoder-demo.livecodescript is STALE: a carried region or the "
                  "control list differs from its master.\n  Run: python3 tools/sync_demo_embeds.py",
                  file=sys.stderr)
            return 1
        print("lib/examples/xtQRdecoder-demo.livecodescript carries the library, the UI kit and the "
              "self-check block exactly; %d controls in the derived list" % len(controls))
        return 0
    if text == demo_text:
        print("demo already in sync (%d controls in the derived list)" % len(controls))
        return 0
    open(DEMO, "w", encoding="utf-8").write(text)
    print("wrote lib/examples/xtQRdecoder-demo.livecodescript (%d lines; %d controls in the derived list)"
          % (len(text.splitlines()), len(controls)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
