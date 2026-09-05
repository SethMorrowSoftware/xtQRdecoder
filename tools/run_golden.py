#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
run_golden.py - decode the five golden fixtures in qr/fixtures headlessly,
through the PUBLIC API of the ACTUAL qr/*.lc modules, under tools/lcs_model.py
(an execution MODEL of the engine, not the engine).

    python3 tools/run_golden.py                 # all five fixtures
    python3 tools/run_golden.py --only hello    # name fragments
    python3 tools/run_golden.py --skip test.png,139
    python3 tools/run_golden.py --lib           # the combined lib build
    python3 tools/run_golden.py --time-limit 600

The ONLY handler replaced is luminanceSource_decodeRawPlane (the engine's
image-object decode): a pure-Python PNG decoder below produces the engine's
imageData layout - 4 bytes per pixel in the order 0,R,G,B, row-major, alpha
dropped, palette images expanded through the PLTE - and everything from the
luminance conversion onward is the .lc text itself.

Each fixture runs twice: qrDecodeFromData with the hints qr/qr_golden.lc
uses, and qrDecodeResultRobust with TRY_HARDER (the multi-strategy path the
scanner uses). Exit status is non-zero on any FAIL or model error. A fixture
that exceeds --time-limit seconds (default 600) is reported as TIMEOUT, not
hidden.

A PASS here is a MODEL pass: it never promotes a fixture to engine-verified
(tools/MODEL.md). A FAIL is a model bug until proven otherwise.
"""
import argparse
import os
import signal
import struct
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import lcs_model  # noqa: E402
from build_livecodescript import MODULES  # noqa: E402

FIXTURES = os.path.join(ROOT, "qr", "fixtures")
GOSUSLUGI = ("https://www.gosuslugi.ru/covid-cert/verify/9770000014233333"
             "?lang=ru&ck=733a9d218d312fe134f1c2cc06e1a800")
RAMP = "".join(chr(i) for i in range(256))

# (file, hints for qrDecodeFromData, expected, description)
CASES = [
    ("hello_world.png", "", "Hello world!", "Hello world!"),
    ("empty.png", "", "", "(no decode: empty result, error set)"),
    ("test.png", "TRY_HARDER", GOSUSLUGI, "gosuslugi URL"),
    ("139225861-398ccbbd-2bfd-4736-889b-878c10573888.png", "TRY_HARDER,NR_ALLOW_SKIP_ROWS=0",
     GOSUSLUGI, "gosuslugi URL"),
    ("binary-test.png", "BINARY_MODE", RAMP, "the 256-byte ramp 0x00..0xFF"),
]


# ------------------------------------------------------------ PNG decoder --

class PNGError(Exception):
    pass


def _paeth(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _unfilter(raw, w, h, bpp, stride):
    """Undo the five PNG scanline filters. Returns the concatenated rows."""
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        ft = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if len(line) != stride:
            raise PNGError("truncated image data")
        if ft == 0:
            pass
        elif ft == 1:                                   # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:                                   # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:                                   # Average
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif ft == 4:                                   # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                c = prev[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + _paeth(a, prev[i], c)) & 255
        else:
            raise PNGError("unknown filter type %d on row %d" % (ft, y))
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return out


def _unpack_samples(row, w, channels, bitdepth):
    """One scanline -> list of 8-bit samples (16-bit takes the high byte;
    sub-byte depths scale to 0..255 for grey, raw index for palette)."""
    if bitdepth == 8:
        return list(row[:w * channels])
    if bitdepth == 16:
        return list(row[0:w * channels * 2:2])
    n = w * channels
    per_byte = 8 // bitdepth
    mask = (1 << bitdepth) - 1
    out = []
    for i in range(n):
        byte = row[i // per_byte]
        shift = 8 - bitdepth * (1 + i % per_byte)
        out.append((byte >> shift) & mask)
    return out


def decode_png(data):
    """PNG bytes -> (width, height, raw) where raw is the engine imageData
    layout as a Python str of code points 0..255: per pixel 0,R,G,B."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise PNGError("not a PNG file")
    pos = 8
    ihdr = None
    plte = None
    idat = []
    while pos + 8 <= len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"PLTE":
            plte = body
        elif typ == b"IDAT":
            idat.append(body)
        elif typ == b"IEND":
            break
    if ihdr is None:
        raise PNGError("no IHDR")
    w, h, bitdepth, ctype, comp, filt, interlace = ihdr
    if comp != 0 or filt != 0:
        raise PNGError("unsupported compression/filter method")
    if interlace != 0:
        raise PNGError("Adam7 interlaced PNGs are not supported by this decoder")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype)
    if channels is None:
        raise PNGError("unknown colour type %d" % ctype)
    if ctype == 3 and plte is None:
        raise PNGError("palette image without PLTE")
    raw = zlib.decompress(b"".join(idat))
    bits_per_pixel = channels * bitdepth
    stride = (w * bits_per_pixel + 7) // 8
    bpp = max(1, bits_per_pixel // 8)
    rows = _unfilter(raw, w, h, bpp, stride)
    out = bytearray(w * h * 4)
    grey_scale = 255 // ((1 << bitdepth) - 1) if bitdepth < 8 else 1
    o = 0
    for y in range(h):
        row = rows[y * stride:(y + 1) * stride]
        s = _unpack_samples(row, w, channels, bitdepth)
        if ctype == 6:                      # RGBA: alpha dropped
            for x in range(w):
                i = x * 4
                out[o + 1] = s[i]
                out[o + 2] = s[i + 1]
                out[o + 3] = s[i + 2]
                o += 4
        elif ctype == 2:                    # RGB
            for x in range(w):
                i = x * 3
                out[o + 1] = s[i]
                out[o + 2] = s[i + 1]
                out[o + 3] = s[i + 2]
                o += 4
        elif ctype == 3:                    # palette -> PLTE (tRNS ignored: alpha dropped)
            for x in range(w):
                i = s[x] * 3
                if i + 2 >= len(plte):
                    raise PNGError("palette index %d out of range" % s[x])
                out[o + 1] = plte[i]
                out[o + 2] = plte[i + 1]
                out[o + 3] = plte[i + 2]
                o += 4
        elif ctype == 0:                    # grey
            for x in range(w):
                g = s[x] * grey_scale
                out[o + 1] = g
                out[o + 2] = g
                out[o + 3] = g
                o += 4
        else:                               # grey + alpha
            for x in range(w):
                g = s[x * 2] * grey_scale
                out[o + 1] = g
                out[o + 2] = g
                out[o + 3] = g
                o += 4
    return w, h, out.decode("latin-1")


# ------------------------------------------------------------ the runner --

class Timeout(Exception):
    pass


def _alarm(signum, frame):
    raise Timeout()


def load_model(use_lib, count):
    srcs = []
    if use_lib:
        path = os.path.join(ROOT, "lib", "xtQRdecoder.livecodescript")
        srcs.append(("lib/xtQRdecoder.livecodescript",
                     lcs_model.strip_script_header(open(path, encoding="utf-8").read())))
    else:
        for m in MODULES:
            path = os.path.join(ROOT, "qr", m + ".lc")
            srcs.append(("qr/%s.lc" % m, lcs_model.strip_server_tags(open(path, encoding="utf-8").read())))
    model = lcs_model.Model(srcs, count_statements=count)

    def decode_raw_plane(image_data, max_dim=""):
        # the engine image-object path, replaced: PNG bytes -> {width,height,raw}
        try:
            w, h, raw = decode_png(lcs_model.Model.to_text(image_data).encode("latin-1"))
        except (PNGError, zlib.error) as e:
            raise lcs_model.LCThrow("NotFound: image did not decode (%s)" % e)
        return {"width": w, "height": h, "raw": raw}

    model.override("luminanceSource_decodeRawPlane", decode_raw_plane)
    model.compile_all()
    return model


def describe(v, limit=80):
    if isinstance(v, dict):
        return "(array: %s)" % ", ".join("%s=%s" % (k, describe(x, 40)) for k, x in v.items())
    s = lcs_model.Model.to_text(v)
    if any(ord(c) < 32 or ord(c) > 126 for c in s):
        return "(%d bytes: %s%s)" % (len(s), s[:16].encode("latin-1").hex(), "..." if len(s) > 16 else "")
    return s if len(s) <= limit else s[:limit - 3] + "..."


def run_case(model, fname, hints, expected, limit):
    path = os.path.join(FIXTURES, fname)
    data = open(path, "rb").read().decode("latin-1")
    signal.signal(signal.SIGALRM, _alarm)
    results = []
    # 1. qrDecodeFromData with the qr_golden.lc hints
    t0 = time.time()
    signal.alarm(limit)
    try:
        got = model.call("qrDecodeFromData", data, hints)
        ok = lcs_model.Model.eq(got, expected)
        err = ""
        if fname == "empty.png":
            res = model.call("qrDecodeResult", data, hints)
            err = res.get("error", "") if isinstance(res, dict) else ""
            ok = ok and err != ""
        status = "PASS" if ok else "FAIL"
        detail = describe(got) + ((" [error: %s]" % describe(err)) if err else "")
    except Timeout:
        status, detail = "TIMEOUT", "exceeded %ds" % limit
    except lcs_model.ModelError as e:
        status, detail = "MODEL ERROR", str(e)
    finally:
        signal.alarm(0)
    results.append(("qrDecodeFromData(%s)" % (hints or "no hints"), status, detail, time.time() - t0))
    # 2. qrDecodeResultRobust with TRY_HARDER
    t0 = time.time()
    signal.alarm(limit)
    try:
        res = model.call("qrDecodeResultRobust", data, "TRY_HARDER")
        if fname == "empty.png":
            ok = isinstance(res, dict) and res.get("error", "") != ""
            detail = "error: %s" % describe(res.get("error", "")) if isinstance(res, dict) else describe(res)
        else:
            key = "bytes" if fname == "binary-test.png" else "text"
            got = res.get(key, "") if isinstance(res, dict) else ""
            ok = isinstance(res, dict) and res.get("error", "") == "" and lcs_model.Model.eq(got, expected)
            detail = describe(got)
            if isinstance(res, dict):
                detail += "  [strategy %s %sx%s]" % (res.get("strategy"), res.get("procW"), res.get("procH"))
                if res.get("error"):
                    detail += " error: " + describe(res.get("error"))
        status = "PASS" if ok else "FAIL"
    except Timeout:
        status, detail = "TIMEOUT", "exceeded %ds" % limit
    except lcs_model.ModelError as e:
        status, detail = "MODEL ERROR", str(e)
    finally:
        signal.alarm(0)
    results.append(("qrDecodeResultRobust(TRY_HARDER)", status, detail, time.time() - t0))
    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--only", default="", help="comma list of fixture-name fragments to run")
    ap.add_argument("--skip", default="", help="comma list of fixture-name fragments to skip")
    ap.add_argument("--lib", action="store_true", help="use lib/xtQRdecoder.livecodescript")
    ap.add_argument("--count", action="store_true", help="count executed statements")
    ap.add_argument("--time-limit", type=int, default=600, help="seconds per decode call (default 600)")
    args = ap.parse_args()

    t0 = time.time()
    try:
        model = load_model(args.lib, args.count)
    except lcs_model.ModelError as e:
        print("MODEL ERROR while loading/compiling:\n%s" % e)
        return 2
    print("loaded %s in %.2fs; luminanceSource_decodeRawPlane overridden by a pure-Python PNG decoder"
          % ("lib/xtQRdecoder.livecodescript" if args.lib else "%d qr/*.lc modules" % len(MODULES), time.time() - t0))

    only = [w.strip().lower() for w in args.only.split(",") if w.strip()]
    skip = [w.strip().lower() for w in args.skip.split(",") if w.strip()]
    nfail = 0
    nrun = 0
    total_t = 0.0
    for fname, hints, expected, desc in CASES:
        low = fname.lower()
        if only and not any(w in low for w in only):
            continue
        if skip and any(w in low for w in skip):
            continue
        nrun += 1
        print("\n%s  (expect: %s)" % (fname, desc))
        n0 = model.statements_executed
        for label, status, detail, dt in run_case(model, fname, hints, expected, args.time_limit):
            total_t += dt
            print("   %-38s %-11s %7.2fs  %s" % (label, status, dt, detail))
            if status != "PASS":
                nfail += 1
        if args.count:
            print("   statements executed for this fixture: %d" % (model.statements_executed - n0))
    print()
    if args.count:
        print("statements executed: %d in %.1fs decode time = %.0f statements/sec"
              % (model.statements_executed, total_t, model.statements_executed / total_t if total_t else 0))
    if nrun == 0:
        print("no fixture selected")
        return 2
    if nfail == 0:
        print("ALL GOLDEN DECODES PASSED under the model (%d fixtures, %.1fs). Not an engine pass."
              % (nrun, total_t))
        return 0
    print("%d golden decode(s) FAILED / timed out / hit a model error (%.1fs)." % (nfail, total_t))
    return 1


if __name__ == "__main__":
    sys.exit(main())
