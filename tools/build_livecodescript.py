#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
build_livecodescript.py - combine the qr/*.lc library modules into a single
portable **script-only stack** (lib/xtQRdecoder.livecodescript) usable on
xTalk desktop, mobile, AND server via `start using`.

The qr/*.lc modules remain the single source of truth; this script regenerates
the combined library from them so the two never diverge. Run after any change
to a library module:

    python3 tools/build_livecodescript.py

What it does, per module, in dependency order:
  * strips the leading "<?lc" and trailing "?>" server tags (a script-only
    stack is pure script, never wrapped),
  * removes the repeated 4-line SPDX header (one canonical header is emitted at
    the top of the combined file instead),
  * keeps each module's descriptive banner + all handlers verbatim.

Because the xTalk server's `include` already inlines these same modules into one
shared script scope (which the 399-test suite validates), the combined stack
uses the identical namespace - no renaming, no behavioural change.
"""
import pathlib
import re
import sys

STACK_NAME = "xtQRdecoder"

# Dependency order - identical to the include list in qr/qr_demo.lc. The library
# subset only (no UI/test pages, no loose "main" block).
MODULES = [
    "qrCompat", "genericGF", "genericGFPoly", "reedSolomonDecoder",
    "bitArray", "bitMatrix", "bitSource", "luminanceSource",
    "globalHistogramBinarizer", "hybridBinarizer", "binaryBitmap",
    "errorCorrectionLevel", "mode", "dataMask", "formatInformation",
    "version", "characterSetECI", "dataBlock", "decodedBitStreamParser",
    "bitMatrixParser", "decoder", "mathUtils", "resultPoint",
    "perspectiveTransform", "gridSampler", "finderPatternFinder",
    "alignmentPatternFinder", "detector", "qrCodeReader", "qrReader",
]

# Lines (after stripping) that belong to the per-module SPDX block we inject in
# qr/*.lc - removed here so the combined file carries exactly one header.
SPDX_PREFIXES = (
    "-- SPDX-License-Identifier:",
    "-- Copyright 2026 Seth Morrow",
    "-- Part of xtQRdecoder, an xTalk",
    "-- ZXing is Apache-2.0; see the NOTICE",
)

ROOT = pathlib.Path(__file__).resolve().parent.parent
QR = ROOT / "qr"
OUT = ROOT / "lib" / f"{STACK_NAME}.livecodescript"

HEADER = f"""script "{STACK_NAME}"
-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Seth Morrow
--
-- xtQRdecoder - a pure xTalk QR Code decoder, combined into a single
-- script-only stack for use on desktop, mobile, and server.
--
-- This file is GENERATED from the qr/*.lc modules by
-- tools/build_livecodescript.py - do not edit it by hand; edit the modules and
-- rebuild. The modules are the single source of truth.
--
-- A line-for-line port of khanamiryan/php-qrcode-detector-decoder, itself a
-- hand-port of ZXing (Apache-2.0). See the repository NOTICE file for full
-- attribution.
--
-- USAGE (desktop / mobile / server) - load it once, e.g. in preOpenStack,
-- from the folder that holds your own stack file:
--   local tDir
--   put the effective filename of this stack into tDir
--   set the itemDelimiter to "/"
--   delete the last item of tDir          -- the folder of the host stack
--   start using stack (tDir & "/{STACK_NAME}.livecodescript")
--   put qrDecodeResultRobust(url ("binfile:" & tImagePath), "TRY_HARDER") into tRes
--   if tRes["error"] is empty then answer tRes["text"]
-- (There is no `folder` property of a stack; `the effective filename of this
-- stack` is the engine-proven way to locate a sibling file.)
--
-- PUBLIC API (see the README for the full reference):
--   qrDecodeFromData(imageBytes [,hints])        -> text  (empty on failure)
--   qrDecodeFromFile(path [,hints])              -> text  (empty on failure)
--   qrDecodeResult(imageBytes [,hints])          -> result array (never throws)
--   qrDecodeResultRobust(imageBytes [,hints[,maxDim]]) -> result array (best for photos)
-- =====================================================================
"""


def clean_module(name: str) -> str:
    path = QR / f"{name}.lc"
    lines = path.read_text(encoding="utf-8").split("\n")

    # drop a single leading "<?lc"
    if lines and lines[0].strip() == "<?lc":
        lines = lines[1:]
    # drop a single trailing "?>" (ignoring trailing blank lines)
    while lines and lines[-1].strip() == "":
        lines.pop()
    if lines and lines[-1].strip() == "?>":
        lines.pop()
    # drop the SPDX header lines (the canonical one is emitted once at top)
    kept = [ln for ln in lines
            if not any(ln.strip().startswith(p) for p in SPDX_PREFIXES)]
    # trim leading blank lines so the banner sits right under the separator
    while kept and kept[0].strip() == "":
        kept.pop(0)
    return "\n".join(kept).rstrip()


def render() -> str:
    parts = [HEADER]
    for name in MODULES:
        parts.append("")
        parts.append(f"-- ===================== module: {name} "
                     + "=" * max(0, 24 - len(name)))
        parts.append(clean_module(name))
    return "\n".join(parts).rstrip() + "\n"


# Structural validation of the *combined* artifact. The per-module linter
# (tools/lint_lcs.py) sees one file at a time and so cannot detect collisions
# that only exist once every module shares a single script scope -- exactly what
# happens both when xTalk server `include`s the modules AND in this combined
# stack. xTalk rejects such a stack at compile time, so we refuse to emit one.
_HANDLER_RE = re.compile(
    r"^[ \t]*(?:private[ \t]+)?(?:command|function|on|getProp|setProp)[ \t]+([A-Za-z_]\w*)",
    re.M)
_END_HANDLER_RE = re.compile(r"^[ \t]*end[ \t]+([A-Za-z_]\w*)[ \t]*$", re.M)
_FILELEVEL_DECL_RE = re.compile(r"^(local|constant)[ \t]+(.+)$", re.M)


def _dups(names):
    counts: dict[str, int] = {}
    for n in names:
        counts[n] = counts.get(n, 0) + 1
    return sorted(n for n, c in counts.items() if c > 1)


def validate_combined(text: str) -> list:
    """Return a list of structural problems in the combined stack (empty == OK):
      * the same handler name defined by two modules (xTalk compile error),
      * the same file-level local/constant declared by two modules,
      * handler open/close imbalance,
      * a script-level local/constant referenced above its declaration
        (OpenXTalk resolves those by lexical position),
      * any non-ASCII character (the suite's pure-ASCII source rule).
    """
    problems = []

    handler_names = _HANDLER_RE.findall(text)
    dup_handlers = _dups(handler_names)
    if dup_handlers:
        problems.append("duplicate handler definitions: " + ", ".join(dup_handlers))

    open_names = set(handler_names)
    handler_ends = [e for e in _END_HANDLER_RE.findall(text) if e in open_names]
    if len(handler_names) != len(handler_ends):
        problems.append(
            f"handler open/close imbalance: {len(handler_names)} openers vs "
            f"{len(handler_ends)} matching 'end <name>'")

    # file-level (column-0) declarations only; indented handler-locals are
    # correctly scoped per handler and may repeat freely.
    decl_names = []
    for kind, rest in _FILELEVEL_DECL_RE.findall(text):
        rest = rest.split("--", 1)[0]
        for piece in _split_decl(rest):   # "constant kA = 1, kB = 2" / "local a, b   -- note"
            nm = piece.split("=", 1)[0].strip() if kind == "constant" else piece.strip()
            if nm:
                decl_names.append(nm.split()[0].lower())
    dup_decls = _dups(decl_names)
    if dup_decls:
        problems.append("duplicate file-level local/constant: " + ", ".join(dup_decls))

    # OpenXTalk resolves a script-level `constant`/`local` by LEXICAL POSITION: a
    # handler that sits ABOVE the declaration it reads sees an undeclared name,
    # which silently evaluates to its own spelling (xtalk-suite engine notes 1.2,
    # 1.3, 2.1). Concatenating modules can create exactly that shape, so refuse
    # any column-0 name whose first reference precedes its declaration.
    problems += _check_lexical_order(text)

    # The suite's ASCII rule: curly quotes fail compilation anywhere, and the
    # house rule is zero non-ASCII bytes so the fatal class can never slip in.
    bad = sorted(set(c for c in text if ord(c) > 127))
    if bad:
        problems.append("non-ASCII characters in the combined stack: "
                        + " ".join("U+%04X" % ord(c) for c in bad))

    return problems


_LINE_STRIP_RE = re.compile(r'"[^"]*"')


def _check_lexical_order(text):
    lines = text.split("\n")
    decls = []  # (name_lower, lineno)
    for i, ln in enumerate(lines, 1):
        m = _FILELEVEL_DECL_RE.match(ln)
        if not m:
            continue
        kind, rest = m.groups()
        rest = rest.split("--", 1)[0]
        for piece in _split_decl(rest):
            nm = piece.split("=", 1)[0].strip() if kind == "constant" else piece.strip()
            if nm:
                decls.append((nm.split()[0].lower(), i))
    out = []
    for nm, decl_line in decls:
        pat = re.compile(r"\b" + re.escape(nm) + r"\b", re.I)
        for i, ln in enumerate(lines[:decl_line - 1], 1):
            code = _LINE_STRIP_RE.sub('""', ln.split("--", 1)[0])
            if pat.search(code):
                out.append("script-level name '%s' is referenced at line %d but declared at line %d "
                           "(OpenXTalk resolves by lexical position)" % (nm, i, decl_line))
                break
    return out


def _split_decl(rest):
    """Split a declaration list on commas OUTSIDE quotes (`constant kA = "a,b", kB = 2`)."""
    parts, cur, inq = [], "", False
    for ch in rest:
        if ch == '"':
            inq = not inq
        if ch == "," and not inq:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return parts


def main() -> int:
    missing = [m for m in MODULES if not (QR / f"{m}.lc").is_file()]
    if missing:
        print(f"ERROR: missing modules: {', '.join(missing)}", file=sys.stderr)
        return 2

    text = render()

    # the five server pages hand-copy the include list; hold them to MODULES
    for page in ("qr_tester.lc", "qr_golden.lc", "qr_synthetic.lc", "qr_demo.lc", "qr_decodeprobe.lc"):
        ppath = QR / page
        if not ppath.is_file():
            continue
        found = re.findall(r'include \(tBase & "/([A-Za-z0-9_]+)\.lc"\)', ppath.read_text(encoding="utf-8"))
        libs = [n for n in found if n in MODULES]
        if libs != MODULES:
            print(f"ERROR: qr/{page} includes the library modules in a different order/set "
                  f"than MODULES in this script; fix one of them", file=sys.stderr)
            return 1

    # refuse to emit (or pass --check on) a stack that won't compile in xTalk
    problems = validate_combined(text)
    if problems:
        print("ERROR: the combined stack has cross-module collisions the "
              "per-module linter cannot see (it would not compile in xTalk):",
              file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    # --check: verify the committed stack is in sync with the modules (CI gate)
    if "--check" in sys.argv:
        if not OUT.is_file():
            print(f"ERROR: {OUT.relative_to(ROOT)} does not exist; "
                  "run: python3 tools/build_livecodescript.py", file=sys.stderr)
            return 1
        if OUT.read_text(encoding="utf-8") != text:
            print(f"ERROR: {OUT.relative_to(ROOT)} is STALE - a library module "
                  "changed without rebuilding.\n"
                  "  Run: python3 tools/build_livecodescript.py", file=sys.stderr)
            return 1
        print(f"{OUT.relative_to(ROOT)} is up to date with the qr/ modules "
              "(structural validation OK)")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8")

    leftover_tags = text.count("<?lc") + text.count("?>")
    handler_count = len(_HANDLER_RE.findall(text))
    print(f"wrote {OUT.relative_to(ROOT)}  "
          f"({len(MODULES)} modules, {len(text.splitlines())} lines, "
          f"{handler_count} handlers)")
    print("  structural validation OK: no duplicate handlers or file-level "
          "locals, handlers balanced, server tags stripped")
    if leftover_tags:
        print("  WARNING: server tags survived the strip", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
