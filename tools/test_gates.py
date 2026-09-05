#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
test_gates.py - mutation tests for the static gates: prove that each gate
actually catches the defect class it exists for.

    python3 tools/test_gates.py

A gate that has never been seen to fail is a decoration (the xTalk Suite's
"gates must be mutation-tested" rule). For every case below a pristine
copy of the repository's qr/, lib/ and tools/ is made in a temporary
directory, ONE defect is seeded, the gate is run on the copy and it must
exit non-zero with the expected message. A positive control runs the
unmutated copy through every gate first, so a broken harness cannot pass
by accident. Exit status is non-zero if any gate fails to fail.

Gates covered: tools/build_livecodescript.py (duplicate handler, handler
imbalance, constant used above its declaration, page include order,
non-ASCII source, stale generated stack), tools/check_engine_rules.py (the
vendored xTalk Suite checker: dangling else, zero-argument statement call,
throw inside catch, curly quote) and tools/lint_lcs.py (bare return,
undeclared variable, nested local, delimiter changed inside its own loop,
missing SPDX header).
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def fresh_copy():
    tmp = tempfile.mkdtemp(prefix="xtqr-gates-")
    for sub in ("qr", "lib", "tools"):
        shutil.copytree(os.path.join(ROOT, sub), os.path.join(tmp, sub),
                        ignore=shutil.ignore_patterns("__pycache__", "fixtures"))
    return tmp


