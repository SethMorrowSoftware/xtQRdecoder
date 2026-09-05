#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
verify_tables.py - regenerate every constant table the decoder relies on
from FIRST PRINCIPLES (or from ZXing's own source) and compare it with what
the qr/*.lc modules actually produce under tools/lcs_model.py.

    python3 tools/verify_tables.py

A transcription slip in a table is the classic silent defect: the v39/v40
alignment rows were transposed for months without any unit test noticing,
because the tests were written from the same (wrong) table. So every table
is checked against an INDEPENDENT source here:

  * version table (40 rows x 4 EC levels: block layout, EC codewords per
    block, alignment centres): ZXing core Version.java (Apache-2.0, the
    rows embedded below) AND the ISO/IEC 18004 module-count identity - the
    total codewords of a version must equal (data modules) div 8 computed
    from the symbol's function patterns, which does not depend on ZXing;
  * version-information words (v7..40): BCH(18,6) with generator 0x1F25,
    recomputed, compared with ZXing's VERSION_DECODE_INFO and with what
    ver_decodeVersionInformation accepts (exact and every 1-bit error);
  * format-information words (32): BCH(15,5) with generator 0x537 masked
    with 0x5412, recomputed; fmt_decode must return the right EC level and
    mask for every word and every 1-bit error of it;
  * GF(256) exp/log tables and multiplicative inverses from the primitive
    polynomial 0x11D;
  * mode indicators and character-count widths (ISO/IEC 18004 table 3);
  * the alphanumeric table (ISO table 5), the data-mask conditions (ISO
    table 10), and the ECI designator table (ZXing CharacterSetECI).

Exit status is non-zero on any mismatch. The tables the port builds at run
time are exercised by CALLING the real handlers, so the check covers the
parsing code as well as the literals.
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import lcs_model  # noqa: E402
from build_livecodescript import MODULES  # noqa: E402

# ZXing core, com.google.zxing.qrcode.decoder.Version.buildVersions(), as
# (version, alignment centres, [(ecCodewordsPerBlock, [(count, dataCodewords), ...]) for L, M, Q, H]).
# Copyright 2007 ZXing authors, Apache License 2.0.
ZXING_VERSIONS = [
    (1, [], [[7,[[1,19]]],[10,[[1,16]]],[13,[[1,13]]],[17,[[1,9]]]]),
    (2, [6, 18], [[10,[[1,34]]],[16,[[1,28]]],[22,[[1,22]]],[28,[[1,16]]]]),
    (3, [6, 22], [[15,[[1,55]]],[26,[[1,44]]],[18,[[2,17]]],[22,[[2,13]]]]),
    (4, [6, 26], [[20,[[1,80]]],[18,[[2,32]]],[26,[[2,24]]],[16,[[4,9]]]]),
    (5, [6, 30], [[26,[[1,108]]],[24,[[2,43]]],[18,[[2,15],[2,16]]],[22,[[2,11],[2,12]]]]),
    (6, [6, 34], [[18,[[2,68]]],[16,[[4,27]]],[24,[[4,19]]],[28,[[4,15]]]]),
    (7, [6, 22, 38], [[20,[[2,78]]],[18,[[4,31]]],[18,[[2,14],[4,15]]],[26,[[4,13],[1,14]]]]),
    (8, [6, 24, 42], [[24,[[2,97]]],[22,[[2,38],[2,39]]],[22,[[4,18],[2,19]]],[26,[[4,14],[2,15]]]]),
    (9, [6, 26, 46], [[30,[[2,116]]],[22,[[3,36],[2,37]]],[20,[[4,16],[4,17]]],[24,[[4,12],[4,13]]]]),
    (10, [6, 28, 50], [[18,[[2,68],[2,69]]],[26,[[4,43],[1,44]]],[24,[[6,19],[2,20]]],[28,[[6,15],[2,16]]]]),
    (11, [6, 30, 54], [[20,[[4,81]]],[30,[[1,50],[4,51]]],[28,[[4,22],[4,23]]],[24,[[3,12],[8,13]]]]),
    (12, [6, 32, 58], [[24,[[2,92],[2,93]]],[22,[[6,36],[2,37]]],[26,[[4,20],[6,21]]],[28,[[7,14],[4,15]]]]),
    (13, [6, 34, 62], [[26,[[4,107]]],[22,[[8,37],[1,38]]],[24,[[8,20],[4,21]]],[22,[[12,11],[4,12]]]]),
    (14, [6, 26, 46, 66], [[30,[[3,115],[1,116]]],[24,[[4,40],[5,41]]],[20,[[11,16],[5,17]]],[24,[[11,12],[5,13]]]]),
    (15, [6, 26, 48, 70], [[22,[[5,87],[1,88]]],[24,[[5,41],[5,42]]],[30,[[5,24],[7,25]]],[24,[[11,12],[7,13]]]]),
    (16, [6, 26, 50, 74], [[24,[[5,98],[1,99]]],[28,[[7,45],[3,46]]],[24,[[15,19],[2,20]]],[30,[[3,15],[13,16]]]]),
    (17, [6, 30, 54, 78], [[28,[[1,107],[5,108]]],[28,[[10,46],[1,47]]],[28,[[1,22],[15,23]]],[28,[[2,14],[17,15]]]]),
    (18, [6, 30, 56, 82], [[30,[[5,120],[1,121]]],[26,[[9,43],[4,44]]],[28,[[17,22],[1,23]]],[28,[[2,14],[19,15]]]]),
    (19, [6, 30, 58, 86], [[28,[[3,113],[4,114]]],[26,[[3,44],[11,45]]],[26,[[17,21],[4,22]]],[26,[[9,13],[16,14]]]]),
    (20, [6, 34, 62, 90], [[28,[[3,107],[5,108]]],[26,[[3,41],[13,42]]],[30,[[15,24],[5,25]]],[28,[[15,15],[10,16]]]]),
    (21, [6, 28, 50, 72, 94], [[28,[[4,116],[4,117]]],[26,[[17,42]]],[28,[[17,22],[6,23]]],[30,[[19,16],[6,17]]]]),
    (22, [6, 26, 50, 74, 98], [[28,[[2,111],[7,112]]],[28,[[17,46]]],[30,[[7,24],[16,25]]],[24,[[34,13]]]]),
    (23, [6, 30, 54, 78, 102], [[30,[[4,121],[5,122]]],[28,[[4,47],[14,48]]],[30,[[11,24],[14,25]]],[30,[[16,15],[14,16]]]]),
    (24, [6, 28, 54, 80, 106], [[30,[[6,117],[4,118]]],[28,[[6,45],[14,46]]],[30,[[11,24],[16,25]]],[30,[[30,16],[2,17]]]]),
    (25, [6, 32, 58, 84, 110], [[26,[[8,106],[4,107]]],[28,[[8,47],[13,48]]],[30,[[7,24],[22,25]]],[30,[[22,15],[13,16]]]]),
    (26, [6, 30, 58, 86, 114], [[28,[[10,114],[2,115]]],[28,[[19,46],[4,47]]],[28,[[28,22],[6,23]]],[30,[[33,16],[4,17]]]]),
    (27, [6, 34, 62, 90, 118], [[30,[[8,122],[4,123]]],[28,[[22,45],[3,46]]],[30,[[8,23],[26,24]]],[30,[[12,15],[28,16]]]]),
    (28, [6, 26, 50, 74, 98, 122], [[30,[[3,117],[10,118]]],[28,[[3,45],[23,46]]],[30,[[4,24],[31,25]]],[30,[[11,15],[31,16]]]]),
    (29, [6, 30, 54, 78, 102, 126], [[30,[[7,116],[7,117]]],[28,[[21,45],[7,46]]],[30,[[1,23],[37,24]]],[30,[[19,15],[26,16]]]]),
    (30, [6, 26, 52, 78, 104, 130], [[30,[[5,115],[10,116]]],[28,[[19,47],[10,48]]],[30,[[15,24],[25,25]]],[30,[[23,15],[25,16]]]]),
    (31, [6, 30, 56, 82, 108, 134], [[30,[[13,115],[3,116]]],[28,[[2,46],[29,47]]],[30,[[42,24],[1,25]]],[30,[[23,15],[28,16]]]]),
    (32, [6, 34, 60, 86, 112, 138], [[30,[[17,115]]],[28,[[10,46],[23,47]]],[30,[[10,24],[35,25]]],[30,[[19,15],[35,16]]]]),
    (33, [6, 30, 58, 86, 114, 142], [[30,[[17,115],[1,116]]],[28,[[14,46],[21,47]]],[30,[[29,24],[19,25]]],[30,[[11,15],[46,16]]]]),
    (34, [6, 34, 62, 90, 118, 146], [[30,[[13,115],[6,116]]],[28,[[14,46],[23,47]]],[30,[[44,24],[7,25]]],[30,[[59,16],[1,17]]]]),
    (35, [6, 30, 54, 78, 102, 126, 150], [[30,[[12,121],[7,122]]],[28,[[12,47],[26,48]]],[30,[[39,24],[14,25]]],[30,[[22,15],[41,16]]]]),
    (36, [6, 24, 50, 76, 102, 128, 154], [[30,[[6,121],[14,122]]],[28,[[6,47],[34,48]]],[30,[[46,24],[10,25]]],[30,[[2,15],[64,16]]]]),
    (37, [6, 28, 54, 80, 106, 132, 158], [[30,[[17,122],[4,123]]],[28,[[29,46],[14,47]]],[30,[[49,24],[10,25]]],[30,[[24,15],[46,16]]]]),
    (38, [6, 32, 58, 84, 110, 136, 162], [[30,[[4,122],[18,123]]],[28,[[13,46],[32,47]]],[30,[[48,24],[14,25]]],[30,[[42,15],[32,16]]]]),
    (39, [6, 26, 54, 82, 110, 138, 166], [[30,[[20,117],[4,118]]],[28,[[40,47],[7,48]]],[30,[[43,24],[22,25]]],[30,[[10,15],[67,16]]]]),
    (40, [6, 30, 58, 86, 114, 142, 170], [[30,[[19,118],[6,119]]],[28,[[18,47],[31,48]]],[30,[[34,24],[34,25]]],[30,[[20,15],[61,16]]]]),
]
ZXING_VERSION_DECODE_INFO = [31892,34236,39577,42195,48118,51042,55367,58893,63784,68472,70749,76311,79154,84390,87683,92361,96236,102084,102881,110507,110734,117786,119615,126325,127568,133589,136944,141498,145311,150283,152622,158308,161089,167017]

ECL_ORDER = "LMQH"                      # ordinal 0..3 as the port numbers them
ECL_BITS = {"L": 1, "M": 0, "Q": 3, "H": 2}
ALNUM = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
MODE_NAMES = {0: "TERMINATOR", 1: "NUMERIC", 2: "ALPHANUMERIC", 3: "STRUCTURED_APPEND", 4: "BYTE",
              5: "FNC1_FIRST_POSITION", 7: "ECI", 8: "KANJI", 9: "FNC1_SECOND_POSITION", 13: "HANZI"}
COUNT_BITS = {"NUMERIC": (10, 12, 14), "ALPHANUMERIC": (9, 11, 13), "BYTE": (8, 16, 16),
              "KANJI": (8, 10, 12), "HANZI": (8, 10, 12)}
# ZXing CharacterSetECI values -> the charset name this port reports
ECI = {0: "Cp437", 2: "Cp437", 1: "ISO-8859-1", 3: "ISO-8859-1", 4: "ISO-8859-2", 5: "ISO-8859-3",
       6: "ISO-8859-4", 7: "ISO-8859-5", 8: "ISO-8859-6", 9: "ISO-8859-7", 10: "ISO-8859-8",
       11: "ISO-8859-9", 12: "ISO-8859-10", 13: "ISO-8859-11", 15: "ISO-8859-13", 16: "ISO-8859-14",
       17: "ISO-8859-15", 18: "ISO-8859-16", 20: "Shift_JIS", 21: "Cp1250", 22: "Cp1251", 23: "Cp1252",
       24: "Cp1256", 25: "UTF-16BE", 26: "UTF-8", 27: "US-ASCII", 170: "US-ASCII", 28: "Big5",
       29: "GB2312", 30: "EUC-KR"}
ECI_UNKNOWN = (14, 19, 31, 32, 100, 899)


# ------------------------------------------------------------ first principles --
def bch_version_word(v):
    """ISO 18004 annex D: 6 version bits + 12 BCH(18,6) bits, generator 0x1F25."""
    d = v << 12
    for i in range(5, -1, -1):
        if d & (1 << (i + 12)):
            d ^= 0x1F25 << i
    return (v << 12) | d


def bch_format_word(ecl, mask):
    """ISO 18004 annex C: 5 data bits + 10 BCH(15,5) bits (generator 0x537), XOR 0x5412."""
    data = (ECL_BITS[ecl] << 3) | mask
    d = data << 10
    for i in range(4, -1, -1):
        if d & (1 << (i + 10)):
            d ^= 0x537 << i
    return ((data << 10) | d) ^ 0x5412


def gf_tables():
    exp = [0] * 256
    log = [0] * 256
    x = 1
    for i in range(255):
        exp[i] = x
        log[x] = i
        x <<= 1
        if x & 0x100:
            x ^= 0x11D
    exp[255] = exp[0]
    return exp, log


def alignment_count(v):
    return 0 if v == 1 else v // 7 + 2


def iso_total_codewords(v):
    """(data modules) div 8 from the function-pattern geometry alone."""
    dim = 17 + 4 * v
    n = alignment_count(v)
    align = n * n - 3 if n else 0
    modules = dim * dim
    modules -= 3 * 64                          # finders + separators (8x8 each)
    modules -= 2 * (dim - 16)                  # timing patterns between the finders
    modules -= 25 * align                      # alignment patterns
    modules += 10 * (n - 2) if n > 2 else 0    # alignment patterns crossing the timing lines
    modules -= 31                              # format information x2 + the dark module
    if v >= 7:
        modules -= 36                          # version information x2
    return modules // 8


def mask_condition(ref, i, j):
    if ref == 0:
        return (i + j) % 2 == 0
    if ref == 1:
        return i % 2 == 0
    if ref == 2:
        return j % 3 == 0
    if ref == 3:
        return (i + j) % 3 == 0
    if ref == 4:
        return (i // 2 + j // 3) % 2 == 0
    if ref == 5:
        return (i * j) % 2 + (i * j) % 3 == 0
    if ref == 6:
        return ((i * j) % 2 + (i * j) % 3) % 2 == 0
    return ((i + j) % 2 + (i * j) % 3) % 2 == 0


# ------------------------------------------------------------------- runner --
class Checker(object):
    def __init__(self, model):
        self.model = model
        self.bad = []
        self.n = 0

    def call(self, name, *args):
        try:
            return self.model.call(name, *args)
        except lcs_model.LCThrow as e:
            return "THROW " + lcs_model.Model.to_text(e.value)

    def text(self, v):
        return lcs_model.Model.to_text(v) if not isinstance(v, dict) else v

    def eq(self, what, got, want):
        self.n += 1
        g = self.text(got)
        if isinstance(want, bool):
            ok = (got is want) or (not isinstance(g, dict) and str(g).lower() == ("true" if want else "false"))
        elif isinstance(want, int):
            ok = (not isinstance(g, dict)) and g != "" and lcs_model.Model.eq(got, want)
        else:
            ok = (g == want)
        if not ok:
            self.bad.append("%s: got %r, want %r" % (what, g, want))
        return ok

    def throws(self, what, got):
        self.n += 1
        if not (isinstance(got, str) and got.startswith("THROW ")):
            self.bad.append("%s: expected a throw, got %r" % (what, self.text(got)))


def load():
    srcs = []
    for m in MODULES:
        path = os.path.join(ROOT, "qr", m + ".lc")
        srcs.append(("qr/%s.lc" % m, lcs_model.strip_server_tags(open(path, encoding="utf-8").read())))
    model = lcs_model.Model(srcs)
    model.override("luminanceSource_decodeRawPlane", lambda *a: None)
    model.compile_all()
    return model


def check_versions(c):
    seen = set()
    for v, centers, ecs in ZXING_VERSIONS:
        seen.add(v)
        c.eq("v%d dimension" % v, c.call("ver_getDimensionForVersion", v), 17 + 4 * v)
        c.eq("v%d provisional version from its dimension" % v,
             c.call("ver_getProvisionalVersionForDimension", 17 + 4 * v), v)
        c.eq("v%d alignment centres" % v, c.call("ver_getAlignmentCenters", v), ",".join(str(x) for x in centers))
        c.eq("v%d alignment count (ISO)" % v, len(centers), alignment_count(v))
        total = 0
        for ordinal, (ecw, blocks) in enumerate(ecs):
            lvl = ECL_ORDER[ordinal]
            c.eq("v%d-%s ec codewords per block" % (v, lvl), c.call("ver_getEcCodewordsPerBlock", v, ordinal), ecw)
            c.eq("v%d-%s block layout" % (v, lvl), c.call("ver_getEcBlocks", v, ordinal),
                 "".join("%d,%d\n" % (cnt, data) for cnt, data in blocks))
            data_total = sum(cnt * data for cnt, data in blocks)
            c.eq("v%d-%s total data codewords" % (v, lvl), c.call("ver_getTotalDataCodewords", v, ordinal), data_total)
            t = sum(cnt * (data + ecw) for cnt, data in blocks)
            if total and t != total:
                c.bad.append("ZXING_VERSIONS v%d: EC levels disagree on the total codewords" % v)
            total = t
        c.eq("v%d total codewords (ZXing rows)" % v, c.call("ver_getTotalCodewords", v), total)
        c.eq("v%d total codewords (ISO module count)" % v, total, iso_total_codewords(v))
    c.eq("version table has 40 rows", len(seen), 40)
    c.throws("version 0 rejected", c.call("ver_getDimensionForVersion", 0))
    c.throws("version 41 rejected", c.call("ver_getDimensionForVersion", 41))
    # version information words
    for v in range(7, 41):
        word = bch_version_word(v)
        c.eq("v%d version word matches ZXing" % v, ZXING_VERSION_DECODE_INFO[v - 7], word)
        c.eq("v%d decodes from its exact word" % v, c.call("ver_decodeVersionInformation", word), v)
        for bit in range(18):
            c.eq("v%d decodes with bit %d flipped" % (v, bit),
                 c.call("ver_decodeVersionInformation", word ^ (1 << bit)), v)


def check_format(c):
    for ecl in "LMQH":
        for mask in range(8):
            word = bch_format_word(ecl, mask)
            res = c.call("fmt_decode", word, word)
            c.eq("format %s/%d ec level" % (ecl, mask), res["ecLevel"] if isinstance(res, dict) else res, ECL_ORDER.index(ecl))
            c.eq("format %s/%d data mask" % (ecl, mask), res["dataMask"] if isinstance(res, dict) else res, mask)
            for bit in range(15):
                res = c.call("fmt_decode", word ^ (1 << bit), word ^ (1 << bit))
                c.eq("format %s/%d bit %d flipped: ec level" % (ecl, mask, bit),
                     res["ecLevel"] if isinstance(res, dict) else res, ECL_ORDER.index(ecl))
                c.eq("format %s/%d bit %d flipped: data mask" % (ecl, mask, bit),
                     res["dataMask"] if isinstance(res, dict) else res, mask)
    c.eq("format: the 0x5412 mask constant", c.model.constants.get("kformatinfomaskqr"), 0x5412)
    c.eq("ecl_bits L", c.call("ecl_bits", 0), 1)
    c.eq("ecl_bits M", c.call("ecl_bits", 1), 0)
    c.eq("ecl_bits Q", c.call("ecl_bits", 2), 3)
    c.eq("ecl_bits H", c.call("ecl_bits", 3), 2)
    for ordinal, name in enumerate("LMQH"):
        c.eq("ecl_name %d" % ordinal, c.call("ecl_name", ordinal), name)
        c.eq("ecl_forBits %s" % name, c.call("ecl_forBits", ECL_BITS[name]), ordinal)


def check_gf(c):
    exp, log = gf_tables()
    for i in range(256):
        c.eq("gf_exp(%d)" % i, c.call("gf_exp", i), exp[i])
    for i in range(1, 256):
        c.eq("gf_log(%d)" % i, c.call("gf_log", i), log[i])
    rnd = random.Random(2026)
    for _ in range(200):
        a, b = rnd.randrange(256), rnd.randrange(256)
        want = 0 if a == 0 or b == 0 else exp[(log[a] + log[b]) % 255]
        c.eq("gf_multiply(%d,%d)" % (a, b), c.call("gf_multiply", a, b), want)
    for a in range(1, 256):
        inv = c.call("gf_inverse", a)
        c.eq("gf_inverse(%d) * %d" % (a, a), c.call("gf_multiply", a, inv), 1)
    c.throws("gf_log(0) rejected", c.call("gf_log", 0))
    c.throws("gf_inverse(0) rejected", c.call("gf_inverse", 0))
    c.eq("gf size", c.call("gf_getSize"), 256)
    c.eq("gf generator base", c.call("gf_getGeneratorBase"), 0)


def check_modes(c):
    for bits, name in MODE_NAMES.items():
        c.eq("mode bits %d" % bits, c.call("mode_forBits", bits), name)
    for bits in (6, 10, 11, 12, 14, 15):
        c.throws("mode bits %d rejected" % bits, c.call("mode_forBits", bits))
    for v in range(1, 41):
        idx = 0 if v <= 9 else (1 if v <= 26 else 2)
        for name, widths in COUNT_BITS.items():
            c.eq("count bits %s v%d" % (name, v), c.call("mode_charCountBits", name, v), widths[idx])
        for name in ("TERMINATOR", "ECI", "FNC1_FIRST_POSITION", "FNC1_SECOND_POSITION", "STRUCTURED_APPEND"):
            c.eq("count bits %s v%d" % (name, v), c.call("mode_charCountBits", name, v), 0)


def check_alnum_masks_eci(c):
    for i, ch in enumerate(ALNUM):
        c.eq("alphanumeric[%d]" % i, c.call("dbsp_alnumChar", i), ch)
    c.throws("alphanumeric[45] rejected", c.call("dbsp_alnumChar", 45))
    for ref in range(8):
        for i in range(12):
            for j in range(12):
                c.eq("mask %d (%d,%d)" % (ref, i, j), c.call("dataMask_isMasked", ref, i, j), mask_condition(ref, i, j))
    for value, name in ECI.items():
        c.eq("eci %d" % value, c.call("eci_charsetName", value), name)
    for value in ECI_UNKNOWN:
        c.eq("eci %d unknown -> empty" % value, c.call("eci_charsetName", value), "")


def main():
    try:
        model = load()
    except lcs_model.ModelError as e:
        print("MODEL ERROR while loading/compiling:\n%s" % e)
        return 2
    c = Checker(model)
    for fn in (check_versions, check_format, check_gf, check_modes, check_alnum_masks_eci):
        try:
            fn(c)
        except lcs_model.ModelError as e:
            c.bad.append("%s: MODEL ERROR %s" % (fn.__name__, e))
    if c.bad:
        print("verify_tables: %d of %d checks FAILED" % (len(c.bad), c.n))
        for b in c.bad[:60]:
            print("  - " + b)
        if len(c.bad) > 60:
            print("  ... and %d more" % (len(c.bad) - 60))
        return 1
    print("verify_tables: all %d checks passed - version table (ZXing rows + ISO module counts), "
          "version/format BCH words with 1-bit errors, GF(256), modes, alphanumeric, data masks, ECI" % c.n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
