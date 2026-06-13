# Changelog

All notable changes to xtQRdecoder are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the project aims to
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Performance
- **Further reduced the interpreted hot-loop cost (the documented decode cost
  centre, `docs/spec.md` §11) with no change to decode output.** Output is
  bit-identical — verified by simulating the old vs. new logic over thousands of
  random pixel buffers and bit-matrices — so the 399 unit tests and 5 golden
  fixtures are unaffected:
  - `luminanceSource_newFromImageData` (one iteration per pixel) now walks the
    raw pixel plane with a `repeat for each byte` **sequential iterator** and a
    4-phase counter, instead of three indexed `byte (o+k) of pRaw` reads per
    pixel. Indexed chunk access re-resolves the chunk on every read; `repeat for
    each` advances an internal pointer and hands each byte over directly — the
    single biggest interpreted-loop lever in xTalk. (This also speeds the
    downsample path, which feeds the same handler.)
  - The two binarizers no longer invoke the `bitMatrix_set` **command** once per
    black pixel on their O(W·H) threshold loops (`hb_thresholdBlock` and
    `globalHistogramBinarizer`'s whole-image threshold). The bit-set is inlined,
    removing the per-pixel handler dispatch and the `shl` call (`shl(1, k)` is
    exactly `2 ^ k` for k in 0..31). The computed word index and set bit are
    unchanged, so the resulting `BitMatrix` is bit-identical.

## [0.1.0] — 2026-06-03

Second public release. Builds on `0.0.1` with a modern interactive scanner, the
documented hot-loop performance work, a ready-to-paste demo stack, and a
repository-wide documentation pass. The public API is unchanged.

### Added
- **A two-button demo stack** (`lib/examples/demoStack/`): a one-call "Decode QR"
  button and a "Verbose Decode" button that narrates each pipeline stage
  (luminance → binarize → detect → decode, rendering the de-skewed grid as block
  art), with a short assembly README.

### Performance
- **Optimised the interpreted hot loops (the documented decode cost centre,
  `docs/spec.md` §11) without changing any decode output** — the same bytes are
  produced, so the 399 unit tests and 5 golden fixtures are unaffected:
  - `luminanceSource_newFromImageData` (one iteration per pixel) now accumulates
    the greyscale plane in a flat local assigned to the instance once, indexes it
    by the loop counter directly, and advances the byte offset by addition rather
    than recomputing `p * 4` each pixel.
  - `hybridBinarizer` hoists the luminance plane out of the per-block loop and
    passes it (and the per-block black-points) **by reference** to
    `hb_thresholdBlock`, so the full-image arrays are no longer re-evaluated /
    copied on every 8×8 block (the same big-array-by-reference idiom as
    `arraycopy`).
  - `bitMatrix_new` zero-fills a flat local and assigns it into the instance
    once, instead of a nested write per word (the matrix is image-sized on the
    binarizer path).
  - **Hoisted the loop-invariant index arithmetic out of the remaining per-pixel
    binarizer/downsample loops** (strength-reducing a per-pixel multiply to a
    per-row add). The computed flat indices are unchanged, so output stays
    bit-identical:
    - `hb_calculateBlackPoints` and `hb_thresholdBlock` (the 8×8 block sum /
      threshold loops, and the 5×5 black-point neighbourhood) now compute each
      row's base offset once and index with a single add per pixel.
    - `globalHistogramBinarizer` computes the y-invariant sample-column bounds
      once instead of per sampled row, and hoists the row base in the histogram
      loop.
    - `luminanceSource_downsampleRaw` carries the source byte offset with a
      constant `add` per kept pixel instead of recomputing
      `((sy*pStep)*pW + sx*pStep)*4` each time (the same idiom as the per-pixel
      `add 4` already used in `luminanceSource_newFromImageData`).

### Changed
- **Reworked the interactive scanner (`qr/qr_demo.lc`) into a modern single-page
  web app.** Presentation moved into two sibling assets, `qr/qr_demo.css` and
  `qr/qr_demo.js`, served next to the page.
  - **Async decoding** via a new JSON response mode (`POST ?api=1`): the page no
    longer reloads to show a result, and displays a live loading state while the
    server decodes. The JSON is pure ASCII (free-text fields are base64/UTF-8) so
    it is robust regardless of the engine build's default output encoding.
  - **Richer input:** tabbed Upload / Camera / Image-URL, drag-and-drop,
    click-to-browse, paste-from-clipboard, live webcam capture (`getUserMedia`),
    instant local preview, and a phone camera-capture fallback.
  - **Smart results:** the decoded payload is recognised (web link, Wi-Fi,
    contact/vCard/MeCard, geo, email, phone, SMS, calendar event, or plain text)
    and shown with one-tap actions (open, call, email, save contact/`.vcf`, add
    to calendar/`.ics`, copy), plus a recent-scan history in `localStorage`.
  - **Accessible & resilient:** ARIA roles/labels, keyboard support, focus
    management, and `prefers-reduced-motion`. Progressive enhancement keeps the
    scanner fully functional as a plain server-rendered form with JavaScript off.
  - The untrusted decoded payload is rendered with `textContent` only, and link
    targets are restricted to a small URL-scheme allow-list.
  - **Refined the look & feel for desktop and mobile.** Wide screens now use a
    two-pane workspace — a sticky input card on the left and a live results
    column on the right (with a resting "Ready to scan" placeholder so it never
    looks empty); phones keep the focused single-column flow. Tightened the
    type, spacing, cards, buttons, toggles and chips throughout, and fixed a
    bug where action-button glyphs (the `.ico` SVGs) had no intrinsic size and
    ballooned to fill the button. Asset cache version bumped to `4`.

### Security & accessibility
- **Hardened the scanner's no-JavaScript path.** Decoded-QR link `href`s and the
  URL re-fill value are now attribute-escaped (closing an attribute-injection
  vector where a crafted QR payload could otherwise inject an event handler), and
  the inline preview's `data:` URI takes its MIME from the image's own magic
  bytes rather than the attacker-controllable upload `Content-Type`. Added
  `X-Content-Type-Options: nosniff`, `Referrer-Policy`, and an explicit
  content-type on the page responses.
- **Keyboard-accessible tabs** following the WAI-ARIA pattern (arrow / Home / End
  navigation over a roving `tabindex`).
- The result metadata now shows a data **mask of `0`** (previously suppressed),
  and the page carries a meta description plus Open Graph / Twitter tags for
  clean link previews.

### Documentation
- Repository-wide comment & documentation consistency pass for the release:
  unified spec cross-references and banner style, reconciled the engine-version
  wording across the docs, corrected several stale code comments (each verified
  against the code), and filled in file-inventory gaps. No decode behaviour
  changed.

## [0.0.1] — 2026-06-01

First public release to the xTalk community. A complete QR **decoder** in pure
xTalk — no externals, no companion app, no GUI — running on
**OpenXTalk** and compatible xTalk engines (9.6.3+ generation and later) across **desktop, mobile, and headless server**.

> This `0.0.1` is the first public release. The public API
> (`qrDecodeFromData` / `qrDecodeFromFile` / `qrDecodeResult` /
> `qrDecodeResultRobust`) is considered stable.

### Decoder
- Full ZXing decode pipeline ported line-for-line from
  [`khanamiryan/php-qrcode-detector-decoder`](https://github.com/khanamiryan/php-qrcode-detector-decoder):
  the integer/bitwise compatibility layer, GF(256) + Reed–Solomon, the bit
  structures, luminance acquisition + Hybrid/Global binarizers, the detector
  geometry (finder/alignment pattern finders, perspective transform, grid
  sampler), the decode tables (version/format/mode/data-mask), bitstream
  parsing, and the public API.
- QR **versions 1–40** and **all four error-correction levels (L/M/Q/H)**.
- **Numeric, Alphanumeric, and Byte (ASCII / ISO-8859-1 / UTF-8)** modes, plus
  ECI character-set switching, FNC1, and Structured Append metadata.
- Rotation / perspective tolerance for skewed photos, and a mirror-image
  (transpose) retry.
- **Robust multi-strategy decode** (`qrDecodeResultRobust`): decodes the image
  to a raw pixel plane once, then tries the Hybrid and Global binarizers at two
  scales (≤1200px and ~1600px), returning the first that decodes — greatly
  improving reliability on real-world phone photos (glare, blur, dense codes).
- `PURE_BARCODE` fast path for clean bordered images, and `BINARY_MODE` to return
  the raw decoded byte payload verbatim.
- Strict failure contract: the public API never throws — internal
  `NotFound` / `Format` / `Checksum` errors surface in the result's `["error"]`
  key.

### Packaging
- **Script-only library** (`lib/xtQRdecoder.livecodescript`): the entire decoder
  combined into one portable script-only stack, loadable on desktop, mobile, and
  server with `start using`. It is generated from the `qr/*.lc` modules by
  `tools/build_livecodescript.py` (with a `--check` sync gate), so the modules
  remain the single source of truth. See `lib/README.md`.
- xTalk server deployment via the raw `qr/` module folder (`include` in
  dependency order).
- A ready-to-paste "Scan QR" button example in
  `lib/examples/scanButton.livecodescript`.

### Tests & tooling
- **399 unit tests** across 17 `suite_*.lc` panels (run via `qr/qr_tester.lc`),
  plus **5 golden photographic fixtures** decoded through the public API
  (`qr/qr_golden.lc`) — both green on a real xTalk engine (a 9.6.11-class community build).
- Diagnostics pages: `qr/qr_imageprobe.lc` (image / `imageData` capability probe)
  and `qr/qr_decodeprobe.lc` (self-contained real-image decode through the full
  public pipeline).
- `tools/lint_lcs.py` static checker for the xTalk syntax rules, and a
  GitHub Actions workflow that runs it together with the build `--check` sync
  gate.

### Documentation & licensing
- Apache-2.0 `LICENSE`, a `NOTICE` carrying ZXing / khanamiryan attribution, a
  root `.gitignore`, and SPDX headers on every source file.
- An OpenXTalk-first `README.md` plus `docs/` (architecture & contributor guide,
  contributing workflow, and the authoritative port specification).

### Known limitations
- **Decoder only** — xtQRdecoder reads QR codes; it does not generate/encode
  them.
- **Kanji (Shift-JIS) / Hanzi (GB2312)** modes are not decoded:
  `decodedBitStreamParser` raises a documented "not supported" error because
  xTalk's `textDecode` has no Shift-JIS / GB2312 codec. Numeric / Alphanumeric
  / Byte (ASCII, ISO-8859-1, UTF-8) — the overwhelming majority of real QR codes,
  including all URLs — are fully supported. (See `docs/spec.md` §8.7 for how to
  add them.)
- **JPEG decode depends on the engine build** having a JPEG import codec; PNG /
  GIF / BMP decode everywhere. The library reports a precise error if an image
  fails to decode.
