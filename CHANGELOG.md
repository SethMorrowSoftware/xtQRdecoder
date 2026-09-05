# Changelog

All notable changes to xtQRdecoder are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the project aims to
follow [Semantic Versioning](https://semver.org/).

## [0.2.0] — 2026-09-05

A correctness, fidelity and verification release. Four real decoder defects
found by a synthetic corpus and confirmed against ZXing itself; the detector
brought up to current ZXing; the interpreted hot loops halved; the xTalk
Suite's engine lessons applied throughout; and a compiler-free verification
stack (a headless execution model, an independent-encoder corpus, table
regeneration, mutation-tested gates) that runs on every push. The public API
gains one hint and several result keys; nothing is removed.

> **Verification status.** Everything in this release is proven under the
> headless model and the static gates; **none of it has yet run on an
> engine.** The 0.1.0 engine record (399 unit assertions and 5 golden
> fixtures on a 9.6.11-class xTalk server build) stands unchanged, and its
> expected values were never edited. See `docs/VERIFICATION.md`.

### Fixed
- **Versions 39 and 40 could not be decoded.** Their alignment-centre rows in
  `version.lc` were wrong (eight entries, two beyond the symbol), so every
  v39/v40 symbol threw "region must fit inside matrix". The rows now match
  ZXing's table, and `tools/verify_tables.py` regenerates all forty rows from
  ZXing's source and the ISO/IEC 18004 module-count identity on every push.
- **Mirrored symbols never decoded.** The transpose retry un-masked the
  untransposed matrix and then read it transposed, so every mirrored symbol
  failed Reed-Solomon. The copy is now transposed first
  (`bitMatrix_transposed`), as ZXing's `BitMatrixParser.mirror` does, and the
  result points are swapped for a mirrored symbol.
- **UTF-8 byte payloads came back as mojibake.** Byte segments without an ECI
  were always decoded as ISO-8859-1. The charset is now guessed as ZXing's
  `StringUtils.guessCharset` does (UTF-16 by byte-order mark, UTF-8 when
  structurally valid with a multi-byte character, else ISO-8859-1); UTF-16 is
  decoded; the UTF-8 walk rejects overlong and surrogate forms.
- **Clean version-30 symbols were rejected** by the pre-2020 finder-pattern
  selection, which discarded the three true finders as module-size outliers.
  Selection now follows current ZXing (isosceles-right-triangle scoring, a
  diagonal cross-check on every candidate, MAX_MODULES 97, row skip 2).
- Shift counts are masked to five bits as Java masks them
  (`qr_shl(1, -1)` is `1 << 31`); the Euclidean loop bound is ZXing's
  `2*deg(r) >= R`, which matters for an odd number of EC codewords.

### Changed (fidelity and contract)
- Reed-Solomon failures are reported as `Checksum: ...` and untagged internal
  errors as `Format: ...`, the documented tag contract. Unknown ECI values,
  alphanumeric indices >= 45, truncated byte segments and structured-append
  headers, a codeword count that does not match the version, a version-info
  block whose dimension disagrees with the matrix, and versions outside 1..40
  are `Format` errors as in ZXing.
- Detector geometry follows current ZXing Java: integer `computeDimension`
  with the residue-3 recovery, truncated alignment estimate, integer Bresenham
  error term and alignment row schedule; out-of-image samples read white; a
  NaN module size ends in `NotFound` instead of arithmetic on empty; only
  `NotFound` is swallowed around the alignment search. Result points agree
  with ZXing within one pixel on every corpus image.
- `qrDecodeResultRobust` plans its resolution ladder in integer downsample
  steps, skips rungs that would repeat identical work, builds each greyscale
  plane once for both binarizers, reports the **first** (most specific) error
  on total failure and lists every attempt.
- Flag hints accept `KEY`, `KEY=1`, `KEY=true`, `KEY=yes` and reject
  `0` / `no` / `off` / `false` / empty (`qr_hintFlag`); a hint string is split
  at the first `=` only; hint parsing restores the caller's `itemDelimiter`.
- `luminanceSource_decodeRawPlane` no longer creates its scratch image on the
  host app's front stack: it locks messages, pins the defaultStack to the
  library's own invisible stack, uses a fixed scratch image name, deletes the
  image and restores the defaultStack and `lockMessages` on every exit.
- The eleven unprefixed compat helpers are now `qr_`-prefixed (`qr_u32`,
  `qr_u8`, `qr_shl`, `qr_uShr`, `qr_aShr`, `qr_byteAt`, `qr_hashCode`,
  `qr_arraycopy`, `qr_floatToIntBits`, `qr_numberOfTrailingZeros`,
  `qr_fillArray`) so a host stack cannot shadow them. These were never part of
  the public API; the four `qrDecode*` entry points are unchanged.
- Every source file is pure ASCII (the compile-fatal curly-quote class can no
  longer slip in); the install idiom everywhere is
  `the effective filename of this stack` (there is no `folder` property of a
  stack), and the scan-button example no longer carries a dangling `else`, a
  nested `local` or a never-true `the handlers of stack` probe.

### Added
- **`ALSO_INVERTED` hint:** a failed decode is retried on the inverted matrix
  (white modules on black), as ZXing's `MultiFormatReader` does; the result
  carries `["inverted"] = true` when the retry won.
- Result keys `["charset"]`, `["fnc1"]`, `["symbologyModifier"]`,
  `["structuredAppendSeq"]` / `["structuredAppendParity"]`, `["inverted"]`,
  and (robust) `["step"]` and `["attempts"]`. FNC1 group separators in
  alphanumeric data are delivered as ZXing delivers them.
- `qrLibraryVersion()` returns the library version (`"0.2.0"`).
- **`qr/suite_reader.lc`** (98 assertions, harness 2 = 19 panels / 497
  assertions): hints and flag spellings, the delimiter restore, the v39/v40
  rows, range checks, masked shifts, transpose/flip, the mirrored and
  inverted retries, the `Checksum:` tag, alphanumeric/FNC1, charset guessing,
  ECI designators and errors, structured append, Kanji, and Reed-Solomon with
  an odd number of EC codewords. Every expected value was derived outside the
  port.
- **A synthetic corpus** (`qr/fixtures/synthetic/`, 46 images, 49 manifest
  rows) from an independent encoder, covering versions 1..40 at every EC
  level, all eight masks, rotations, mirrored and inverted symbols, lighting,
  blur, noise, tight and off-centre quiet zones, 1 and 2 px per module, UTF-8
  bytes and the `PURE_BARCODE` path; `qr/qr_synthetic.lc` runs it on an
  engine, `tools/run_synthetic.py` under the model, and
  `tools/gen_synthetic_fixtures.py --check` keeps it in sync pixel for pixel.
- **The compiler-free gates**, all in CI: `tools/lcs_model.py` (a headless
  execution model of the engine with its divergences named in
  `tools/MODEL.md`) with `run_unit_tests.py`, `run_golden.py` and
  `run_synthetic.py`; `tools/check_engine_rules.py` running the xTalk Suite's
  22-rule checker, vendored verbatim; `tools/verify_tables.py` (5,060 table
  checks from first principles and ZXing's rows); `tools/test_gates.py` and
  `tools/test_model_mutations.py` (every gate and the suites are
  mutation-tested); the build's lexical-order, ASCII and include-order checks.
- `docs/VERIFICATION.md` (what is proven, how, on what engine, and how to
  record an engine pass) and `docs/ENGINE-LESSONS.md` (the suite's lessons
  applied, each with its evidence class).

### Test harness
- `qr_tester.lc` harness 2: the reporter compares byte-exactly under
  `the caseSensitive` (a case-folded or numeric near-miss no longer passes);
  every panel runs in its own `try` so one throw becomes a FAIL row instead of
  a blank page; the report ends with an explicit completeness trailer and
  prints the harness and library versions. `qr_golden.lc`'s reporter is
  byte-exact the same way.

### Performance
- The interpreted hot loops execute **half the statements** they did, with
  output proven bit-identical at every intermediate stage on all 51 fixtures:
  per-module power-of-two tables replace `2 ^ n` and the shift helpers in
  `bitMatrix`, the binarizers accumulate a 32-bit word and write it once, the
  greyscale rule is branch-free, the downsample is single-pass, the finder's
  row scan skips all-white and all-black words, and the grid sampler and
  un-masker address the word arrays directly. Statements executed for the
  golden run: 46.2M to 22.3M.

### Security (demo page)
- `qr_demo.lc`: fetching an image by URL is off unless the operator sets
  `kDemoAllowUrlFetch` to `"on"` (the tab is not rendered when off), and
  uploads, pasted `data:` URIs and fetched images are refused above
  `kDemoMaxUploadBytes` before any decoding work.

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