def run(tmp, tool, *args):
    p = subprocess.run([sys.executable, os.path.join(tmp, "tools", tool)] + list(args),
                       cwd=tmp, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def edit(tmp, rel, old, new, count=1):
    path = os.path.join(tmp, rel)
    text = open(path, encoding="utf-8").read()
    if old not in text:
        raise SystemExit("fixture out of date: %r not found in %s" % (old, rel))
    open(path, "w", encoding="utf-8").write(text.replace(old, new, count))


def append(tmp, rel, extra):
    path = os.path.join(tmp, rel)
    text = open(path, encoding="utf-8").read()
    if text.rstrip().endswith("?>"):
        text = text.rstrip()[:-2] + extra + "?>\n"
    else:
        text += extra
    open(path, "w", encoding="utf-8").write(text)


# (name, gate + args, mutation(tmp), expected fragment of the gate's output)
BUILD = ("build_livecodescript.py", "--check")


def m_dup_handler(tmp):
    append(tmp, "qr/mathUtils.lc", "\nfunction bitMatrix_getWidth pObj\n   return pObj[\"width\"]\nend bitMatrix_getWidth\n")


def m_imbalance(tmp):
    edit(tmp, "qr/mathUtils.lc", "end mu_round\n", "\n")


def m_constant_below_use(tmp):
    edit(tmp, "qr/qrReader.lc", 'constant kQrLibVersion = "0.2.0"\n', "\n")
    append(tmp, "qr/qrReader.lc", '\nconstant kQrLibVersion = "0.2.0"\n')


def m_include_order(tmp):
    edit(tmp, "qr/qr_golden.lc",
         '   include (tBase & "/genericGF.lc")\n   include (tBase & "/genericGFPoly.lc")\n',
         '   include (tBase & "/genericGFPoly.lc")\n   include (tBase & "/genericGF.lc")\n')


def m_non_ascii(tmp):
    edit(tmp, "qr/mathUtils.lc", "function mu_round pRoundArg\n", "function mu_round pRoundArg\n   -- café\n")


def m_stale_lib(tmp):
    edit(tmp, "qr/mathUtils.lc", "function mu_round pRoundArg\n", "function mu_round pRoundArg\n   -- a comment the lib does not have\n")


def m_dangling_else(tmp):
    append(tmp, "qr/mathUtils.lc",
           "\nfunction mu_gateProbe pA\n   local tB\n   if pA > 1 then put 1 into tB\n   else\n      put 2 into tB\n   end if\n   return tB\nend mu_gateProbe\n")


def m_zero_arg_call(tmp):
    append(tmp, "qr/mathUtils.lc", "\ncommand mu_gateProbe\n   gf_ensure()\nend mu_gateProbe\n")


def m_throw_in_catch(tmp):
    append(tmp, "qr/mathUtils.lc",
           "\ncommand mu_gateProbe\n   local e\n   try\n      gf_ensure\n   catch e\n      throw \"again: \" & e\n   end try\nend mu_gateProbe\n")


def m_curly_quote(tmp):
    append(tmp, "qr/mathUtils.lc", "\ncommand mu_gateProbe\n   put “hello” into msg\nend mu_gateProbe\n")


def m_bare_return(tmp):
    append(tmp, "qr/mathUtils.lc", "\ncommand mu_gateProbe pA\n   if pA then return\n   put 1 into msg\nend mu_gateProbe\n")


def m_undeclared(tmp):
    append(tmp, "qr/mathUtils.lc", "\ncommand mu_gateProbe pA\n   put pA into tNotDeclared\nend mu_gateProbe\n")


def m_nested_local(tmp):
    append(tmp, "qr/mathUtils.lc",
           "\ncommand mu_gateProbe pA\n   if pA then\n      local tInner\n      put 1 into tInner\n   end if\nend mu_gateProbe\n")


def m_delimiter_in_loop(tmp):
    append(tmp, "qr/mathUtils.lc",
           "\ncommand mu_gateProbe pA\n   local x\n   repeat for each item x in pA\n      set the itemDelimiter to \"/\"\n   end repeat\nend mu_gateProbe\n")


def m_no_spdx(tmp):
    edit(tmp, "qr/mathUtils.lc", "-- SPDX-License-Identifier: Apache-2.0\n", "")


CASES = [
    ("build: duplicate handler across modules", BUILD, m_dup_handler, "duplicate handler"),
    ("build: handler open/close imbalance", BUILD, m_imbalance, "imbalance"),
    ("build: constant referenced above its declaration", BUILD, m_constant_below_use, "declared at line"),
    ("build: page include order differs from MODULES", BUILD, m_include_order, "different order"),
    ("build: non-ASCII character in a module", BUILD, m_non_ascii, "non-ASCII"),
    ("build --check: generated stack is stale", BUILD, m_stale_lib, "STALE"),
    ("checker: dangling else", ("check_engine_rules.py", "qr/mathUtils.lc"), m_dangling_else, "else"),
    ("checker: zero-argument statement call foo()", ("check_engine_rules.py", "qr/mathUtils.lc"), m_zero_arg_call, "()"),
    ("checker: throw inside catch", ("check_engine_rules.py", "qr/mathUtils.lc"), m_throw_in_catch, "throw"),
    ("checker: curly quote", ("check_engine_rules.py", "qr/mathUtils.lc"), m_curly_quote, "U+201C"),
    ("lint: bare return", ("lint_lcs.py", "qr/mathUtils.lc"), m_bare_return, "bare 'return'"),
    ("lint: write to an undeclared variable", ("lint_lcs.py", "qr/mathUtils.lc"), m_undeclared, "undeclared"),
    ("lint: local declared inside a block", ("lint_lcs.py", "qr/mathUtils.lc"), m_nested_local, "inside a block"),
    ("lint: itemDelimiter changed inside repeat for each item", ("lint_lcs.py", "qr/mathUtils.lc"), m_delimiter_in_loop, "itemDelimiter changed"),
    ("lint: missing SPDX header", ("lint_lcs.py", "qr/mathUtils.lc"), m_no_spdx, "SPDX"),
]


def main():
    bad = []
    # positive control: the pristine copy passes every gate
    tmp = fresh_copy()
    try:
        for tool, args in (("build_livecodescript.py", ["--check"]),
                           ("check_engine_rules.py", ["qr/mathUtils.lc", "qr/qrReader.lc", "qr/qr_golden.lc"]),
                           ("lint_lcs.py", ["qr/mathUtils.lc"])):
            rc, out = run(tmp, tool, *args)
            if rc != 0:
                bad.append("positive control: %s exited %d on the pristine copy:\n%s" % (tool, rc, out))
    finally:
        shutil.rmtree(tmp)
    if bad:
        print("test_gates: the pristine tree does not pass the gates; fix that first")
        for b in bad:
            print("  " + b)
        return 1
    for name, gate, mutate, fragment in CASES:
        tmp = fresh_copy()
        try:
            mutate(tmp)
            rc, out = run(tmp, gate[0], *gate[1:])
        finally:
            shutil.rmtree(tmp)
        if rc == 0:
            bad.append("%s: the gate PASSED the seeded defect" % name)
            print("MISSED  " + name)
        elif fragment not in out:
            bad.append("%s: the gate failed but without %r in its output:\n%s" % (name, fragment, out[-400:]))
            print("VAGUE   " + name)
        else:
            print("caught  " + name)
    print()
    if bad:
        print("test_gates: %d of %d seeded defects were NOT caught as expected" % (len(bad), len(CASES)))
        for b in bad:
            print("  - " + b)
        return 1
    print("test_gates: all %d seeded defects caught by their gate (plus the positive control)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
