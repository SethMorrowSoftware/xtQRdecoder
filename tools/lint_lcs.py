#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
lint_lcs.py — static checks for the xTalk modules in qr/.

These catch the classes of error a real xTalk engine (9.6.x-era) rejects but that
reading by eye tends to miss:

  1. BLOCK MATCHING   — every `end if/repeat/switch/try` closes the right opener,
                        every handler `end <name>` matches, nothing unclosed.
                        (Caught an `if/else` wrongly closed with `end try`.)
  2. RESERVED WORDS   — no xTalk builtin/property/keyword used as a local or
                        parameter name. (Caught `result`, `line`, `offset`,
                        `average`, `ln`, `top`, `left`, `right`, `sum`.)
  3. BARE RETURN      — no `return` without a value. This engine errors with
                        "missing factor"; the early-exit idiom is `exit <name>`.
  4. UNDECLARED VARS  — every variable written via `put .. into X` / `add .. to X`
                        is declared (file-level local, handler local, param, or
                        loop/catch var) so files parse under explicitVariables.

Usage:  python3 tools/lint_lcs.py [path ...]   (defaults to ./qr)
  Each path may be a directory (linted as <dir>/*.lc) or an explicit file --
  e.g. `python3 tools/lint_lcs.py qr lib/xtQRdecoder.livecodescript` lints both
  the modules and the generated combined library.
Exit code is non-zero if any check fails, so it can gate CI.

NOTE: this is a heuristic linter, not an xTalk parser. It is intentionally
conservative (prefers false positives over misses). The real engine remains
the final authority — see qr/qr_tester.lc and qr/qr_imageprobe.lc.
"""
import re, sys, glob, os

# Confirmed against the published xTalk grammar
# and a real xTalk engine (a 9.6.11-class build). Constants + keywords + common
# properties/functions/commands that break (or get misparsed) when used as a
# plain variable or parameter name. xTalk matching is case-INSENSITIVE, so
# the linter lowercases identifiers before testing membership here.
RESERVED = set("""
arrow backslash busy colon comma crlf linefeed cr lf cross down eight empty eof false five
formfeed four hand help ibeam left nine null one pi plus quote return right space tab ten three
true two up watch zero
abbreviated addmax addover addpin admin any array as ascending at back binfile black blend bold box
browse brush bucket button by byte bytes card cascade character characters clear codepoint codepoints
codeunit codeunits colorpalette combobox control curve dateitems datetime default descending dropper
each effective eighth element english eraser field fifth file finally first fourth from front graphic
gray image in int1 int2 int4 integer internet intersect inverse it italic item items last line lines
link long magnifier marked maximize me menu menuitem middle milliseconds minimize modem ninth noop
normal numeric of onto opaque option oval paint paragraph paragraphs pencil plain player point pointer
polygon popup previous printer pulldown real4 real8 recent rectangle regular relative resfile reverse
roundrect scrollbar second seconds segment segments select selection sentence sentences set seventh
shadow short sixth standard stderr stdin stdout strikeout string subover subpin surround system
tabbed target text the then third ticks title to token top transparent uint1 uint2 uint4 underline
until url using while white whole with without word words for
abs acos annuity atan average ceiling char compound cos date exp exp1 exp2 exp10 floor format
height hostname keys length ln ln1 log2 max md5digest min number offset param paramcount params
random result round sin sqrt sum tan tanh time trunc value width
add answer ask beep breakpoint call cancel choose click close create delete dispatch divide drag
edit exit filter find flip get go grab hide import include kill launch load lock
mark move multiply open pass place play pop post prepare print put quit read receive
record reject release remove rename repeat replace request reset resize revert rotate save
scroll seek send show sort start stop subtract switch throw toggle try unload unlock unmark wait write
location loc owner id name kind mask scale position source pixel bit angle zoom margin margins
mod div is not and or contains
center centers centered dim
ac bg cd btn fld grc img snd eps lcw vc grp msg
""".split())
# NOTE: the last two rows are ENGINE-CONFIRMED (or strongly suspected) reserved
# words that are ABSENT from the published xTalk grammar file. 'centers' and
# 'ac' both parsed-failed on a real xTalk engine (a 9.6.11-class build) despite not being in the
# grammar; 'ac' (audioClip) and the other two-letter object abbreviations
# (bg=background, cd=card, btn=button, fld=field, grc=graphic, img=image,
# snd=audioclip/player, ...) are xTalk object-type shorthands.
# (Also note: 'pi' is the constant Pi, and names are case-INSENSITIVE, so
# 'pI'/'pi'/'PI' all collide -- the membership test below lowercases first.)

BUILTINS = set("""the empty true false cr lf tab quote comma space zero return null it result me target
paramcount params param number length offset random round trunc abs min max sum average item char word line byte token
sin cos tan atan exp ln sqrt log2 put into after before set get add subtract multiply divide throw
is not and or bitand bitor bitxor bitnot mod div of by there a an file folder image stack
toupper tolower numtobyte bytetonum base64decode base64encode binarydecode binaryencode textencode textdecode
milliseconds formattedwidth formattedheight imagedata lockloc invisible create delete""".lower().split())


def logical_lines(path):
    """Yield (lineno, text) joining xTalk backslash continuations."""
    buf, start = "", 0
    for i, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.rstrip("\n")
        if buf == "":
            start = i
        if line.rstrip().endswith("\\"):
            buf += re.sub(r"\\\s*$", "", line) + " "
        else:
            yield (start, buf + line)
            buf = ""
    if buf:
        yield (start, buf)


def strip_comment(s):
    return re.sub(r"--.*$", "", s)


def opener_kind(s):
    s = strip_comment(s).strip()
    if not s:
        return None
    m = re.match(r"^(command|function)\s+([A-Za-z_][A-Za-z0-9_]*)", s)
    if m:
        return ("handler", m.group(2))
    if re.match(r"^repeat\b", s):
        return ("repeat", None)
    if re.match(r"^switch\b", s):
        return ("switch", None)
    if re.match(r"^try\b", s):
        return ("try", None)
    if re.match(r"^if\b", s):
        return ("if", None) if re.search(r"\bthen\s*$", s) else ("inline-if", None)
    return None


def end_kind(s):
    s = strip_comment(s).strip()
    m = re.match(r"^end\s+(if|repeat|switch|try)\b", s)
    if m:
        return ("ctl", m.group(1))
    m = re.match(r"^end\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", s)
    if m:
        return ("handler", m.group(1))
    return None


def check_blocks(path, fail):
    stack = []
    for ln, s in logical_lines(path):
        ok = opener_kind(s)
        if ok and ok[0] != "inline-if":
            stack.append((ok, ln))
        ek = end_kind(s)
        if ek:
            if not stack:
                fail(f"{path}:{ln}: 'end' with empty stack")
                continue
            top, oln = stack.pop()
            if ek[0] == "handler" and top[0] == "handler":
                if ek[1] != top[1]:
                    fail(f"{path}:{ln}: end {ek[1]} != handler {top[1]} (opened {oln})")
            elif ek[0] == "ctl" and top[0] in ("if", "repeat", "switch", "try"):
                if ek[1] != top[0]:
                    fail(f"{path}:{ln}: 'end {ek[1]}' closes '{top[0]}' (opened {oln})")
            else:
                fail(f"{path}:{ln}: 'end {ek[1] or ek[0]}' != opener '{top[0]}' (opened {oln})")
    if stack:
        fail(f"{path}: unclosed blocks {[(k[0], k[1], l) for k, l in stack]}")


def check_reserved_and_bare_return(path, fail):
    for ln, s in logical_lines(path):
        cs = strip_comment(s)
        m = re.match(r"^\s*local\s+(.+)$", cs)
        if m:
            for v in re.split(r"\s*,\s*", m.group(1).strip()):
                if v.strip().lower() in RESERVED:
                    fail(f"{path}:{ln}: local '{v.strip()}' is a reserved word")
        m = re.match(r"^\s*(command|function)\s+[A-Za-z_][A-Za-z0-9_]*\s+(.+)$", cs)
        if m:
            for v in re.split(r"\s*,\s*", m.group(2).strip()):
                vv = v.strip().lstrip("@")
                if vv.lower() in RESERVED:
                    fail(f"{path}:{ln}: param '{vv}' is a reserved word")
        if re.search(r"(^|\s)return\s*$", cs) and not re.search(r"return\s+\S", cs):
            fail(f"{path}:{ln}: bare 'return' (use 'exit <handler>' for valueless early exit)")


def check_case_collisions(path, fail):
    """xTalk variable names are case-INSENSITIVE; declaring both 'R' (param)
    and 'r' (local) in one handler is a redeclaration error."""
    lines = open(path, encoding="utf-8").read().split("\n")
    i = 0
    while i < len(lines):
        hm = re.match(r"^\s*(command|function)\s+([A-Za-z_]\w*)\s*(.*)$", strip_comment(lines[i]))
        if not hm:
            i += 1
            continue
        hname = hm.group(2)
        seen = {}
        for p in re.split(r"\s*,\s*", hm.group(3).strip()):
            p = p.strip().lstrip("@")
            if p:
                seen.setdefault(p.lower(), p)
        j = i + 1
        while j < len(lines) and not re.match(rf"^\s*end\s+{re.escape(hname)}\s*$", lines[j]):
            lm = re.match(r"^\s*local\s+(.+)$", strip_comment(lines[j]))
            if lm:
                for v in re.split(r"\s*,\s*", lm.group(1).strip()):
                    v = v.strip()
                    if v:
                        lo = v.lower()
                        if lo in seen and seen[lo] != v:
                            fail(f"{path}:{j+1}: {hname}: '{v}' case-collides with '{seen[lo]}' (xTalk names are case-insensitive)")
                        seen.setdefault(lo, v)
            j += 1
        i = j


def check_loopvars_declared(path, fail):
    """Under explicitVariables, a `repeat with X` / `repeat for each ... X` loop
    variable must be declared as a local or parameter. Flag any that aren't."""
    lines = open(path, encoding="utf-8").read().split("\n")
    i = 0
    while i < len(lines):
        hm = re.match(r"^\s*(command|function)\s+([A-Za-z_]\w*)\s*(.*)$", strip_comment(lines[i]))
        if not hm:
            i += 1
            continue
        hname = hm.group(2)
        declared = set()
        for p in re.split(r"\s*,\s*", hm.group(3).strip()):
            p = p.strip().lstrip("@")
            if p:
                declared.add(p.lower())
        loopvars = []  # (lineno, name)
        j = i + 1
        while j < len(lines) and not re.match(rf"^\s*end\s+{re.escape(hname)}\s*$", lines[j]):
            bs = strip_comment(lines[j])
            lm = re.match(r"^\s*local\s+(.+)$", bs)
            if lm:
                for v in re.split(r"\s*,\s*", lm.group(1).strip()):
                    declared.add(v.strip().lower())
            for rm in re.finditer(r"\brepeat\s+with\s+([A-Za-z_]\w*)\s*=", bs):
                loopvars.append((j + 1, rm.group(1)))
            for rm in re.finditer(r"\brepeat\s+for\s+each\s+\w+\s+([A-Za-z_]\w*)\b", bs):
                loopvars.append((j + 1, rm.group(1)))
            j += 1
        for ln, v in loopvars:
            if v.lower() not in declared:
                fail(f"{path}:{ln}: {hname}: loop var '{v}' not declared local (fails under explicitVariables)")
        i = j


def check_delimiter_footgun(path, fail):
    """`repeat for each item X` caches the itemDelimiter at loop entry; changing
    it inside the body is unreliable in xTalk. Same for line/lineDelimiter."""
    lines = open(path, encoding="utf-8").read().split("\n")
    stack = []  # (kind, lineno) for 'item' or 'line' for-each loops
    for i, raw in enumerate(lines, 1):
        s = strip_comment(raw)
        m = re.search(r"\brepeat\s+for\s+each\s+(item|line)\b", s)
        if m:
            stack.append((m.group(1), i))
        elif re.match(r"^\s*repeat\b", s):
            stack.append(("other", i))
        if re.match(r"^\s*end\s+repeat\b", s) and stack:
            stack.pop()
        for kind, ln in stack:
            if kind == "item" and re.search(r"set\s+the\s+itemDelimiter", s):
                fail(f"{path}:{i}: itemDelimiter changed inside 'repeat for each item' (opened {ln})")
            if kind == "line" and re.search(r"set\s+the\s+lineDelimiter", s):
                fail(f"{path}:{i}: lineDelimiter changed inside 'repeat for each line' (opened {ln})")


def check_undeclared(path, fail):
    lines = open(path, encoding="utf-8").read().split("\n")
    filelocals, inh = set(), False
    for raw in lines:
        s = strip_comment(raw)
        if re.match(r"^\s*(command|function)\s", s):
            inh = True
        if inh and re.match(r"^\s*end\s+[A-Za-z_]", s) and not re.match(r"^\s*end\s+(if|repeat|switch|try)\b", s):
            inh = False
            continue
        if not inh:
            lm = re.match(r"^\s*local\s+(.+)$", s)
            if lm:
                for v in re.split(r"\s*,\s*", lm.group(1).strip()):
                    filelocals.add(v.strip().lower())
    i = 0
    while i < len(lines):
        hm = re.match(r"^\s*(command|function)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$", strip_comment(lines[i]))
        if not hm:
            i += 1
            continue
        hname = hm.group(2)
        declared = set(filelocals)
        for p in re.split(r"\s*,\s*", hm.group(3).strip()):
            p = p.strip().lstrip("@")
            if p:
                declared.add(p.lower())
        body, j = [], i + 1
        while j < len(lines) and not re.match(rf"^\s*end\s+{re.escape(hname)}\s*$", lines[j]):
            body.append(lines[j])
            j += 1
        for b in body:
            bs = strip_comment(b)
            lm = re.match(r"^\s*local\s+(.+)$", bs)
            if lm:
                for v in re.split(r"\s*,\s*", lm.group(1).strip()):
                    declared.add(v.strip().lower())
            for rm in re.finditer(r"\brepeat\s+with\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", bs):
                declared.add(rm.group(1).lower())
            for rm in re.finditer(r"\brepeat\s+for\s+each\s+\w+\s+([A-Za-z_][A-Za-z0-9_]*)\b", bs):
                declared.add(rm.group(1).lower())
            for cm in re.finditer(r"\bcatch\s+([A-Za-z_][A-Za-z0-9_]*)", bs):
                declared.add(cm.group(1).lower())
        targets = set()
        for b in body:
            bs = strip_comment(b)
            for m in re.finditer(r"\binto\s+([A-Za-z_][A-Za-z0-9_]*)", bs):
                targets.add(m.group(1).lower())
            for m in re.finditer(r"\b(?:add|subtract|multiply|divide)\s+.+?\s+(?:to|from|by)\s+([A-Za-z_][A-Za-z0-9_]*)", bs):
                targets.add(m.group(1).lower())
        for v in sorted(targets):
            if v not in declared and v not in BUILTINS:
                fail(f"{path}: {hname}: writes undeclared var '{v}'")
        i = j


def check_spdx(path, fail):
    """Every source file should carry the SPDX license header (run add_spdx.py)."""
    with open(path, encoding="utf-8") as fh:
        head = fh.read(600)
    if "SPDX-License-Identifier" not in head:
        fail(f"{path}: missing SPDX-License-Identifier header (run tools/add_spdx.py)")


def collect_files(args):
    """Expand CLI args into a sorted file list. Each arg may be a directory
    (linted as <dir>/*.lc) or an explicit file path of any extension -- so the
    generated lib/xtQRdecoder.livecodescript can be linted with the same checks
    the qr/*.lc modules get. No args defaults to the qr/ directory."""
    default = os.path.join(os.path.dirname(__file__), "..", "qr")
    files = []
    for t in (args or [default]):
        if os.path.isdir(t):
            files.extend(glob.glob(os.path.join(t, "*.lc")))
        elif os.path.isfile(t):
            files.append(t)
        else:
            print(f"warning: no such file or directory: {t}", file=sys.stderr)
    return sorted(set(files))


def main():
    files = collect_files(sys.argv[1:])
    if not files:
        print("no files to lint", file=sys.stderr)
        return 2
    failures = []
    fail = failures.append
    for f in files:
        check_blocks(f, fail)
        check_reserved_and_bare_return(f, fail)
        check_case_collisions(f, fail)
        check_loopvars_declared(f, fail)
        check_delimiter_footgun(f, fail)
        check_undeclared(f, fail)
        check_spdx(f, fail)
    if failures:
        print("xTalk lint: FAIL")
        for x in failures:
            print("  " + x)
        return 1
    print(f"xTalk lint: clean ({len(files)} files: blocks, reserved words, bare-return, case-collisions, loop vars, undeclared vars, SPDX)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
