#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
gen_synthetic_fixtures.py - (re)generate qr/fixtures/synthetic/: a corpus of
synthetic QR images from an INDEPENDENT encoder (the Python `qrcode`
library), rasterised by a pure-Python PNG writer, plus manifest.tsv.

    python3 tools/gen_synthetic_fixtures.py            # rewrite the corpus
    python3 tools/gen_synthetic_fixtures.py --check    # committed corpus == regenerated?
    python3 tools/gen_synthetic_fixtures.py --out DIR  # generate elsewhere

Needs `pip install qrcode` (pinned in CI; the fixtures are COMMITTED so the
runners - tools/run_synthetic.py and qr/qr_synthetic.lc - never need it).
The generation is deterministic (seeded payloads, integer rasterisation,
nearest-neighbour rotation), so --check regenerates every image in memory
and compares PIXELS with the committed PNGs (not bytes: zlib output may
differ between builds) and the manifest text exactly; a drift fails CI, so a
change to the corpus is always a deliberate, reviewed commit.

WHAT THE CORPUS COVERS (46 images, all with a documented expected outcome):
  * every version class 1..40 across the four EC levels, numeric /
    alphanumeric / byte payloads;
  * all eight data masks on one symbol;
  * rotations (5..270 degrees; +45 is EXCLUDED: ZXing itself fails it at
    this scale, so it would be a test of the oracle, not the port);
  * a mirrored (transposed) symbol and two inverted ones (white on black);
  * uneven lighting, blur, noise, and a combination;
  * tight and off-centre quiet zones, 1 px and 2 px per module;
  * a UTF-8 byte payload and a clean "pure barcode" symbol.
Each manifest row also names the hints that row needs (TRY_HARDER for the
lot; ALSO_INVERTED for the inverted images) and, for the inverted images, a
second row proving they FAIL without the flag (expect "error:NotFound").

MANIFEST FORMAT (tab-separated, "#" lines are comments; pure ASCII):
  file  version  ec  mask  hints  expect  text_hex  note
    expect   "text" (decode must equal text_hex) or "error:<prefix>"
    text_hex the expected text as hex of its UTF-8 bytes
