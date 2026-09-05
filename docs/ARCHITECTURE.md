# xtQRdecoder — architecture and contributor guide

This document explains how xtQRdecoder is built and the conventions to follow
when contributing. For usage, see [`README.md`](../README.md); for the
authoritative algorithm and data-table specification, see [`spec.md`](spec.md).
The [`khanamiryan/php-qrcode-detector-decoder`](https://github.com/khanamiryan/php-qrcode-detector-decoder)
PHP source (itself a port of ZXing) is the line-level authority for behaviour.

---

## 1. What xtQRdecoder is

A pure **xTalk** port of the ZXing QR **decoder**, targeting **OpenXTalk** and
compatible xTalk engines (9.6.3+ generation and later) on desktop, mobile, and
headless servers. It reads existing QR codes from raster images; it does not
generate them. The public entry point is `qrDecodeFromData(imageBytes)` →
decoded text, running entirely in xTalk with no companion app, external, or GUI.

---

## 2. The pipeline

The decode is a linear pipeline; each stage is a module group (see `spec.md` §3
for the authoritative description):

```
image bytes (PNG/JPEG/GIF/BMP)
   → luminance acquisition      luminanceSource.lc        (imageData → greyscale plane)
   → binarization               hybridBinarizer.lc /      (greyscale → BitMatrix)
                                globalHistogramBinarizer.lc
   → detection                  detector.lc + finder/alignment/perspective/grid
   → bit-matrix parsing         bitMatrixParser.lc        (format/version/codewords)
   → error correction           dataBlock.lc + reedSolomonDecoder.lc (GF(256))
   → bitstream decode           decodedBitStreamParser.lc (modes + charset → text)
```

`qrReader.lc` wires the front of the pipeline (image → binary bitmap);
`qrCodeReader.lc` (`qcr_decode`) runs detection through bitstream decode. The
integer layer (`qrCompat.lc`) underpins everything.

---

## 3. Architecture conventions

- **OOP-as-arrays ("Pattern A").** There are no classes; each "object" is an
  xTalk array and methods are handlers named `<class>_<method>` whose first
  argument is the instance. Mutators are **commands** taking the instance by
  reference (`@`); accessors are **functions**. Example: `bitMatrix_new()`
  returns an array; `bitMatrix_set tBM, x, y` mutates it; `bitMatrix_get(tBM, x,
  y)` reads it.
- **0-based indexing throughout**, matching the PHP/Java source. xTalk arrays
  accept key `0` directly. String byte access is 1-based, wrapped by
  `qr_byteAt(s, i)`.
- **All bit-packed words are unsigned 32-bit** `[0, 2³²)`. Every bit operation
  routes through `qrCompat` (`qr_u32`, `qr_shl`, `qr_uShr`, `qr_aShr`, …). Never
  compare a packed word to a negative literal; `-1` is `4294967295`. Shift counts
  are masked to 5 bits, as Java masks them.
- **Every handler carries a prefix** (`bitMatrix_`, `dbsp_`, `fpf_`, `qr_`, …)
  so a host stack that co-loads the library cannot shadow an internal name; the
  build refuses duplicate handler or script-level names across modules.
- **Delimiters are set immediately before the chunk read that needs them and
  never assumed from a caller.** The public boundary (`qr_parseHints`) saves and
  restores the caller's `itemDelimiter`. This keeps the code correct under both
  scoping rules that engines have been observed to apply - see
  [`ENGINE-LESSONS.md`](ENGINE-LESSONS.md) for the evidence on each side.
- **Errors are rethrown after `end try`, never from inside `catch`** (the engine
  swallows a throw made inside a catch block): record the error in a local,
  close the try, then throw.
- **The engine image object is touched in exactly one handler**
  (`luminanceSource_decodeRawPlane`): messages locked, a private invisible host
  stack made the defaultStack, a fixed scratch image name, the image deleted and
  the defaultStack and `lockMessages` restored on every exit. The headless model
  never compiles it; the host supplies a PNG decoder instead (MODEL.md D17).
- **Static tables initialise lazily** via a `<mod>_ensure` guard that runs
  `<mod>_init` once (mirrors the PHP `::Init()` pattern). See `genericGF`,
  `version`, `formatInformation`.
- **Exceptions are tagged strings:** `throw "Format: …"`, `"NotFound: …"`,
  `"Checksum: …"` / `"RS: …"`. The public API catches these and returns empty +
  an `["error"]` field; they never escape (spec §6.6, §9).
- **Cross-module dependencies** are listed in each file's header comment and
  respected in the `include` order in the entry pages (dependencies first). A few
  small helpers are duplicated locally to avoid a cross-module dependency — an
  acceptable trade-off for load-order simplicity.

---

## 4. xTalk engine rules the parser enforces

These are not stylistic — the engine **rejects** the alternatives, often with a
parse error that takes down the whole file (and anything that `include`s it). Two
static gates check them on every push: this repository's linter
(`tools/lint_lcs.py`) and the xTalk Suite's unified checker, vendored verbatim
(`tools/check_engine_rules.py`). Rules 1-14 were paid for on the 9.6.11-class
server build this project first ran on; rules 15-24 come from the suite's
OpenXTalk record (see [`ENGINE-LESSONS.md`](ENGINE-LESSONS.md)).

### Reserved words are the biggest hazard

xTalk reserves a large vocabulary of property, function, keyword, and
abbreviation names. Some are not in the published grammar yet are still rejected
by the engine (e.g. `centers`, and object-type shorthands like
`ac`/`bg`/`cd`/`btn`/`fld`/`img`/`snd`), so no static list is provably complete.

**Convention: prefix every local with `t` and every parameter with `p`** (`tDim`,
`pVersion`). A `t`/`p`-prefixed camelCase identifier cannot collide with a
reserved word. Single letters (`i`, `j`, `n`, `x`, `y`, `c`, `r`, `b`, `e`, `p`)
are safe for loop counters.

### Other engine-confirmed rules

1. **No `0x..` hex literals.** Write decimal; put the hex in a comment.
   `constant` takes only literals, not expressions (no `2^32`).
2. **Bitwise operators have LOW precedence.** `i bitAnd 1 = 0` parses as
   `i bitAnd (1 = 0)`. **Parenthesize every bitwise sub-expression:**
   `(i bitAnd 1) = 0`.
3. **No bare `return`.** A valueless `return` errors with "missing factor". Use
   `return <expr>` to yield a value, or `exit <handlerName>` to leave early.
4. **Variable names are case-insensitive.** Declaring param `R` and local `r` in
   the same handler is a redeclaration error.
5. **`end` keywords must match their opener type.** An `if/else` block closed with
   `end try` is a structural error the engine catches late.
6. **`set the itemDelimiter` inside `repeat for each item` is unreliable** — the
   loop caches the delimiter at entry. Index with `repeat with i` and re-set the
   delimiter each iteration. Same for `lineDelimiter` + `repeat for each line`.
7. **`qr_shl` must be precision-safe.** `qr_u32(a * 2ⁿ)` overflows 2⁵³ and
   silently drops low bits when shifting a full 32-bit word; `qr_shl` discards
   out-shifted high bits *before* multiplying. Don't "simplify" it.
8. **`<?lc … ?>` wraps every server file**, and loose top-level statements must
   come **after** all handler definitions (the "main" block at the bottom).
9. **`include` may need an absolute path.** Some builds leave `the defaultFolder`
   pointing elsewhere; the entry pages resolve their own directory from several
   `$_SERVER` candidates. See `qrFindBase()`.
10. **Under `explicitVariables`**, every `local`, parameter, and loop variable
    must be declared. We declare them all defensively.
11. **No `repeat … step N`.** `repeat with` has only `to` / `down to`. To stride,
    iterate an index and compute the offset (`put (c * 2) into x`).
12. **Never put `else` after an inline `if … then <statement>`.** The engine binds
    the trailing `else` to the inline `if`, silently wrecking the block nest, and
    then mis-blames a distant `end repeat`/`end if`. Expand any inline-if that
    needs an `else` into a full `if / else / end if`.
13. **No literal×literal product as a `div`/`mod` right operand.** `div (4 * 57)`
    is rejected; precompute the literal (`div 228`).
14. **Prefer constructs the codebase already uses.** A few dictionary-valid
    operators (`is among the keys of`, `is an array`) are unexercised here; prefer
    the long-form equivalents that are proven (`is among the lines of the keys
    of`, `the keys of X is not empty`).
15. **Pure ASCII, comments and strings included.** Curly quotes fail
    compilation; the house rule is zero non-ASCII bytes so that class can never
    slip in (`numToCodepoint(9608)` for a block glyph, not the glyph).
16. **Never write a zero-argument call as `foo()` in statement position.** Write
    `foo`. (In expression position `foo()` is fine.)
17. **Never `throw` inside a `catch` block.** The error is swallowed. Record it,
    `end try`, then throw.
18. **Constants are literals, declared above their first use, in the file that
    uses them.** OpenXTalk resolves script-level `constant`/`local` names by
    lexical position; a handler above the declaration sees an undeclared name,
    which silently evaluates to its own spelling.
19. **No `local` inside an `if`/`repeat` block.** Declare every handler local at
    block depth 0.
20. **`the number of keys of` and `does not contain` do not parse.** Use `the
    number of elements of` and `is not in`.
21. **There is no `folder` property of a stack, and no `handlers` property.**
    Derive a sibling path from `the effective filename of this stack`; test
    readiness with `is among the lines of the stacksInUse`.
22. **`create` opens the stack it makes and unqualified controls resolve against
    the defaultStack.** Pin the defaultStack to a private stack around any
    control work and restore it on every exit.
23. **`textDecode(..., "UTF-8")` never throws on malformed input.** Establish
    validity yourself (the bitstream parser walks the bytes).
24. **`the caseSensitive` is off by default.** A reporter that compares decoded
    text with `=` alone passes case-folded and numeric near-misses; set the
    property in the reporter and check byte lengths.

### Reading a parse error

The engine's reported token is often the one **after** the real problem — the
parser aborts the statement, then names what it tried to execute next. When a
fix shifts the column but the token name stays the same, believe the token name,
not the line number, and look earlier in the same handler for a block-structure
desync (an inline-if+else, or a mismatched `end`).

---

## 5. The gates

There is no engine in CI, so a set of compiler-free gates stands in for it.
Run them all before every commit; CI runs the same commands on every push.

```sh
python3 tools/lint_lcs.py qr lib/xtQRdecoder.livecodescript   # this repo's linter
python3 tools/check_engine_rules.py      # the xTalk Suite's 22-rule checker (vendored verbatim)
python3 tools/build_livecodescript.py --check   # the combined stack is in sync + structurally sound
python3 tools/run_unit_tests.py          # the 19 suite panels under the headless model
python3 tools/run_unit_tests.py --lib    # the same against the combined stack
python3 tools/run_golden.py              # the 5 golden photos through the public API
python3 tools/run_synthetic.py           # the 49-row synthetic corpus
python3 tools/verify_tables.py           # every decoder table from first principles / ZXing
python3 tools/test_gates.py              # the static gates catch their seeded defects
python3 tools/test_model_mutations.py    # the suites go red on seeded library defects
python3 tools/gen_synthetic_fixtures.py --check   # the corpus matches its generator (needs `pip install qrcode`)
```

- **The linter** (`lint_lcs.py`) checks block-type matching, reserved words, bare
  `return`, case-insensitive collisions, undeclared loop/written variables, the
  delimiter-in-`for each` pitfall, nested `local`s and the SPDX header. When the
  engine reveals a new reserved word, add it to the `RESERVED` set.
- **The suite checker** (`check_engine_rules.py`) is
  `tools/check_livecodescript.py`, the xTalk Suite's checker byte-for-byte; the
  wrapper strips the `<?lc ... ?>` server tags and maps line numbers back. Never
  edit the vendored file; update it from the suite.
- **The headless model** (`lcs_model.py`, documented in
  [`../tools/MODEL.md`](../tools/MODEL.md)) compiles the shipped `.lc` text to
  Python and runs the suites and fixtures. Its divergences from the engine are
  named (D1-D22); a green model run says the algorithm is right as written, and
  its own trailer says "not an engine pass".
- **Every gate is mutation-tested** (`test_gates.py`, `test_model_mutations.py`):
  a gate that has never been seen to fail is a decoration.

What each of these proves, and what is engine-verified, is recorded in
[`VERIFICATION.md`](VERIFICATION.md).

---

## 6. Testing philosophy

Every layer is validated in two ways before it is trusted:

1. **Verify the data/logic against an independent oracle first** (ZXing, the
   Python `qrcode` library, ISO/IEC 18004) before porting a table or algorithm.
   This catches transcription errors that a single wrong table value would
   otherwise hide.
2. **Then run it under the headless model** (`tools/run_unit_tests.py`) and,
   when you can, **on a real engine** via the same `suite_*.lc` panel in
   `qr_tester.lc`. A model pass is labelled *verified statically; needs an OXT
   pass* until an engine run is recorded in [`VERIFICATION.md`](VERIFICATION.md).

Two rules that matter:

- **Never assert an expected value you haven't independently derived.** A
  fabricated fixture can pass a *broken* decoder.
- **Always include a multi-part / edge case**, not just the happy path. (A
  single-segment test can pass by luck when trailing bits read as a terminator; a
  multi-segment input — e.g. ECI + a non-ASCII byte segment — exercises the real
  state handling.)

### What's verified

The authoritative, dated record is [`VERIFICATION.md`](VERIFICATION.md). In
brief:

- **497 unit tests** across 19 `suite_*.lc` panels (run via `qr/qr_tester.lc`,
  headlessly via `tools/run_unit_tests.py`). 399 of them (harness 1) were green
  on a stock xTalk server engine (a 9.6.11-class community build) at the 0.1.0
  release; the 98 in `suite_reader` were added in 0.2.0 and have passed under
  the model only.
- **The synthetic corpus**: 46 images from an independent encoder, 49 manifest
  rows (`qr/fixtures/synthetic/`, `qr/qr_synthetic.lc`, `tools/run_synthetic.py`).
- **Every decoder table** regenerated from ISO/IEC 18004 and ZXing's own rows
  (`tools/verify_tables.py`, 5,060 checks).
- **5 golden photographic fixtures** decode through the public API
  (`qr/qr_golden.lc`; engine-passed at 0.1.0, model-passed since):

  | Fixture | Hints | Expected |
  |---|---|---|
  | `hello_world.png` | — | `Hello world!` |
  | `empty.png` | — | (no decode) |
  | `test.png` (776×640) | `TRY_HARDER` | gosuslugi URL |
  | `139225861-…png` | `TRY_HARDER`, `NR_ALLOW_SKIP_ROWS=0` | gosuslugi URL |
  | `binary-test.png` | `BINARY_MODE` | bytes `0x00..0xFF` |

The detector geometry is also validated end-to-end on synthetic photos before
any real image: a "HI" v1 matrix upscaled ×4 runs the whole detector back to a
bit-identical matrix; a v2 "HELLO WORLD" symbol exercises the alignment-pattern
branch.

### Adding a test panel

1. Write `qr/suite_<name>.lc` defining `command suite_<name>` that calls
   `t_eq pName, pGot, pExp` (the reporter is provided by the runner; it compares
   byte-exactly under `the caseSensitive`).
2. In `qr/qr_tester.lc`, add the suite filename to the `tFiles` list, add the
   `include` line, add a `startSuite` / `try suite_<name> catch ... end try` /
   `endSuite` / `add 1 to sPanelsRan` block in `renderPage`, bump
   `kQrPanelCount` and `kQrHarnessVersion`.
3. Add the panel to `SUITES` in `tools/run_unit_tests.py` and run the gates
   (section 5). If the panel pins a defect class, add a seeded mutation for it
   to `tools/test_model_mutations.py`.
4. When you can, open `qr/qr_tester.lc` on an engine and record the run in
   `VERIFICATION.md`.

---

## 7. The script-only library build

`lib/xtQRdecoder.livecodescript` is a single-file build of the whole decoder,
generated from the `qr/*.lc` modules by `tools/build_livecodescript.py`. The
modules are the single source of truth — never edit the combined file by hand.
After changing any library module:

```sh
python3 tools/build_livecodescript.py            # rewrite the combined stack
python3 tools/build_livecodescript.py --check     # verify it's in sync (CI gate)
```

The combined build uses the identical namespace to the server's `include` of the
same modules, and the build validates the concatenation itself: no duplicate
handler or script-level names, balanced handlers, no script-level name
referenced above its declaration, pure ASCII. `tools/run_unit_tests.py --lib`
runs the whole suite against the combined text. Loading it with `start using`
on a desktop or mobile engine has not been observed on an engine yet
([`VERIFICATION.md`](VERIFICATION.md)).

---

## 8. Scope and limitations

- **Decoder only** — xtQRdecoder reads QR codes; it does not generate them.
- **Kanji (Shift-JIS) / Hanzi (GB2312)** modes are not decoded.
  `decodedBitStreamParser` raises a documented "not supported" error for them
  (xTalk `textDecode` has no Shift-JIS/GB2312 codec). Numeric, Alphanumeric, and
  Byte (ASCII / ISO-8859-1 / UTF-8) — the overwhelming majority of real QR codes,
  including all URLs — are fully supported. To add Kanji/Hanzi later (spec §8.7),
  bundle compact Shift-JIS↔Unicode and GB2312↔Unicode mapping tables in
  `qr/tables/`, then convert the double-byte values to codepoints. This is a
  self-contained sub-project; it does not block the detector.
- **JPEG decode depends on the engine build** having a JPEG import codec. PNG /
  GIF / BMP decode everywhere; the library reports a precise error if an image
  doesn't decode.

---

## 9. File inventory

```
qr/
  qrCompat.lc                  integer/bitwise compat (qr_u32, qr_shl, qr_uShr, qr_aShr, …)
  genericGF.lc genericGFPoly.lc reedSolomonDecoder.lc   GF(256) + Reed–Solomon
  bitArray.lc bitMatrix.lc bitSource.lc                 packed bit structures
  luminanceSource.lc                                    imageData → greyscale (§7)
  globalHistogramBinarizer.lc hybridBinarizer.lc binaryBitmap.lc   binarization
  errorCorrectionLevel.lc mode.lc dataMask.lc formatInformation.lc version.lc   tables
  characterSetECI.lc dataBlock.lc decodedBitStreamParser.lc   bitstream
  bitMatrixParser.lc decoder.lc                         matrix parse + orchestration
  mathUtils.lc resultPoint.lc                           detector helpers (§8.4)
  perspectiveTransform.lc gridSampler.lc                geometry + grid sampling
  finderPatternFinder.lc alignmentPatternFinder.lc detector.lc   detection
  qrCodeReader.lc qrReader.lc                           public API (§9)
  suite_*.lc                   one test panel per layer (19 panels)
  fixtures/                    golden test PNGs
  fixtures/synthetic/          the generated corpus (46 PNGs + manifest.tsv)
  qr_demo.lc qr_demo.css qr_demo.js    interactive scanner page + assets (server)
  qr_tester.lc                 browser test console (the unit tests)
  qr_golden.lc                 golden-fixture acceptance page
  qr_synthetic.lc              synthetic-corpus acceptance page
  qr_decodeprobe.lc            self-contained real-image decode (embedded PNG)
  qr_imageprobe.lc             standalone image / imageData capability probe
  tables/                      reserved for §8.7 Shift-JIS/GB2312 data
lib/
  xtQRdecoder.livecodescript     the whole library as one script-only stack
  examples/scanButton.livecodescript   a ready-to-paste "Scan QR" button
  examples/demoStack/          a 2-button demo stack (Decode QR + Verbose Decode)
tools/
  lint_lcs.py                  this repo's static checker
  check_livecodescript.py      the xTalk Suite's checker, vendored VERBATIM (never edit)
  check_engine_rules.py        runs it over the <?lc ?>-wrapped sources
  build_livecodescript.py      regenerates lib/ from the qr/ modules (--check gate)
  lcs_model.py + MODEL.md      the headless execution model and its named divergences
  run_unit_tests.py            the suites under the model
  run_golden.py                the golden fixtures under the model (pure-Python PNG decoder)
  run_synthetic.py             the synthetic corpus under the model
  gen_synthetic_fixtures.py    regenerates qr/fixtures/synthetic (--check gate; needs qrcode)
  verify_tables.py             every decoder table from first principles / ZXing
  test_gates.py                mutation tests for the static gates
  test_model_mutations.py      mutation tests for the suites
  add_spdx.py                  SPDX-header inserter
README.md                      usage + reference (repo root)
docs/spec.md                   authoritative port specification
docs/ARCHITECTURE.md           this document
docs/CONTRIBUTING.md           how to contribute
docs/VERIFICATION.md           what is proven, how, and on what engine
docs/ENGINE-LESSONS.md         the engine lessons applied, with evidence
```

---

## 10. Contributing checklist

1. Skim `spec.md` for the module you'll touch; the PHP/ZXing source is the
   line-level authority for behaviour.
2. `t`-prefix all locals, `p`-prefix all params. Parenthesize bitwise ops. No
   bare `return`. `<?lc ?>` wrapper, main block last.
3. Verify any new table/algorithm against an oracle, and write the `suite_*`
   expected values from that (include a multi-part/edge case). If it is a
   table, add it to `tools/verify_tables.py`.
4. Run every gate in section 5 until all are green.
5. If you changed a library module, rebuild: `python3
   tools/build_livecodescript.py` (CI refuses a stale combined stack).
6. When you can, run `qr/qr_tester.lc`, `qr/qr_golden.lc` and
   `qr/qr_synthetic.lc` on a real engine and record the engine, platform, date
   and counts in `VERIFICATION.md`; until then the PR's label is *verified
   statically; needs an OXT pass*.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full workflow.
