#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
run_synthetic.py - decode the synthetic corpus in qr/fixtures/synthetic
headlessly, through the PUBLIC API of the ACTUAL qr/*.lc modules, under
tools/lcs_model.py (an execution MODEL of the engine, not the engine).

    python3 tools/run_synthetic.py                # every manifest row
    python3 tools/run_synthetic.py --only rot,mask
    python3 tools/run_synthetic.py --lib          # the combined stack
    python3 tools/run_synthetic.py --time-limit 900

Each manifest row (see tools/gen_synthetic_fixtures.py for the format) is
one call to qrDecodeResultRobust(pngBytes, hints) - the scanner's path - and
passes when the decoded text equals the row's UTF-8 text byte for byte, or,
for an "error:<prefix>" row, when the result's ["error"] begins with that
prefix. The only handler replaced is the engine image object
(luminanceSource_decodeRawPlane), by run_golden.py's pure-Python PNG
decoder. Exit status is non-zero on any FAIL, TIMEOUT or model error.

qr/qr_synthetic.lc is the same check on an engine; a PASS here is a MODEL
pass and never promotes a fixture to engine-verified (tools/MODEL.md).
"""
import argparse
import os
import signal
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import lcs_model  # noqa: E402
from run_golden import Timeout, _alarm, describe, load_model  # noqa: E402

CORPUS = os.path.join(ROOT, "qr", "fixtures", "synthetic")


def read_manifest(path):
    rows = []
    for ln in open(path, encoding="ascii"):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        parts = ln.split("\t")
        if len(parts) != 8:
            raise SystemExit("manifest row with %d fields (want 8): %r" % (len(parts), ln))
        f, version, ec, mask, hints, expect, text_hex, note = parts
        rows.append({"file": f, "version": version, "ec": ec, "mask": mask, "hints": hints,
                     "expect": expect, "text": bytes.fromhex(text_hex).decode("utf-8"), "note": note})
    return rows


def run_row(model, row, limit):
    data = open(os.path.join(CORPUS, row["file"]), "rb").read().decode("latin-1")
    signal.signal(signal.SIGALRM, _alarm)
    signal.alarm(limit)
    t0 = time.time()
    try:
        res = model.call("qrDecodeResultRobust", data, row["hints"])
        if not isinstance(res, dict):
            return "FAIL", "non-array result %s" % describe(res), time.time() - t0
        err = lcs_model.Model.to_text(res.get("error", ""))
        text = lcs_model.Model.to_text(res.get("text", "")) if not err else ""
        exp = row["expect"]
        if exp == "text":
            ok = (err == "" and text == row["text"])
        elif exp.startswith("error:"):
            ok = err.startswith(exp[6:])
        else:
            ok = False
        if err:
            detail = "error: " + err[:90]
        else:
            detail = "strategy %s %sx%s" % (res.get("strategy"), res.get("procW"), res.get("procH"))
            if res.get("mirrored"):
                detail += " mirrored"
            if res.get("inverted"):
                detail += " inverted"
            if not ok:
                detail += "  got %s" % describe(text, 60)
        return ("PASS" if ok else "FAIL"), detail, time.time() - t0
    except Timeout:
        return "TIMEOUT", "exceeded %ds" % limit, time.time() - t0
    except lcs_model.LCThrow as e:
        return "FAIL", "uncaught throw: " + lcs_model.Model.to_text(e.value), time.time() - t0
    except lcs_model.ModelError as e:
        return "MODEL ERROR", str(e), time.time() - t0
    finally:
        signal.alarm(0)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--only", default="", help="comma list of file-name fragments to run")
    ap.add_argument("--lib", action="store_true", help="use lib/xtQRdecoder.livecodescript")
    ap.add_argument("--count", action="store_true", help="count executed statements")
    ap.add_argument("--time-limit", type=int, default=600, help="seconds per decode (default 600)")
    args = ap.parse_args()

    rows = read_manifest(os.path.join(CORPUS, "manifest.tsv"))
    only = [w.strip().lower() for w in args.only.split(",") if w.strip()]
    if only:
        rows = [r for r in rows if any(w in r["file"].lower() for w in only)]
    t0 = time.time()
    try:
        model = load_model(args.lib, args.count)
    except lcs_model.ModelError as e:
        print("MODEL ERROR while loading/compiling:\n%s" % e)
        return 2
    print("loaded %s in %.2fs; %d manifest rows"
          % ("lib/xtQRdecoder.livecodescript" if args.lib else "the qr/*.lc modules", time.time() - t0, len(rows)))
    nbad = 0
    total = 0.0
    for row in rows:
        status, detail, dt = run_row(model, row, args.time_limit)
        total += dt
        if status != "PASS":
            nbad += 1
        print("%-11s %-26s %6.1fs  v%-2s %s  [%s]  %s" % (status, row["file"], dt, row["version"], row["ec"],
                                                        row["hints"], detail))
    print()
    if args.count:
        print("statements executed: %d" % model.statements_executed)
    if nbad == 0:
        print("ALL %d SYNTHETIC ROWS PASSED in %.1fs under the model. Not an engine pass: the label "
              "stays 'verified statically; needs an OXT pass'." % (len(rows), total))
        return 0
    print("%d of %d synthetic rows FAILED (%.1fs). A failure here is a MODEL bug or a real defect; "
          "the fixtures' expected values come from an independent encoder." % (nbad, len(rows), total))
    return 1


if __name__ == "__main__":
    sys.exit(main())
