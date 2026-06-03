# xtQRdecoder — a pure xTalk QR decoder

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![CI](https://github.com/SethMorrowSoftware/xtQRdecoder/actions/workflows/ci.yml/badge.svg)](https://github.com/SethMorrowSoftware/xtQRdecoder/actions/workflows/ci.yml)
[![Engine: OpenXTalk / xTalk 9.6.3+](https://img.shields.io/badge/engine-OpenXTalk%20%2F%20xTalk%209.6.3%2B-2a9d8f.svg)](https://openxtalk.org/)
[![Tests: 399 passing](https://img.shields.io/badge/tests-399%20passing-brightgreen.svg)](qr/qr_tester.lc)
[![Pure xTalk](https://img.shields.io/badge/pure-xTalk-orange.svg)](#)

**xtQRdecoder reads QR codes from raster images, entirely in xTalk — no
externals, no companion app, no GUI.** It runs on **OpenXTalk** and every
compatible xTalk engine (9.6.3+ generation and later) — **desktop, mobile, and
headless server** alike — from a single file you load with `start using`.

It is a line-for-line port of
[`khanamiryan/php-qrcode-detector-decoder`](https://github.com/khanamiryan/php-qrcode-detector-decoder),
which is itself a hand-port of [**ZXing**](https://github.com/zxing/zxing)
("Zebra Crossing"), the canonical open-source barcode library. The algorithms,
data tables, and module structure are derived from ZXing; the PHP source is the
line-level authority for behaviour.

> **Decoder only.** xtQRdecoder *reads* existing QR codes. It does **not**
> generate/encode them.

---

## Table of contents

- [Why xtQRdecoder](#why-xtqrdecoder)
- [Feature matrix](#feature-matrix)
- [Requirements](#requirements)
- [Install & use](#install--use)
- [Quick start](#quick-start)
- [API reference](#api-reference)
  - [`qrDecodeFromData`](#qrdecodefromdata)
  - [`qrDecodeFromFile`](#qrdecodefromfile)
  - [`qrDecodeResult`](#qrdecoderesult)
  - [`qrDecodeResultRobust`](#qrdecoderesultrobust)
  - [The result array](#the-result-array)
  - [Decode hints](#decode-hints)
- [How it works (the pipeline)](#how-it-works-the-pipeline)
- [Bundled tools & pages](#bundled-tools--pages)
- [Project layout](#project-layout)
- [Troubleshooting](#troubleshooting)
- [Performance notes](#performance-notes)
- [Limitations](#limitations)
- [Contributing](#contributing)
- [License & attribution](#license--attribution)

---

## Why xtQRdecoder

QR decoding normally means embedding a native external, calling a cloud API, or
shelling out to a separate binary (zbar, a ZXing build). xtQRdecoder needs none
of those — it is **self-contained xTalk** that runs anywhere an xTalk engine does
(OpenXTalk and other variants), so the same code decodes a photo in your desktop
app, your mobile app, or a headless server page.

- **Cross-platform from one file** — load `lib/xtQRdecoder.livecodescript` with
  `start using` on **OpenXTalk**, an xTalk IDE/standalone, mobile, or server.
  No build step, no externals, no widgets.
- **Faithful ZXing port** — detection is rotation/perspective tolerant; decoding
  covers QR **versions 1–40** and **all four error-correction levels (L/M/Q/H)**.
- **Robust on real photos** — multi-strategy decoding (two binarizers × two
  scales) handles glare, blur, and dense codes from phone cameras.
- **Verified on a real engine** — **399 unit tests** and **5 golden photographic
  fixtures** pass on a stock xTalk engine (a 9.6.11-class community build).
- **Strict failure contract** — the public API never throws; failures surface as
  a string in the result's `["error"]` key.
- **Headless-server friendly** — runs unchanged on a stock xTalk server or a
  shared cPanel host, where externals and cloud APIs aren't an option.

---

## Feature matrix

| Capability | Status |
|---|---|
| QR versions 1–40 | ✅ |
| Error-correction levels L, M, Q, H | ✅ |
| Reed–Solomon error correction over GF(256) | ✅ |
| Rotation / perspective tolerance (skewed photos) | ✅ |
| Mirror-image symbols (transpose retry) | ✅ |
| Numeric mode | ✅ |
| Alphanumeric mode | ✅ |
| Byte mode — ASCII / ISO-8859-1 / UTF-8 | ✅ |
| ECI character-set switching | ✅ |
| FNC1 (first/second position) | ✅ |
| Structured Append (segment metadata) | ✅ |
| `PURE_BARCODE` fast path (clean, bordered images) | ✅ |
| `BINARY_MODE` (return raw bytes verbatim) | ✅ |
| Image formats: PNG, GIF, BMP (always) | ✅ |
| Image format: JPEG | ⚠️ depends on your engine build — [see below](#jpeg-isnt-decoding) |
| Kanji (Shift-JIS) / Hanzi (GB2312) modes | ❌ documented limitation — [see Limitations](#limitations) |
| QR **encoding** / generation | ❌ out of scope (decoder only) |

---

## Requirements

- **An xTalk engine:** **OpenXTalk** (recommended — the open-source xTalk
  environment), or any other compatible **9.6.3+ xTalk engine** or variant.
  Desktop, mobile, and headless **server** builds all work — the
  code is pure xTalk with no version-specific or proprietary APIs.
- The engine's **image object** + `the imageData` for the pixel path. On a normal
  desktop/mobile build this works and exposes 4 bytes/pixel in `0,R,G,B` order.
  Whether a *headless server* build exposes it is engine-specific, so it's
  verifiable with a standalone probe (see
  [`qr_imageprobe.lc`](#bundled-tools--pages)).
- **No GUI, no externals, no compiled widget extensions** are required at runtime.

---

## Install & use

There is nothing to compile or install. Choose the form that fits your target.

### The script-only library (desktop / mobile / OpenXTalk / server) — recommended

`lib/xtQRdecoder.livecodescript` is a single **script-only stack** containing the
whole decoder. It's xTalk's standard, source-control-friendly library format:
plain text, loadable by any xTalk engine — OpenXTalk, an xTalk IDE, standalone,
mobile, or server — with `start using`.

1. Copy `lib/xtQRdecoder.livecodescript` into your project (next to your stack is
   fine).
2. Load it once, early in your app (e.g. `preOpenStack`):

   ```xtalk
   start using stack (the folder of me & "/xtQRdecoder.livecodescript")
   put qrDecodeResultRobust(url ("binfile:" & tImagePath), "TRY_HARDER") into tRes
   if tRes["error"] is empty then answer tRes["text"]
   ```

Once `start using` succeeds, **all the public functions below are in scope**
anywhere in your app. See [`lib/README.md`](lib/README.md) and
[`lib/examples/scanButton.livecodescript`](lib/examples/scanButton.livecodescript)
for ready-to-paste desktop/mobile button code.

### xTalk server alternative: the `qr/` module folder

For a server deployment you can instead copy the raw module folder:

1. Upload the whole **`qr/`** folder to your document root, e.g. `public_html/qr/`.
2. (Optional) open the bundled pages in a browser to confirm your engine:
   - `https://yoursite/qr/qr_imageprobe.lc` — can this engine decode images?
   - `https://yoursite/qr/qr_tester.lc` — the 399 unit tests.
   - `https://yoursite/qr/qr_golden.lc` — the golden photographic fixtures.
   - `https://yoursite/qr/qr_demo.lc` — the interactive scanner.
3. To use the library from your own `.lc` page, `include` the modules in
   dependency order (see [Quick start](#quick-start)).

> **Path note.** Some cPanel builds leave `the defaultFolder` pointing at the
> engine directory and don't populate `$_SERVER["SCRIPT_FILENAME"]`, so relative
> `include`s can fail. The bundled pages resolve their own directory from several
> `$_SERVER` candidates; when you `include` from your own page, prefer **absolute
> paths**.

---

## Quick start

### Desktop / mobile / OpenXTalk — the script-only stack

```xtalk
-- Load the library once (e.g. in preOpenStack), then call it anywhere.
start using stack (the folder of me & "/xtQRdecoder.livecodescript")

-- 1) Simplest: image bytes in, decoded text out (empty string on any failure).
put qrDecodeFromData(url ("binfile:/path/to/qr.png")) into tText

-- 2) From a file path, with a hint (recommended for photographs).
put qrDecodeFromFile("/path/to/photo.png", "TRY_HARDER") into tText

-- 3) Rich result + robust multi-strategy decode — best for real-world photos.
put qrDecodeResultRobust(url ("binfile:/path/to/photo.jpg"), "TRY_HARDER", 1200) into tRes
if tRes["error"] is empty then
   put tRes["text"]      -- the decoded string
   put tRes["version"]   -- QR version, 1..40
   put tRes["ecLevel"]   -- "L" / "M" / "Q" / "H"
   put tRes["strategy"]  -- which binarizer won: "hybrid" / "global"
else
   put tRes["error"]     -- e.g. "NotFound: could not find 3 finder patterns"
end if
```

### xTalk server — include the modules directly

```xtalk
<?lc
-- Include the decode stack in dependency order. The simplest reliable way to get
-- the exact list + order is to copy the 30-line include block from qr_demo.lc.
include "/home/you/public_html/qr/qrCompat.lc"
-- ... (genericGF, genericGFPoly, reedSolomonDecoder, bitArray, bitMatrix,
--      bitSource, luminanceSource, globalHistogramBinarizer, hybridBinarizer,
--      binaryBitmap, errorCorrectionLevel, mode, dataMask, formatInformation,
--      version, characterSetECI, dataBlock, decodedBitStreamParser,
--      bitMatrixParser, decoder, mathUtils, resultPoint, perspectiveTransform,
--      gridSampler, finderPatternFinder, alignmentPatternFinder, detector,
--      qrCodeReader) ...
include "/home/you/public_html/qr/qrReader.lc"

put qrDecodeResultRobust(url ("binfile:" & $_FILES["qr"]["filename"]), "TRY_HARDER") into tRes
put tRes["text"]
?>
```

(On a server you can equally `start using` the single combined stack — it's just
a more convenient single dependency.)

---

## API reference

The public surface lives in **`qr/qrReader.lc`** (and the combined stack). All
four entry points are xTalk **functions** (call with parentheses). None of them
throw — internal `NotFound` / `Format` / `Checksum` errors are caught and reported
(empty result, or the `["error"]` key).

### `qrDecodeFromData`

```xtalk
qrDecodeFromData(pImageData [, pHints])  ->  text (or empty)
```

Decode raw **image bytes**. Returns the decoded **text** on success, or **empty**
on any failure.

- `pImageData` — the image file's bytes (PNG/GIF/BMP, and JPEG where the engine
  supports it). Read a file with `url ("binfile:" & tPath)`.
- `pHints` *(optional)* — see [Decode hints](#decode-hints).
- With the `BINARY_MODE` hint, returns the raw decoded **byte string** verbatim
  (no charset decoding) instead of text.
- **Decodes at full resolution** (no downsampling). For large phone photos prefer
  `qrDecodeResultRobust`, which downsamples and retries.

### `qrDecodeFromFile`

```xtalk
qrDecodeFromFile(pFilePath [, pHints])  ->  text (or empty)
```

Convenience wrapper: reads the file at `pFilePath` (`binfile:`) and calls
`qrDecodeFromData`. Same return contract.

### `qrDecodeResult`

```xtalk
qrDecodeResult(pImageData [, pHints])  ->  result array
```

Like `qrDecodeFromData` but returns the **full result array** (see below) instead
of just text — giving you the version, EC level, data mask, raw byte payload, and
detected corner points. Never throws; on failure the array has `["error"]` set.
Decodes at full resolution.

### `qrDecodeResultRobust`

```xtalk
qrDecodeResultRobust(pImageData [, pHints [, pMaxDim]])  ->  result array
```

**The recommended entry point for real-world photographs.** It decodes the image
to a raw pixel plane **once** (the costly step), then tries several
`(binarizer, scale)` strategies cheapest-first and returns the first that
decodes:

| Order | Binarizer | Max dimension |
|---|---|---|
| 1 | hybrid | `pMaxDim` (default **1200**) |
| 2 | global | `pMaxDim` |
| 3 | hybrid | ~1.33 × `pMaxDim` (~1600) |
| 4 | global | ~1.33 × `pMaxDim` |

Why this helps where a single pass fails:

- **Hybrid vs Global binarizer** catch different failure modes — hybrid's local
  8×8 threshold handles uneven lighting and glare; the global histogram is a
  better bet for low-contrast or evenly-lit frames.
- **A higher-resolution retry** recovers dense (v4+) codes whose thin modules
  alias away under the aggressive fast-pass downsample.

- `pMaxDim` *(optional)* — the base (fast-pass) cap on the longer side, in pixels.
  Omit for **1200**. Larger = more detail but slower interpreted pixel loops.
- On success the result also carries `["strategy"]`, `["procW"]`, `["procH"]`
  describing the winning attempt; on failure they describe the last one tried.

### The result array

`qrDecodeResult` / `qrDecodeResultRobust` return an xTalk array with these keys:

| Key | Type | Meaning |
|---|---|---|
| `["text"]` | string | Decoded text (charset-decoded). Empty on failure. |
| `["bytes"]` | string | Raw decoded byte payload (pre-charset). Useful with `BINARY_MODE`. |
| `["error"]` | string | Empty on success; otherwise a tagged message (`"NotFound: …"`, `"Format: …"`, `"Checksum: …"`). **Check this first.** |
| `["version"]` | 1–40 | QR symbol version. |
| `["ecLevel"]` | `L`/`M`/`Q`/`H` | Error-correction level. |
| `["mask"]` | 0–7 | Data-mask pattern. |
| `["points"]` | array | Detected reference points (`0`=bottom-left, `1`=top-left, `2`=top-right, `3`=alignment if present). Each is `{["x"],["y"],…}` in image pixels. |
| `["mirrored"]` | `true` | Present only if the symbol decoded on the mirror/transpose retry. |
| `["strategy"]` | `hybrid`/`global` | *(robust only)* binarizer that produced this result. |
| `["procW"]`, `["procH"]` | px | *(robust only)* dimensions the winning attempt processed at. |

### Decode hints

Hints may be passed as an **xTalk array** (`tHints["TRY_HARDER"] = true`) or as
a **comma-separated string** of `"KEY"` / `"KEY=VALUE"` tokens
(`"TRY_HARDER,NR_ALLOW_SKIP_ROWS=0"`).

| Hint | Value | Effect |
|---|---|---|
| `TRY_HARDER` | flag | Scan more thoroughly (denser row stride). **Recommended for photographs.** |
| `BINARY_MODE` | flag | Return the raw byte payload verbatim; skip charset decoding. For binary QR payloads. |
| `PURE_BARCODE` | flag | Fast path for a clean, unrotated, bordered "screenshot" QR — skips full detection. |
| `NR_ALLOW_SKIP_ROWS` | int | Override the finder's row-skip heuristic. `0` forces every row to be scanned (slowest, most thorough). |
| `ALLOWED_DEVIATION` | float | Module-size deviation tolerance when selecting finder candidates (default `0.05`). |
| `MAX_VARIANCE` | float | Tolerance for the 1:1:3:1:1 finder-pattern ratio test (default `0.5`). |

---

## How it works (the pipeline)

The decode is a linear pipeline; each stage is a module group (see
[`docs/spec.md`](docs/spec.md) §3 for the authoritative description).

```
image bytes (PNG / JPEG / GIF / BMP)
   │
   ▼
[A] Luminance acquisition        luminanceSource.lc   →  flat 0..255 grey plane (row-major)
   │                             (decode via the engine image object + the imageData)
   ▼
[B] Binarization                 hybridBinarizer.lc   →  BitMatrix (1 bit/pixel, true = black)
   │  default: Hybrid (8×8 local adaptive); falls back to Global histogram < 40px
   ▼
[C] Detection                    detector.lc
   │   • finderPatternFinder  → the 3 corner finder squares
   │   • module size + dimension → provisional Version
   │   • alignmentPatternFinder (v2+) → 4th reference point
   │   • perspectiveTransform + gridSampler → a sampled square BitMatrix
   ▼
[D] Bit-matrix parsing           bitMatrixParser.lc
   │   • format info (EC level + data mask), with mirror fallback
   │   • version (v7+) from version-info blocks
   │   • un-mask, then read codewords in zig-zag order
   ▼
[E] Error correction             dataBlock.lc (de-interleave) + reedSolomonDecoder.lc over GF(256)
   ▼
[F] Bitstream decode             decodedBitStreamParser.lc
   │   • walk mode segments (numeric / alphanumeric / byte / ECI / FNC1 / …)
   │   • apply character set (ASCII / ISO-8859-1 / UTF-8)
   ▼
result { text, bytes, version, ecLevel, mask, points, … }
```

For the internal architecture and conventions, see
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Bundled tools & pages

Open these in a browser on your xTalk server (no CLI needed):

| Page | What it does |
|---|---|
| **`qr/qr_demo.lc`** | 📷 **Interactive scanner.** A polished single-page web app: drag-and-drop, click-to-browse, paste-from-clipboard, live webcam capture, or an image URL. Decodes asynchronously (no page reload, live progress) and **recognises the content** — links, Wi-Fi, contacts, geo, email/phone/SMS, calendar events — with one-tap actions, copy, and a recent-scan history. Falls back to a plain server-rendered form when JavaScript is off. Needs its two sibling assets `qr_demo.css` / `qr_demo.js`. Uses `qrDecodeResultRobust`. |
| `qr/qr_tester.lc` | The **399 unit tests** as a per-module pass/fail dashboard, plus an engine-environment panel and an interactive helper evaluator. |
| `qr/qr_golden.lc` | The **5 golden photographic fixtures** decoded through the public API with the spec hints (acceptance suite). |
| `qr/qr_decodeprobe.lc` | A minimal **self-contained real-image decode** (embedded PNG → `"HI"`) through the full public pipeline. |
| `qr/qr_imageprobe.lc` | Standalone **capability probe**: does this headless engine decode images and expose `the imageData` at 4 bytes/pixel in `0,R,G,B` order? Needs no other files. |

---

## Project layout

```
xtQRdecoder/
├─ qr/                          the library source (pure xTalk)
│  ├─ qrCompat.lc               integer/bitwise compat (u32, shl, uShr, aShr, …)
│  ├─ …                         GF(256), Reed–Solomon, bit structures, luminance,
│  │                            binarizers, detection geometry, bitstream parse
│  ├─ qrReader.lc               ★ PUBLIC API (qrDecodeFromData / …Result / …Robust)
│  ├─ suite_*.lc                17 unit-test suites (399 assertions)
│  ├─ qr_demo.lc                interactive scanner page (server)
│  ├─ qr_demo.css               scanner styling (sibling asset)
│  ├─ qr_demo.js                scanner client: tabs, drag/drop, camera,
│  │                            async decode, smart content actions, history
│  ├─ qr_tester.lc              unit-test console
│  ├─ qr_golden.lc              golden-fixture acceptance page
│  ├─ qr_decodeprobe.lc         self-contained real-image decode
│  ├─ qr_imageprobe.lc          image/imageData capability probe
│  └─ fixtures/                 5 golden test images (PNG)
├─ lib/
│  ├─ xtQRdecoder.livecodescript  ★ the whole library combined into one
│  │                              script-only stack (desktop / mobile / server)
│  ├─ examples/scanButton.livecodescript   a ready-to-paste "Scan QR" button
│  ├─ examples/demoStack/        a 2-button demo stack (Decode QR + Verbose Decode)
│  └─ README.md                 library quick-start
├─ docs/
│  ├─ ARCHITECTURE.md           architecture & contributor guide
│  ├─ CONTRIBUTING.md           how to contribute
│  └─ spec.md                   authoritative port specification
├─ CHANGELOG.md                 release history
├─ LICENSE                      Apache-2.0
└─ NOTICE                       ZXing / khanamiryan attribution
```

The `qr/*.lc` modules are the single source of truth;
`lib/xtQRdecoder.livecodescript` is generated from them. Internal architecture and
conventions: see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Troubleshooting

### "No QR code found" on a photo

In order of likelihood:

1. **Use `qrDecodeResultRobust` with `TRY_HARDER`.** The plain
   `qrDecodeFromData` does a single binarizer pass at full resolution; the robust
   entry tries two binarizers at two scales, which is dramatically more reliable
   on phone photos (glare, blur, dense codes). The interactive demo already does
   this.
2. **Glare / uneven lighting** (e.g. a laminated card). The global binarizer
   sometimes succeeds where hybrid fails (and vice-versa); the robust path tries
   both.
3. **Dense code, downsampled too far.** Raise `pMaxDim` (e.g. 1600–2000) so thin
   modules survive.
4. **Tight quiet zone** (QR crowded by text/border). Try to include a little more
   white margin around the code.

### JPEG isn't decoding

Phone photos are usually **JPEG**, and some *headless* xTalk server builds lack
a JPEG import codec. When that happens the engine decodes the image to **0×0 with
empty pixel data** — which would otherwise look like "no QR". xtQRdecoder detects
this and reports a precise error:

> `NotFound: image did not decode (0 x 0) -- unsupported format? this engine
> build may lack a JPEG codec; try a PNG`

If you see this: re-save/convert the image to **PNG** (PNG/GIF/BMP always decode),
or add a server-side conversion step. You can confirm your engine's image
capabilities with `qr/qr_imageprobe.lc`.

### Kanji / Hanzi text comes back as an error

Shift-JIS and GB2312 are a documented limitation — see [Limitations](#limitations).

### A library file "isn't found" / a page renders half-broken

Usually a single module failed to parse and the failure cascaded. Re-upload the
whole `qr/` folder (a stale partial upload is a common cause). Contributors: the
xTalk parser rules and how to read a misleading parse error are in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) §4.

---

## Performance notes

The cost centre is the interpreted **per-pixel loops** (luminance conversion +
binarization), so throughput scales with processed pixel count.

- `qrDecodeResultRobust` **decodes the source image only once** and reuses the raw
  plane across strategies, so the expensive image decode isn't repeated.
- Its first strategy is the cheapest (hybrid @ ≤1200px); easy images succeed
  immediately and never pay for the fallbacks.
- The `pMaxDim` knob trades detail for speed. 1200 is a good default; lower it for
  speed, raise it for very dense codes.
- For a known-clean, bordered, unrotated image, the `PURE_BARCODE` hint skips full
  detection entirely.

### Large camera photos

A full-resolution phone photo (12 MP ≈ 48 MB of pixels) is downsampled in
interpreted xTalk before decoding, which can take a noticeable moment. To keep it
responsive:

- Pass a smaller `pMaxDim` (e.g. `qrDecodeResultRobust(bytes, "TRY_HARDER", 1000)`
  or `800`) — the single biggest lever.
- On mobile, decode the **saved JPEG/PNG file**; most camera APIs let you request
  a smaller capture.
- For best throughput you can resize the image with the engine's own image object
  in your app code *before* handing the bytes to xtQRdecoder (desktop/mobile
  engines resample in compiled code).

---

## Limitations

- **Decoder only** — xtQRdecoder does not generate/encode QR codes.
- **Kanji (Shift-JIS) / Hanzi (GB2312)** modes are **not decoded**.
  `decodedBitStreamParser` raises a documented "not supported" error for them,
  because xTalk's `textDecode` has no Shift-JIS / GB2312 codec. Everything else
  — **Numeric, Alphanumeric, and Byte (ASCII / ISO-8859-1 / UTF-8)**, i.e. the
  overwhelming majority of real QR codes including all URLs — is fully supported.
  (See [`docs/spec.md`](docs/spec.md) §8.7 for how to add them later.)
- **JPEG decode depends on your engine build** — see
  [Troubleshooting](#jpeg-isnt-decoding).

---

## Contributing

Contributions are welcome. The architecture, the xTalk Script conventions, the
build, and the testing workflow live in the contributor docs:

- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — the contribution workflow.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — architecture & conventions.
- [`docs/spec.md`](docs/spec.md) — the authoritative algorithm/data specification.

---

## License & attribution

Licensed under **Apache-2.0** — see [`LICENSE`](LICENSE).

xtQRdecoder is a port of **ZXing** (Apache-2.0) via
[`khanamiryan/php-qrcode-detector-decoder`](https://github.com/khanamiryan/php-qrcode-detector-decoder)
(Apache-2.0 / MIT). Their copyright and attribution are retained in
[`NOTICE`](NOTICE) and in the per-file SPDX headers. The golden test fixtures in
`qr/fixtures/` originate from the upstream test suite.

Pure, original xTalk with no proprietary dependencies — fully usable on
**OpenXTalk** and **other open-source xTalk engines**. See
[`CHANGELOG.md`](CHANGELOG.md) for release history.
