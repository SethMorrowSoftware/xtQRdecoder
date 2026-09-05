# xtQRdecoder — a pure xTalk QR decoder

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![CI](https://github.com/SethMorrowSoftware/xtQRdecoder/actions/workflows/ci.yml/badge.svg)](https://github.com/SethMorrowSoftware/xtQRdecoder/actions/workflows/ci.yml)
[![Engine: OpenXTalk / xTalk 9.6.3+](https://img.shields.io/badge/engine-OpenXTalk%20%2F%20xTalk%209.6.3%2B-2a9d8f.svg)](https://openxtalk.org/)
[![Tests: 497 model-passed, 399 engine-passed](https://img.shields.io/badge/tests-497%20model--passed%20%7C%20399%20engine--passed-brightgreen.svg)](docs/VERIFICATION.md)
[![Pure xTalk](https://img.shields.io/badge/pure-xTalk-orange.svg)](#)

**xtQRdecoder reads QR codes from raster images, entirely in xTalk — no
externals, no companion app, no GUI.** It is written for **OpenXTalk** and every
compatible xTalk engine (9.6.3+ generation and later) — **desktop, mobile, and
headless server** alike — from a single file you load with `start using`. It has
been run on a headless xTalk server; the desktop and mobile legs are verified
statically and await an engine pass ([status](#verification-status)).

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
- [Verification status](#verification-status)
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
- **Robust on real photos** — multi-strategy decoding (two binarizers over a
  resolution ladder, plus mirrored and inverted retries) handles glare, blur,
  and dense codes from phone cameras.
- **Verified, and honest about how** — **399 unit tests** and **5 golden
  photographic fixtures** passed on a stock xTalk server engine (a 9.6.11-class
  community build) at the 0.1.0 release; everything since (497 assertions, 49
  synthetic images, 5,060 table checks) is proven under a headless execution
  model and mutation-tested static gates on every push, and is labelled
  *needs an OXT pass* until an engine run says otherwise. See
  [`docs/VERIFICATION.md`](docs/VERIFICATION.md).
- **Tested against an independent encoder** — a committed corpus of 46
  synthetic images (versions 1–40, every EC level and mask, rotations, mirrored
  and inverted symbols, lighting, blur, noise, tight quiet zones) decodes as
  expected, and every decoder table is regenerated from ISO/IEC 18004 and
  ZXing's own rows.
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
| Inverted symbols (white on black) with the `ALSO_INVERTED` hint | ✅ |
| Numeric mode | ✅ |
| Alphanumeric mode | ✅ |
| Byte mode — ASCII / ISO-8859-1 / UTF-8 (charset guessed as ZXing does when there is no ECI) | ✅ |
| UTF-16 byte segments with a byte-order mark | ✅ |
| ECI character-set switching (an unknown ECI fails closed with `Format:`) | ✅ |
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
  The code is pure xTalk with no version-specific or proprietary APIs, so
  desktop, mobile, and headless **server** builds are all targets; the server
  leg has been observed on an engine, the others are verified statically
  ([status](#verification-status)).
- The engine's **image object** + `the imageData` for the pixel path. On a normal
  desktop/mobile build this works and exposes 4 bytes/pixel in `0,R,G,B` order.
  Whether a *headless server* build exposes it is engine-specific, so it's
  verifiable with a standalone probe (see
  [`qr_imageprobe.lc`](#bundled-tools--pages)).
- **No GUI, no externals, no compiled widget extensions** are required at runtime.

---

## Install & use

There is nothing to compile or install. Choose the form that fits your target.

### Try it first: the showcase stack

[`lib/examples/xtQRdecoder-demo.livecodescript`](lib/examples/xtQRdecoder-demo.livecodescript)
is a one-file demo laid out the way the xTalk Suite's demos are: paste it into
a new stack's script, close and reopen the stack, and it builds a tabbed window
with the whole library carried inside it - load a file, paste, or drop an image
and decode it with every hint and every result key on screen; walk the
pipeline stage by stage; decode the seven embedded samples for a PASS/FAIL
record of your engine. [`lib/examples/README.md`](lib/examples/README.md) has
the five steps.

### The script-only library (desktop / mobile / OpenXTalk / server) — recommended

`lib/xtQRdecoder.livecodescript` is a single **script-only stack** containing the
whole decoder. It's xTalk's standard, source-control-friendly library format:
plain text, loadable by any xTalk engine — OpenXTalk, an xTalk IDE, standalone,
mobile, or server — with `start using`.

1. Copy `lib/xtQRdecoder.livecodescript` into your project (next to your stack is
   fine).
2. Load it once, early in your app (e.g. `preOpenStack`). There is no `folder`
   property of a stack, so derive the folder from the stack's own file path:

   ```xtalk
   on preOpenStack
      local tDir
      put the effective filename of this stack into tDir
      set the itemDelimiter to "/"
      delete the last item of tDir            -- the folder holding this stack
      start using stack (tDir & "/xtQRdecoder.livecodescript")
   end preOpenStack
   ```

   and then, anywhere:

   ```xtalk
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
   - `https://yoursite/qr/qr_tester.lc` — the 497 unit tests (19 panels).
   - `https://yoursite/qr/qr_golden.lc` — the golden photographic fixtures.
   - `https://yoursite/qr/qr_synthetic.lc` — the 49-row synthetic corpus.
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
-- Load the library once (in preOpenStack; see "Install & use" for the
-- effective-filename idiom), then call it anywhere.

-- 1) Simplest: image bytes in, decoded text out (empty string on any failure).
put qrDecodeFromData(url ("binfile:/path/to/qr.png")) into tText

-- 2) From a file path, with a hint (recommended for photographs).
put qrDecodeFromFile("/path/to/photo.png", "TRY_HARDER") into tText

-- 3) Rich result + robust multi-strategy decode — best for real-world photos.
put qrDecodeResultRobust(url ("binfile:/path/to/photo.jpg"), "TRY_HARDER,ALSO_INVERTED", 1200) into tRes
if tRes["error"] is empty then
   put tRes["text"]      -- the decoded string
   put tRes["version"]   -- QR version, 1..40
   put tRes["ecLevel"]   -- "L" / "M" / "Q" / "H"
   put tRes["strategy"]  -- which binarizer won: "hybrid" / "global"
   put tRes["charset"]   -- e.g. "UTF-8" (byte-mode payloads only)
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
(empty result, or the `["error"]` key). `qrLibraryVersion()` returns the library
version string (`"0.2.0"`).

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
to a raw pixel plane **once** (the costly step), then walks a resolution
**ladder** of `(downsample step, binarizer)` rungs cheapest-first and returns the
first that decodes:

| Order | Binarizer | Resolution |
|---|---|---|
| 1 | hybrid | the integer downsample step that fits the longer side under `pMaxDim` (default **1200**) |
| 2 | global | the same greyscale plane (built once, shared) |
| 3 | hybrid | one step finer: the step for ~1.33 × `pMaxDim`, or the base step minus one — **only when that adds resolution** |
| 4 | global | the same finer plane |

An image that already fits under `pMaxDim` at full resolution has a single rung
(two attempts); the old fixed four-rung list repeated identical work on every
failure.

Why this helps where a single pass fails:

- **Hybrid vs Global binarizer** catch different failure modes — hybrid's local
  8×8 threshold handles uneven lighting and glare; the global histogram is a
  better bet for low-contrast or evenly-lit frames.
- **A higher-resolution retry** recovers dense (v4+) codes whose thin modules
  alias away under the aggressive fast-pass downsample.

- `pMaxDim` *(optional)* — the base (fast-pass) cap on the longer side, in pixels.
  Omit for **1200**. Larger = more detail but slower interpreted pixel loops.
- On success the result also carries `["strategy"]`, `["step"]`, `["procW"]`,
  `["procH"]` describing the winning attempt, and `["attempts"]`, a 0-based list
  of every rung tried (`{strategy, step, procW, procH, error}`). On total
  failure `["error"]` is the **first** rung's error (the most specific one) and
  `["attempts"]` tells the rest.

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
| `["charset"]` | string | *(byte-mode payloads)* the charset the bytes were decoded with: from the ECI, or guessed as ZXing does (`UTF-8`, `ISO-8859-1`, `UTF-16`). |
| `["fnc1"]` | `first`/`second` | Present when the symbol carries an FNC1 indicator (GS1 / AIM). In FNC1 mode a lone `%` in alphanumeric data is delivered as the GS separator (codepoint 29) and `%%` as `%`, as ZXing does. |
| `["symbologyModifier"]` | 1–6 | ZXing's symbology modifier: 1 plain, 3/5 FNC1 first/second, +1 when an ECI was present. |
| `["structuredAppendSeq"]`, `["structuredAppendParity"]` | int | Present when the symbol is part of a structured-append set. |
| `["mirrored"]` | `true` | Present only if the symbol decoded on the mirror/transpose retry. |
| `["inverted"]` | `true` | Present only if the symbol decoded on the `ALSO_INVERTED` retry (white modules on black). |
| `["strategy"]` | `hybrid`/`global` | *(robust only)* binarizer that produced this result. |
| `["step"]`, `["procW"]`, `["procH"]` | int, px | *(robust only)* the downsample step and dimensions the winning attempt processed at. |
| `["attempts"]` | array | *(robust only)* every rung tried, in order: `{strategy, step, procW, procH, error}`. |

### Decode hints

Hints may be passed as an **xTalk array** (`tHints["TRY_HARDER"] = true`) or as
a **comma-separated string** of `"KEY"` / `"KEY=VALUE"` tokens
(`"TRY_HARDER,NR_ALLOW_SKIP_ROWS=0"`). A string is split at the first `=` only,
so a value may itself contain `=`.

**Flag semantics.** A flag hint counts as *set* when its key is present with any
value other than the off spellings `false`, `0`, `no`, `off` or empty - so
`"TRY_HARDER"`, `"TRY_HARDER=1"`, `"TRY_HARDER=yes"` and `tHints["TRY_HARDER"] =
true` are all on, and `"PURE_BARCODE=no"` is off.

| Hint | Value | Effect |
|---|---|---|
| `TRY_HARDER` | flag | Scan more thoroughly (denser row stride). **Recommended for photographs.** |
| `ALSO_INVERTED` | flag | If the normal decode fails, retry on the inverted matrix (white modules on a black background). Costs a second detection pass only when the first fails. |
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
| **`qr/qr_demo.lc`** | 📷 **Interactive scanner.** A polished single-page web app: drag-and-drop, click-to-browse, paste-from-clipboard, live webcam capture, or (when the operator switches it on) an image URL. Decodes asynchronously (no page reload, live progress) and **recognises the content** — links, Wi-Fi, contacts, geo, email/phone/SMS, calendar events — with one-tap actions, copy, and a recent-scan history. Falls back to a plain server-rendered form when JavaScript is off. Needs its two sibling assets `qr_demo.css` / `qr_demo.js`. Uses `qrDecodeResultRobust`. See [Deploying the demo](#deploying-the-demo). |
| `qr/qr_tester.lc` | The **497 unit tests** (19 panels) as a per-module pass/fail dashboard with a byte-exact reporter, per-panel isolation and a completeness trailer, plus an engine-environment panel and an interactive helper evaluator. |
| `qr/qr_golden.lc` | The **5 golden photographic fixtures** decoded through the public API with the spec hints (acceptance suite). |
| `qr/qr_synthetic.lc` | The **49-row synthetic corpus** (`qr/fixtures/synthetic/`, from an independent encoder) decoded through `qrDecodeResultRobust` with each row's hints and compared byte for byte. |
| `qr/qr_decodeprobe.lc` | A minimal **self-contained real-image decode** (embedded PNG → `"HI"`) through the full public pipeline. |
| `qr/qr_imageprobe.lc` | Standalone **capability probe**: does this headless engine decode images and expose `the imageData` at 4 bytes/pixel in `0,R,G,B` order? Needs no other files. |

### Deploying the demo

Two literal constants at the top of `qr/qr_demo.lc` are the operator's
switches:

- `kDemoAllowUrlFetch` (default `"off"`): set to `"on"` to show the *Image URL*
  tab and let the page fetch a user-supplied `http(s)` URL from your server.
  That is a server-side request forgery surface - the page screens private
  address ranges, but redirects and DNS rebinding cannot be vetted in pure
  xTalk - so leave it off unless you need it.
- `kDemoMaxUploadBytes` (default 12,000,000): uploads, pasted `data:` URIs and
  fetched images above this size are refused before any decoding work.

---

## Project layout

```
xtQRdecoder/
├─ qr/                          the library source (pure xTalk)
│  ├─ qrCompat.lc               integer/bitwise compat (qr_u32, qr_shl, qr_uShr, qr_aShr, …)
│  ├─ …                         GF(256), Reed–Solomon, bit structures, luminance,
│  │                            binarizers, detection geometry, bitstream parse
│  ├─ qrReader.lc               ★ PUBLIC API (qrDecodeFromData / …Result / …Robust)
│  ├─ suite_*.lc                19 unit-test panels (497 assertions)
│  ├─ qr_demo.lc                interactive scanner page (server)
│  ├─ qr_demo.css               scanner styling (sibling asset)
│  ├─ qr_demo.js                scanner client: tabs, drag/drop, camera,
│  │                            async decode, smart content actions, history
│  ├─ qr_tester.lc              unit-test console
│  ├─ qr_golden.lc              golden-fixture acceptance page
│  ├─ qr_synthetic.lc           synthetic-corpus acceptance page
│  ├─ qr_decodeprobe.lc         self-contained real-image decode
│  ├─ qr_imageprobe.lc          image/imageData capability probe
│  └─ fixtures/                 5 golden test images (PNG)
│     └─ synthetic/             46 generated images + manifest.tsv (49 rows)
├─ lib/
│  ├─ xtQRdecoder.livecodescript  ★ the whole library combined into one
│  │                              script-only stack (desktop / mobile / server)
│  ├─ examples/xtQRdecoder-demo.livecodescript   the one-file showcase stack (suite UI kit, library carried)
│  ├─ examples/scanButton.livecodescript   a ready-to-paste "Scan QR" button
│  ├─ examples/demoStack/        a 2-button demo stack (Decode QR + Verbose Decode)
│  └─ README.md                 library quick-start
├─ tools/                       the compiler-free gates (no engine in CI)
│  ├─ lcs_model.py              headless execution model of the engine (MODEL.md)
│  ├─ run_unit_tests.py         the suites under the model
│  ├─ run_golden.py, run_synthetic.py   the fixtures through the public API
│  ├─ verify_tables.py          every decoder table from first principles / ZXing
│  ├─ check_engine_rules.py     the xTalk Suite's checker (vendored verbatim)
│  ├─ lint_lcs.py               this repo's linter
│  ├─ build_livecodescript.py   regenerates lib/ from the modules (--check gate)
│  ├─ sync_demo_embeds.py       carries the library + suite blocks into the showcase (--check gate)
│  ├─ ui-kit.livecodescript, demo-selfcheck.livecodescript   the xTalk Suite's masters, vendored verbatim
│  ├─ gen_synthetic_fixtures.py regenerates the synthetic corpus (--check gate)
│  └─ test_gates.py, test_model_mutations.py   the gates' own mutation tests
├─ docs/
│  ├─ ARCHITECTURE.md           architecture & contributor guide
│  ├─ CONTRIBUTING.md           how to contribute
│  ├─ VERIFICATION.md           what is proven, how, and on what engine
│  ├─ ENGINE-LESSONS.md         the engine lessons applied, with evidence
│  └─ spec.md                   authoritative port specification
├─ CHANGELOG.md                 release history
├─ LICENSE                      Apache-2.0
└─ NOTICE                       ZXing / khanamiryan attribution
```

The `qr/*.lc` modules are the single source of truth;
`lib/xtQRdecoder.livecodescript` and `qr/fixtures/synthetic/` are generated from
them and from the generator, and CI refuses a stale copy of either. Internal
architecture and conventions: see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

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
- [`docs/VERIFICATION.md`](docs/VERIFICATION.md) — what is proven, how, and on
  what engine; how to do and record an engine pass.
- [`docs/ENGINE-LESSONS.md`](docs/ENGINE-LESSONS.md) — the xTalk engine lessons
  this code applies, with their evidence.
- [`docs/spec.md`](docs/spec.md) — the authoritative algorithm/data specification.

---

## Verification status

There is no xTalk engine in CI, so every claim here has a label
([`docs/VERIFICATION.md`](docs/VERIFICATION.md) is the authoritative record):

- **Engine-passed:** the unit harness (399 assertions) and the 5 golden fixtures
  on a 9.6.11-class xTalk server build, at the 0.1.0 release (2026-06-03).
- **Model-passed, on every push:** 497 assertions, 5 golden fixtures, the 49-row
  synthetic corpus and 5,060 table checks under a headless execution model of
  the engine whose divergences are named (`tools/MODEL.md`); the static gates are
  mutation-tested.
- **Verified statically; needs an OXT pass:** everything changed in 0.2.0, the
  desktop and mobile examples, and `start using` on a non-server engine.

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