"""
import argparse
import math
import os
import random
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_OUT = os.path.join(ROOT, "qr", "fixtures", "synthetic")
SEED = 20260905

ALNUM = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
ASCII = "".join(chr(c) for c in range(32, 127))


# ------------------------------------------------------------ rasterising --
def png_gray_bytes(w, h, pix):
    raw = b"".join(b"\x00" + bytes(row) for row in pix)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def raster(m, scale, border, fg=0, bg=255):
    n = len(m)
    size = (n + 2 * border) * scale
    pix = [[bg] * size for _ in range(size)]
    for r in range(n):
        for c in range(n):
            if m[r][c]:
                for yy in range((r + border) * scale, (r + border + 1) * scale):
                    row = pix[yy]
                    for xx in range((c + border) * scale, (c + border + 1) * scale):
                        row[xx] = fg
    return pix


def rotate(pix, deg, bg=255):
    h, w = len(pix), len(pix[0])
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    W = int(math.ceil(abs(w * ca) + abs(h * sa)))
    H = int(math.ceil(abs(w * sa) + abs(h * ca)))
    cx, cy, CX, CY = w / 2, h / 2, W / 2, H / 2
    out = []
    for y in range(H):
        row = []
        for x in range(W):
            dx, dy = x + 0.5 - CX, y + 0.5 - CY
            sx = ca * dx + sa * dy + cx
            sy = -sa * dx + ca * dy + cy
            ix, iy = int(math.floor(sx)), int(math.floor(sy))
            row.append(pix[iy][ix] if 0 <= ix < w and 0 <= iy < h else bg)
        out.append(row)
    return out


def transpose(pix):
    return [list(r) for r in zip(*pix)]


def invert(pix):
    return [[255 - v for v in r] for r in pix]


def gradient(pix, lo=60, hi=255):
    w = len(pix[0])
    return [[int(v * (lo + (hi - lo) * x / max(1, w - 1)) / 255) for x, v in enumerate(r)] for r in pix]


def blur(pix):
    h, w = len(pix), len(pix[0])
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            s = n = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w:
                        s += pix[yy][xx]
                        n += 1
            row.append(s // n)
        out.append(row)
    return out


def noise(pix, rnd, amp=40):
    return [[max(0, min(255, v + rnd.randint(-amp, amp))) for v in r] for r in pix]


def pad(pix, left, top, right, bottom, bg=255):
    w = len(pix[0])
    return ([[bg] * (w + left + right) for _ in range(top)]
            + [[bg] * left + r + [bg] * right for r in pix]
            + [[bg] * (w + left + right) for _ in range(bottom)])


# --------------------------------------------------------------- encoding --
def matrix(text, version=None, ec="M", mask=None):
    import qrcode
    import qrcode.constants as C
    levels = {"L": C.ERROR_CORRECT_L, "M": C.ERROR_CORRECT_M, "Q": C.ERROR_CORRECT_Q, "H": C.ERROR_CORRECT_H}
    q = qrcode.QRCode(version=version, error_correction=levels[ec], box_size=1, border=0, mask_pattern=mask)
    q.add_data(text)
    q.make(fit=(version is None))
    return q.get_matrix(), q.version


def rand_text(rnd, n, alphabet):
    return "".join(rnd.choice(alphabet) for _ in range(n))


def build_corpus():
    """Return [(name, pix, rows)]: the images and their manifest rows
    (version, ec, mask, hints, expect, text, note)."""
    rnd = random.Random(SEED)
    out = []

    def emit(name, pix, text, version, ec, mask, note, hints="TRY_HARDER", expect="text", extra_rows=()):
        rows = [(version, ec, mask, hints, expect, text, note)] + list(extra_rows)
        out.append((name, pix, rows))

    # 1. versions x EC, payloads sized to the version
    for ver, ec, kind in [(1, "L", "num"), (1, "H", "alnum"), (2, "M", "byte"), (3, "Q", "byte"),
                          (4, "L", "alnum"), (5, "H", "num"), (6, "M", "byte"), (7, "L", "byte"),
                          (8, "Q", "alnum"), (10, "M", "byte"), (12, "H", "byte"), (15, "L", "num"),
                          (18, "M", "byte"), (20, "Q", "byte"), (25, "L", "byte"), (30, "M", "alnum"),
                          (35, "H", "byte"), (40, "L", "byte")]:
        cap = {"L": 0.55, "M": 0.45, "Q": 0.33, "H": 0.25}[ec] * (ver * ver * 16 + ver * 128 + 100) // 8
        n = max(4, int(cap * 0.6))
        if kind == "num":
            text = rand_text(rnd, int(n * 2.4), "0123456789")
        elif kind == "alnum":
            text = rand_text(rnd, int(n * 1.6), ALNUM)
        else:
            text = rand_text(rnd, n, ASCII)
        m, v = matrix(text, version=ver, ec=ec)
        scale = 4 if v <= 10 else 3
        emit("v%02d-%s-%s" % (ver, ec, kind), raster(m, scale, 4), text, v, ec, None,
             "axis-aligned, scale %d, border 4" % scale)
    # 2. all 8 masks on a v2-M byte symbol
    for mk in range(8):
        text = "mask %d oxt.org" % mk
        m, v = matrix(text, version=2, ec="M", mask=mk)
        emit("mask%d-v2M" % mk, raster(m, 3, 4), text, v, "M", mk, "mask %d, scale 3" % mk)
    # 3. rotations of a v3-Q symbol (+45 excluded: ZXing fails it too at this scale)
    base_text = "ROTATE ME 12345 OpenXTalk"
    m, v = matrix(base_text, version=3, ec="Q")
    for deg in (5, 12, 25, 90, 180, 270, -30):
        emit("rot%+03d-v3Q" % deg, rotate(raster(m, 5, 5), deg), base_text, v, "Q", None,
             "rotated %d deg, nearest neighbour" % deg)
    # 4. mirrored (transposed) symbol: the decoder's mirror retry
    emit("mirror-v3Q", transpose(raster(m, 5, 5)), base_text, v, "Q", None, "transposed image (mirror retry)")
    # 5. inverted (white on black): decodes only under ALSO_INVERTED, and must
    #    FAIL without it (the second row pins the flag's meaning)
    for name, pix, note in (("inverted-v3Q", invert(raster(m, 5, 5)), "inverted: white modules on black"),
                            ("inverted-rot15-v3Q", invert(rotate(raster(m, 5, 5), 15)), "inverted + rotated 15 deg")):
        emit(name, pix, base_text, v, "Q", None, note, hints="TRY_HARDER,ALSO_INVERTED",
             extra_rows=[(v, "Q", None, "TRY_HARDER", "error:NotFound", base_text, note + " (no ALSO_INVERTED: must fail)")])
    # 6. lighting / blur / noise on a v4-M symbol
    t6 = "Lighting test: 0123456789 abc XYZ"
    m6, v6 = matrix(t6, version=4, ec="M")
    emit("gradient-v4M", gradient(raster(m6, 5, 4)), t6, v6, "M", None, "left-right lighting ramp 60..255")
    emit("blur-v4M", blur(raster(m6, 5, 4)), t6, v6, "M", None, "3x3 box blur")
    emit("noise-v4M", noise(raster(m6, 5, 4), rnd, 45), t6, v6, "M", None, "random noise +-45")
    emit("blur-gradient-rot8-v4M", blur(gradient(rotate(raster(m6, 6, 4), 8))), t6, v6, "M", None,
         "blur + gradient + 8 deg")
    # 7. quiet zone / odd geometry
    mq, vq = matrix("tight quiet zone", version=2, ec="L")
    emit("quiet1-v2L", raster(mq, 4, 1), "tight quiet zone", vq, "L", None, "border 1 module")
    emit("quiet2-v2L-offcentre", pad(raster(mq, 3, 2), 7, 13, 41, 29), "tight quiet zone", vq, "L", None,
         "border 2, padded off-centre to odd size")
    ms, vs = matrix("scale two pixels per module 1234567890", version=5, ec="M")
    emit("scale2-v5M", raster(ms, 2, 4), "scale two pixels per module 1234567890", vs, "M", None,
         "only 2 px per module")
    m1, v1 = matrix("one pixel per module", version=3, ec="L")
    emit("scale1-v3L", raster(m1, 1, 4), "one pixel per module", v1, "L", None, "1 px per module")
    # 8. a UTF-8 byte payload (no ECI: the charset is guessed from the bytes)
    u = "café – über € 12"
    mu, vu = matrix(u, version=None, ec="M")
    emit("utf8-bytes", raster(mu, 4, 4), u, vu, "M", None, "byte mode carrying UTF-8, guessed charset")
    # 9. a clean bordered symbol, also decoded through the PURE_BARCODE path
    mp, vp = matrix("pure barcode path", version=2, ec="M")
    emit("pure-v2M", raster(mp, 3, 3), "pure barcode path", vp, "M", None, "clean bordered symbol",
         extra_rows=[(vp, "M", None, "PURE_BARCODE", "text", "pure barcode path", "the PURE_BARCODE fast path")])
    return out


def manifest_text(corpus):
    lines = ["# xtQRdecoder synthetic fixtures - GENERATED by tools/gen_synthetic_fixtures.py; do not edit",
             "# file\tversion\tec\tmask\thints\texpect\ttext_hex\tnote"]
    for name, _pix, rows in corpus:
        for version, ec, mask, hints, expect, text, note in rows:
            lines.append("\t".join([name + ".png", str(version), ec, "" if mask is None else str(mask),
                                    hints, expect, text.encode("utf-8").hex(), note]))
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", default=DEFAULT_OUT, help="output directory (default qr/fixtures/synthetic)")
    ap.add_argument("--check", action="store_true", help="compare the committed corpus with a regeneration")
    args = ap.parse_args()
    try:
        import qrcode  # noqa: F401
    except ImportError:
        print("gen_synthetic_fixtures.py needs the `qrcode` package: pip install qrcode", file=sys.stderr)
        return 2
    corpus = build_corpus()
    text = manifest_text(corpus)
    if not text.isascii():
        print("ERROR: manifest is not pure ASCII", file=sys.stderr)
        return 1
    if args.check:
        sys.path.insert(0, HERE)
        from run_golden import decode_png
        bad = []
        for name, pix, _rows in corpus:
            path = os.path.join(args.out, name + ".png")
            if not os.path.isfile(path):
                bad.append("%s: missing" % name)
                continue
            w, h, raw = decode_png(open(path, "rb").read())
            if isinstance(raw, str):          # the model's byte strings are latin-1 str
                raw = raw.encode("latin-1")
            if (w, h) != (len(pix[0]), len(pix)):
                bad.append("%s: size %dx%d, expected %dx%d" % (name, w, h, len(pix[0]), len(pix)))
                continue
            want = bytearray()
            for row in pix:
                for v in row:
                    want += bytes((0, v, v, v))
            if bytes(want) != raw:
                bad.append("%s: pixels differ" % name)
        mpath = os.path.join(args.out, "manifest.tsv")
        if not os.path.isfile(mpath) or open(mpath, encoding="ascii").read() != text:
            bad.append("manifest.tsv differs from the regenerated manifest")
        names = set(name + ".png" for name, _p, _r in corpus)
        extra = sorted(f for f in os.listdir(args.out) if f.endswith(".png") and f not in names)
        if extra:
            bad.append("untracked images in the corpus directory: " + ", ".join(extra))
        if bad:
            print("synthetic corpus is STALE (%d problem(s)):" % len(bad))
            for b in bad:
                print("  - " + b)
            print("regenerate with: python3 tools/gen_synthetic_fixtures.py")
            return 1
        print("synthetic corpus is up to date: %d images, %d manifest rows"
              % (len(corpus), sum(len(r) for _n, _p, r in corpus)))
        return 0
    os.makedirs(args.out, exist_ok=True)
    for name, pix, _rows in corpus:
        with open(os.path.join(args.out, name + ".png"), "wb") as f:
            f.write(png_gray_bytes(len(pix[0]), len(pix), pix))
    with open(os.path.join(args.out, "manifest.tsv"), "w", encoding="ascii") as f:
        f.write(text)
    print("wrote %d images and manifest.tsv (%d rows) to %s"
          % (len(corpus), sum(len(r) for _n, _p, r in corpus), os.path.relpath(args.out, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
