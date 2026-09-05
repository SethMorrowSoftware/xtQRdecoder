#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
run_unit_tests.py - run the 17 qr/suite_*.lc unit suites headlessly through
tools/lcs_model.py (an execution MODEL of the engine, not the engine).

    python3 tools/run_unit_tests.py            # the qr/*.lc modules + suites
    python3 tools/run_unit_tests.py --lib      # lib/xtQRdecoder.livecodescript + suites
    python3 tools/run_unit_tests.py --time     # per-suite timings
    python3 tools/run_unit_tests.py --count    # statement count / throughput
    python3 tools/run_unit_tests.py --only detector,tables   # a subset

Exit status is non-zero on any failing assertion or any model error.

WHAT A GREEN RUN MEANS. The assertions passed under the model's semantics
(tools/MODEL.md lists every named divergence from the engine). It does NOT
promote anything to engine-verified: the honest label for a handler that has
only passed here remains "verified statically; needs an OXT pass". The suites
are ENGINE-PASSED (399/399 on a 9.6.11-class engine), so a failure here is a
MODEL bug until proven otherwise - fix tools/lcs_model.py, never the .lc
sources or their expected values.

The reporter is defined the way qr/qr_tester.lc defines it: `t_eq pName,
pGot, pExp` compares with the model's own `=` in LiveCodeScript (see HARNESS
below), tallying into script-locals exactly as the web console does.
"""
import argparse
import glob
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import lcs_model  # noqa: E402
from build_livecodescript import MODULES  # noqa: E402

# The suite order of qr_tester.lc's renderPage, titles verbatim.
SUITES = [
    ("qrCompat.lc  -  integer & bitwise layer", "suite_qrCompat"),
    ("genericGF.lc  -  GF(256) field", "suite_genericGF"),
    ("genericGFPoly.lc  -  polynomials over GF(256)", "suite_genericGFPoly"),
    ("reedSolomonDecoder.lc  -  RS decode (ZXing reference vector)", "suite_reedSolomon"),
    ("bitArray.lc  -  packed bit vector", "suite_bitArray"),
    ("bitMatrix.lc  -  packed 2-D bit grid", "suite_bitMatrix"),
    ("bitSource.lc  -  MSB-first bit reader", "suite_bitSource"),
    ("luminanceSource.lc  -  greyscale byte math (s7.3)", "suite_luminance"),
    ("binarizer  -  global histogram + hybrid adaptive", "suite_binarizer"),
    ("tables  -  ErrorCorrectionLevel / Mode / DataMask / FormatInfo / Version", "suite_tables"),
    ("parser  -  DataBlock de-interleave + bitstream decode", "suite_parser"),
    ("decoder  -  end-to-end matrix -> text (real v1 'HI' QR)", "suite_decoder"),
    ("mathUtils  -  round + distance (s8.4)", "suite_mathUtils"),
    ("resultPoint  -  point ops + orderBestPatterns (s8.4)", "suite_resultPoint"),
    ("perspectiveTransform  -  3x3 projective maps (s8.4)", "suite_perspective"),
    ("gridSampler  -  sample a grid through a transform (s8.4)", "suite_gridSampler"),
    ("detector  -  synthetic photo -> finders -> sample -> 'HI' (s8.4)", "suite_detector"),
    ("detector v2  -  alignment pattern -> 'HELLO WORLD' (s8.4)", "suite_detectorV2"),
]

# The reporter, as qr/qr_tester.lc's t_eq: the comparison is the model's `=`
# executed IN LiveCodeScript; only the row recording is native (t_fail).
HARNESS = """
local sCurPass, sCurFail
command t_eq pName, pGot, pExp
   if pGot = pExp then
      add 1 to sCurPass
   else
      add 1 to sCurFail
      t_fail pName, pGot, pExp
   end if
