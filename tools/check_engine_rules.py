#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""check_engine_rules.py - run the xTalk Suite's unified LiveCodeScript static
checker over every xtQRdecoder source.

WHY A SECOND LINTER. tools/lint_lcs.py is this repo's own heuristic checker
(block matching, reserved words, bare return, undeclared writes, the delimiter
footgun, SPDX). The xTalk Suite (SethMorrowSoftware/xtalk-suite) carries a
second, independently grown checker - tools/check_livecodescript.py, vendored
here VERBATIM from the suite's byte-identical copies - whose 22 rules each
encode a defect that was paid for on a real OpenXTalk engine: pure-ASCII
source, throw-inside-catch, the zero-argument statement call, the
prefixed-token-shadow trap, the dangling else, non-literal constants,
constants used above their declaration, a command called as a function, and
the rest (read its docstring). Neither checker is a compiler; together they
front-run the engine for two families of mistakes. Both gate CI.

WHAT THIS WRAPPER DOES. The suite's checker only looks at *.livecodescript and
*.lcb. Our library modules are xTalk SERVER files (qr/*.lc) wrapped in
"<?lc ... ?>", so each one is copied into a temporary directory with the
wrapper lines removed and a .livecodescript name, checked, and the reported
line numbers are shifted back by one (the stripped "<?lc" line) so they point
at the real file. lib/*.livecodescript and lib/examples/** are checked as they
are. Exit code 0 = clean, 1 = problems (CI gate).

Usage:  python3 tools/check_engine_rules.py [path ...]
        (defaults to qr/, lib/xtQRdecoder.livecodescript and lib/examples/)
"""
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def _load_checker():
    path = os.path.join(HERE, "check_livecodescript.py")
    spec = importlib.util.spec_from_file_location("check_livecodescript", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def strip_server_wrapper(text):
    """Remove a leading '<?lc' line and a trailing '?>' line. Returns
    (text, leading_lines_removed)."""
    lines = text.split("\n")
    removed = 0
    if lines and lines[0].strip() == "<?lc":
        lines = lines[1:]
        removed = 1
    while lines and lines[-1].strip() == "":
        lines.pop()
    if lines and lines[-1].strip() == "?>":
        lines.pop()
    return "\n".join(lines) + "\n", removed


def default_targets():
    out = []
    qr = os.path.join(ROOT, "qr")
    for name in sorted(os.listdir(qr)):
        if name.endswith(".lc"):
            out.append(os.path.join(qr, name))
    lib = os.path.join(ROOT, "lib")
    for dirpath, _dirs, files in os.walk(lib):
        for name in sorted(files):
            if name.endswith(".livecodescript"):
                out.append(os.path.join(dirpath, name))
    return out


def main(argv):
    chk = _load_checker()
    targets = []
    for a in (argv[1:] or default_targets()):
        if os.path.isdir(a):
            for dirpath, _dirs, files in os.walk(a):
                for name in sorted(files):
                    if name.endswith(".lc") or name.endswith(".livecodescript"):
                        targets.append(os.path.join(dirpath, name))
        else:
            targets.append(a)
    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        for path in targets:
            if path.endswith(".lc"):
                with open(path, "rb") as f:
                    raw = f.read()
                try:
                    text = raw.decode("utf-8")
                except UnicodeDecodeError as e:
                    problems.append((path, 0, "not valid UTF-8: %s" % e))
                    continue
                body, shift = strip_server_wrapper(text)
                tmp_path = os.path.join(tmp, os.path.basename(path)[:-3] + ".livecodescript")
                with open(tmp_path, "w", encoding="utf-8") as f:
                    f.write(body)
                for p in chk.check_file(tmp_path):
                    problems.append((path, p.line + shift if p.line else 0, p.msg))
            else:
                for p in chk.check_file(path):
                    problems.append((path, p.line, p.msg))
    rel = lambda p: os.path.relpath(p, ROOT)
    if problems:
        for path, line, msg in sorted(problems):
            print("%s:%s: %s" % (rel(path), line, msg))
        print("\ncheck_engine_rules: %d problem(s) in %d file(s) checked" % (len(problems), len(targets)))
        return 1
    print("check_engine_rules: OK (%d files checked against the suite's 22 engine rules)" % len(targets))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
