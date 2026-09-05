#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
test_model_mutations.py - mutation tests for the unit suites: prove that
the qr/suite_*.lc assertions, run under tools/lcs_model.py, actually turn
red when a realistic defect is seeded into a library module.

    python3 tools/test_model_mutations.py

Each case copies the qr/*.lc modules to a temporary directory, applies one
textual mutation (a wrong table entry, a flipped comparison, a disabled
retry, a dropped hint spelling ...), runs all the suites with the byte-exact
reporter and requires at least one assertion to fail (or a suite to throw).
A positive control runs the unmutated modules first and requires zero
failures. Exit status is non-zero if any seeded defect survives.

The mutations were chosen to cover each layer (tables, GF arithmetic,
Reed-Solomon, bit storage, bitstream parsing, luminance, the decoder's
retries, the reader's hint semantics); a mutation that the suites do NOT
catch is a coverage gap to fill, never a reason to weaken this test.
"""
import glob
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import lcs_model  # noqa: E402
from build_livecodescript import MODULES  # noqa: E402
from run_unit_tests import HARNESS, SUITES  # noqa: E402

# (module, old text, new text, what the defect is)
MUTATIONS = [
    ("version.lc", '"40~6,30,58,86,114,142,170~', '"40~6,30,58,86,114,142,168~',
     "version table: a v40 alignment centre off by two"),
    ("dataMask.lc", "return ((j mod 3) = 0)", "return ((j mod 3) = 1)",
     "data mask 2 condition inverted"),
    ("genericGF.lc", "constant kGFPrimitive = 285", "constant kGFPrimitive = 301",
     "GF(256) primitive polynomial wrong"),
    ("reedSolomonDecoder.lc", "repeat while (2 * poly_degree(r)) >= pTwoT", "repeat while (2 * poly_degree(r)) > pTwoT",
     "Euclidean stop condition off by one (the odd-twoS defect)"),
    ("bitMatrix.lc", "bitAnd 1) = 1)", "bitAnd 1) = 0)",
     "bitMatrix_get polarity inverted"),
    ("decodedBitStreamParser.lc",
     'constant kAlphanumChars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"',
     'constant kAlphanumChars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ %$*+-./:"',
     "alphanumeric table: two symbols swapped"),
    ("luminanceSource.lc", "div 4) into tLum[p]", "div 3) into tLum[p]",
     "luminance weights wrong"),
    ("decoder.lc", "bmp_setMirror parser, true", "bmp_setMirror parser, false",
     "mirror retry disabled"),
    ("qrCodeReader.lc", 'qr_hintFlag(pHints, "ALSO_INVERTED")', 'qr_hintFlag(pHints, "ALSO_INVERTEDX")',
     "ALSO_INVERTED hint ignored"),
    ("qrReader.lc", '(v is "0") or (v is "no") or (v is "off")', '(v is "0") or (v is "off")',
     "hint off-spelling 'no' dropped"),
]


def run_suites(qrdir):
    """Return (failures, errors): failing assertion names and suite-level errors."""
    srcs = []
    for m in MODULES:
        path = os.path.join(qrdir, m + ".lc")
        srcs.append(("qr/%s.lc" % m, lcs_model.strip_server_tags(open(path, encoding="utf-8").read())))
    for p in sorted(glob.glob(os.path.join(ROOT, "qr", "suite_*.lc"))):
        srcs.append(("qr/" + os.path.basename(p), lcs_model.strip_server_tags(open(p, encoding="utf-8").read())))
    srcs.append(("tools/run_unit_tests.py(HARNESS)", HARNESS))
    fails = []
    errors = []
    try:
        model = lcs_model.Model(srcs, overrides={"t_fail": lambda name, got, exp: fails.append(name)})
        model.override("luminanceSource_decodeRawPlane", lambda *a: None)
        model.compile_all()
    except lcs_model.ModelError as e:
        return fails, ["compile: " + str(e).splitlines()[0]]
    for _title, handler in SUITES:
        model.set_local("sCurPass", 0)
        model.set_local("sCurFail", 0)
        try:
            model.call(handler)
        except lcs_model.ModelError as e:
            errors.append("%s: MODEL ERROR %s" % (handler, str(e).splitlines()[0]))
        except lcs_model.LCThrow as e:
            errors.append("%s: uncaught throw %s" % (handler, lcs_model.Model.to_text(e.value)))
    return fails, errors


def main():
    tmp = tempfile.mkdtemp(prefix="xtqr-mut-")
    try:
        pristine = os.path.join(tmp, "pristine")
        os.makedirs(pristine)
        for m in MODULES:
            shutil.copy(os.path.join(ROOT, "qr", m + ".lc"), pristine)
        fails, errors = run_suites(pristine)
        if fails or errors:
            print("test_model_mutations: the unmutated modules do not pass the suites; fix that first")
            for x in fails[:10] + errors[:10]:
                print("  " + x)
            return 1
        print("positive control: pristine modules pass every suite")
        survived = []
        for i, (fname, old, new, desc) in enumerate(MUTATIONS):
            d = os.path.join(tmp, "m%d" % i)
            shutil.copytree(pristine, d)
            path = os.path.join(d, fname)
            text = open(path, encoding="utf-8").read()
            if old not in text:
                print("fixture out of date: %r not found in qr/%s" % (old, fname))
                return 2
            open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
            fails, errors = run_suites(d)
            n = len(fails) + len(errors)
            if n == 0:
                survived.append(desc)
                print("SURVIVED  %-58s (qr/%s)" % (desc, fname))
            else:
                first = (fails + errors)[0]
                print("killed    %-58s %3d red, first: %s" % (desc, n, first[:60]))
    finally:
        shutil.rmtree(tmp)
    print()
    if survived:
        print("test_model_mutations: %d of %d seeded defects SURVIVED the suites" % (len(survived), len(MUTATIONS)))
        for s in survived:
            print("  - " + s)
        return 1
    print("test_model_mutations: all %d seeded defects were caught by the suites" % len(MUTATIONS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