end t_eq
"""


def show(v):
    """Render a model value for a failure row."""
    if isinstance(v, dict):
        return "(array with %d element(s): %s)" % (len(v), ", ".join(
            "%s=%s" % (k, show(x)) for k, x in list(v.items())[:6]) + (", ..." if len(v) > 6 else ""))
    try:
        s = lcs_model.Model.to_text(v)
    except lcs_model.ModelError:
        return repr(v)
    if any(ord(c) < 32 or ord(c) > 126 for c in s):
        if len(s) > 40:
            return "(%d bytes: %s...)" % (len(s), s[:20].encode("latin-1", "replace").hex())
        return repr(s)
    return s if len(s) <= 120 else s[:117] + "..."


def load_sources(use_lib):
    srcs = []
    if use_lib:
        path = os.path.join(ROOT, "lib", "xtQRdecoder.livecodescript")
        text = open(path, encoding="utf-8").read()
        srcs.append(("lib/xtQRdecoder.livecodescript", lcs_model.strip_script_header(text)))
    else:
        for m in MODULES:
            path = os.path.join(ROOT, "qr", m + ".lc")
            srcs.append(("qr/%s.lc" % m, lcs_model.strip_server_tags(open(path, encoding="utf-8").read())))
    for path in sorted(glob.glob(os.path.join(ROOT, "qr", "suite_*.lc"))):
        srcs.append(("qr/" + os.path.basename(path), lcs_model.strip_server_tags(open(path, encoding="utf-8").read())))
    srcs.append(("tools/run_unit_tests.py(HARNESS)", HARNESS))
    return srcs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--lib", action="store_true", help="run against lib/xtQRdecoder.livecodescript")
    ap.add_argument("--time", action="store_true", help="print per-suite timings")
    ap.add_argument("--count", action="store_true", help="count executed statements (throughput)")
    ap.add_argument("--only", default="", help="comma list of suite name fragments to run")
    ap.add_argument("--verbose", "-v", action="store_true", help="print every failing assertion in full")
    args = ap.parse_args()

    failures = []

    def t_fail(name, got, exp):
        failures.append((name, got, exp))

    t0 = time.time()
    try:
        model = lcs_model.Model(load_sources(args.lib), overrides={"t_fail": t_fail},
                                count_statements=args.count)
        # the engine image-object path is never compiled here (MODEL.md D17)
        model.override("luminanceSource_decodeRawPlane", lambda *a: (_ for _ in ()).throw(
            lcs_model.ModelError("luminanceSource_decodeRawPlane is engine I/O; not available in the unit runner")))
        ncomp = model.compile_all()
    except lcs_model.ModelError as e:
        print("MODEL ERROR while loading/compiling:\n%s" % e)
        return 2
    t_compile = time.time() - t0
    print("loaded %s: %d handlers compiled in %.2fs%s"
          % ("lib/xtQRdecoder.livecodescript" if args.lib else "%d qr/*.lc modules" % len(MODULES),
             ncomp, t_compile, " (statement counting on)" if args.count else ""))

    wanted = [w.strip().lower() for w in args.only.split(",") if w.strip()]
    total_pass = total_fail = 0
    model_errors = 0
    t_run0 = time.time()
    for title, handler in SUITES:
        if wanted and not any(w in handler.lower() or w in title.lower() for w in wanted):
            continue
        del failures[:]
        model.set_local("sCurPass", 0)
        model.set_local("sCurFail", 0)
        ts = time.time()
        err = None
        try:
            model.call(handler)
        except lcs_model.ModelError as e:
            err = "MODEL ERROR: %s" % e
        except lcs_model.LCThrow as e:
            err = "uncaught throw: %s" % e.value
        dt = time.time() - ts
        p = model.get_local("sCurPass")
        f = model.get_local("sCurFail")
        p = int(p) if p != "" else 0
        f = int(f) if f != "" else 0
        total_pass += p
        total_fail += f
        status = "ok " if (f == 0 and err is None) else "BAD"
        timing = "  (%.3fs)" % dt if args.time else ""
        print("%s  %-24s %3d passed %3d failed%s   %s" % (status, handler, p, f, timing, title))
        for name, got, exp in failures:
            print("      FAIL  %s\n            got:      %s\n            expected: %s" % (name, show(got), show(exp)))
        if err is not None:
            model_errors += 1
            print("      " + err.replace("\n", "\n      "))
    t_run = time.time() - t_run0

    total = total_pass + total_fail
    print()
    if args.count:
        n = model.statements_executed
        print("statements executed: %d in %.3fs = %.0f statements/sec" % (n, t_run, n / t_run if t_run else 0))
    if total_fail == 0 and model_errors == 0:
        print("ALL %d TESTS PASSED (%d/%d) in %.2fs under the model. Not an engine pass: "
              "the label stays 'verified statically; needs an OXT pass'." % (total, total_pass, total, t_run))
        return 0
    print("%d of %d assertions FAILED, %d suite(s) hit a model error (%.2fs). A failure here is a "
          "MODEL bug until proven otherwise - see tools/MODEL.md." % (total_fail, total, model_errors, t_run))
    return 1


if __name__ == "__main__":
    sys.exit(main())
