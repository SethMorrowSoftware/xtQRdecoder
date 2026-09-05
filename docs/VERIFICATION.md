# Verification status - what is proven, how, and on what

xtQRdecoder has no engine in CI. Every claim in this repository therefore
carries one of four labels, and this file is the single place that says
which label applies to what. If a sentence elsewhere in the docs does not
match this file, this file is right and the sentence is stale.

## The labels

| Label | Meaning |
|---|---|
| **ENGINE-PASSED (date, build)** | Ran on a real xTalk engine and passed. Always dated, always names the build. |
| **MODEL-PASSED** | Passed under `tools/lcs_model.py`, a headless execution model of the engine that compiles the shipped `.lc` text to Python. Its divergences from the engine are named and numbered in `tools/MODEL.md` (D1-D22). A model pass is strong evidence about the algorithm and the text; it is not evidence about the engine. |
| **STATIC** | Checked by a static gate on every push (the vendored xTalk Suite checker, the repository linter, the build's structural validation). |
| **verified statically; needs an OXT pass** | The honest label for anything the model cannot execute (the engine image object, `start using`, the desktop and mobile examples) or that has changed since the last engine run. |

## The engine record

| What | Engine | Date | Result |
|---|---|---|---|
| Unit harness 1 (17 panels, 399 assertions) via `qr/qr_tester.lc` | xTalk server, a 9.6.11-class community build, Linux | 2026-06-03 (the 0.1.0 release) | 399/399 |
| The 5 golden photographic fixtures via `qr/qr_golden.lc` | same | 2026-06-03 | 5/5 |
| Desktop / mobile / OpenXTalk (`start using` the combined stack, the showcase stack, the two examples, the demo stack) | - | never | **verified statically; needs an OXT pass** |
| Everything changed since 0.1.0 (see `CHANGELOG.md` 0.2.0) | - | not yet | **verified statically; needs an OXT pass** |

The 0.2.0 changes touch the finder, the detector, the decoder, the
bitstream parser, the version table, the public reader, the reporters and
the engine image path. All of it is MODEL-PASSED and STATIC; none of it is
ENGINE-PASSED. That is the whole truth of this release and the reason the
version number is 0.2.0 and not 1.0.

## The model record (2026-09-05, commit `3076cea` or later)

| Check | Command | Result |
|---|---|---|
| Unit harness 2 (19 panels), the `qr/*.lc` modules | `python3 tools/run_unit_tests.py` | 497/497 |
| The same against the combined stack | `python3 tools/run_unit_tests.py --lib` | 497/497 |
| Golden fixtures through the public API | `python3 tools/run_golden.py` | 5/5 (each twice: `qrDecodeFromData` and `qrDecodeResultRobust`) |
| Synthetic corpus (46 images, 49 rows) | `python3 tools/run_synthetic.py` | 49/49 |
| Decoder tables from first principles / ZXing | `python3 tools/verify_tables.py` | 5060/5060 |
| Gate mutation tests | `python3 tools/test_gates.py` | 15/15 caught |
| Suite mutation tests | `python3 tools/test_model_mutations.py` | 10/10 caught |
| Corpus in sync with its generator | `python3 tools/gen_synthetic_fixtures.py --check` | in sync |
| Hot-loop rewrite bit-identical to the pre-rewrite modules | equivalence harness (stage by stage: luminance at four scales, both binarizers, detector output, both public results) | identical on all 51 images |

Of the 497 unit assertions, 399 are the engine-passed harness-1 set
unchanged (their expected values were never edited) and 98 are
`suite_reader`, added in 0.2.0 with values derived from ISO/IEC 18004, an
independent GF(256) encoder and ZXing's rules, MODEL-PASSED only.

## What each gate proves, and how it is kept honest

| Gate | What it catches | Its own test |
|---|---|---|
| `tools/check_engine_rules.py` | The suite's 22 engine rules (pure ASCII, zero-argument statement calls, throw inside catch, dangling else, non-literal constants, constants used above declaration, undeclared k-constants, the shadow trap, `the number of keys of`, `does not contain`, command called as a function, ...) over every `.lc` and `.livecodescript` | `tools/test_gates.py` |
| `tools/lint_lcs.py` | Block matching, reserved words, bare `return`, case collisions, undeclared writes, the delimiter-in-for-each trap, nested `local`, SPDX headers | `tools/test_gates.py` |
| `tools/build_livecodescript.py --check` | The combined stack is regenerated from the modules and is byte-identical to the committed one; no duplicate handlers or script-level names across modules; no script-level name referenced above its declaration; pure ASCII; the five server pages include the modules in the canonical order | `tools/test_gates.py` |
| `tools/run_unit_tests.py` | The suites, with a byte-exact reporter, under the model | `tools/test_model_mutations.py` (10 seeded library defects go red) and the reporter's own near-miss check |
| `tools/run_golden.py`, `tools/run_synthetic.py` | Real and synthetic images through the public API, the engine image object replaced by a pure-Python PNG decoder (`tools/MODEL.md` D17) | the corpus rows include negative rows (an inverted symbol must FAIL without `ALSO_INVERTED`; `empty.png` must not decode) |
| `tools/verify_tables.py` | Every constant table against a source that is not the code | mutation-checked by hand: a one-bit change to a format-table entry is caught here (the BCH-tolerant decoder itself forgives it) |
| `tools/gen_synthetic_fixtures.py --check` | The committed corpus matches its generator pixel for pixel | a flipped pixel and a changed manifest byte were both caught |
| `tools/sync_demo_embeds.py --check` | The showcase stack carries the library, the suite UI kit and the self-check block exactly, its derived control list is current, and it would compile as one script (no collisions) | `tools/test_gates.py` (an edit inside the sentinels, a patched kit, a stale list, a colliding handler) |

## How to do an OXT pass, and how to record it

1. Deploy the whole `qr/` folder (including `qr/fixtures/`) to an xTalk
   server, or `start using lib/xtQRdecoder.livecodescript` on a desktop
   engine and drive the same pages' handlers from a button.
2. Open `qr/qr_tester.lc`. The page must end with
   `END OF REPORT - 19 panels ran of 19 registered, 497 assertions` and the
   harness line `harness 2 - library 0.2.0`. A page without that trailer is
   incomplete, whatever the banner says.
3. Open `qr/qr_golden.lc` (5 rows) and `qr/qr_synthetic.lc` (49 rows; the
   v40 image is 555 px square, allow time on a shared host).
4. On desktop, paste `lib/examples/xtQRdecoder-demo.livecodescript` into a
   new stack (`lib/examples/README.md`, five steps). The About tab's boot
   self-check block must end `... passed, 0 failed` and the Samples tab's
   **Decode all samples** must print eight PASS lines; copy both blocks
   verbatim into the record. On mobile, run
   `lib/examples/scanButton.livecodescript` on a golden fixture and on
   `qr/fixtures/synthetic/inverted-v3Q.png` with `TRY_HARDER,ALSO_INVERTED`.
5. Record the engine version and platform (`the version`, `the platform`),
   the date, the harness version and the counts in the engine record above,
   and move the corresponding rows from "needs an OXT pass" to
   ENGINE-PASSED. If anything fails, the failure row's text is the
   product: paste it into an issue verbatim.

## What a green CI means

Every static gate passed, the combined stack and the corpus are in sync
with their sources, and every unit, golden, synthetic and table check
passed under the model. It means the shipped text is well-formed under the
family's engine rules and that the algorithm, as written, decodes what it
claims to decode. It does not mean the engine agrees; only a dated row in
the engine record above means that.
