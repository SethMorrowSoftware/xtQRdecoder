# Contributing to xtQRdecoder

Thanks for your interest. xtQRdecoder is a pure **xTalk** port of the ZXing
QR decoder, targeting **OpenXTalk** and compatible xTalk engines (9.6.3+
generation and later) across desktop, mobile, and headless server. A few aspects
of this project make contributing differ from a typical repository, so please
read this first.

## The one hard constraint: there is no engine in CI

There is **no xTalk engine in CI**, and likely none in your usual toolchain
either — the decoder runs only on an xTalk engine (OpenXTalk, an xTalk
standalone/IDE, or xTalk server). The workflow is therefore:

1. Make your change.
2. Run the compiler-free gates (all of them; CI runs the same commands):

   ```sh
   python3 tools/lint_lcs.py qr lib/xtQRdecoder.livecodescript
   python3 tools/check_engine_rules.py
   python3 tools/build_livecodescript.py --check
   python3 tools/run_unit_tests.py && python3 tools/run_unit_tests.py --lib
   python3 tools/run_golden.py && python3 tools/run_synthetic.py
   python3 tools/verify_tables.py
   python3 tools/test_gates.py && python3 tools/test_model_mutations.py
   ```

   The unit, golden and synthetic runs execute the shipped `.lc` text under a
   headless **model** of the engine (`tools/MODEL.md` names its divergences).
   A green model run means the algorithm is right as written; it is not an
   engine pass, and the runners say so in their own trailers.
3. Verify the algorithm/data in **Python** against an independent oracle when
   you touch a table or algorithm (see "Testing philosophy" below), and put
   the oracle in `tools/verify_tables.py` or the synthetic corpus so the
   attestation is committed, not remembered.
4. When you can, run it on a real engine. The bundled `.lc` test pages are
   written for **xTalk server** — deploy the `qr/` folder and open the
   relevant page in a browser to confirm that it passes:
   - `qr/qr_tester.lc` — the unit suite (per-panel pass/fail dashboard; the
     page must end with its `END OF REPORT` trailer)
   - `qr/qr_golden.lc` — the golden photographic fixtures (acceptance)
   - `qr/qr_synthetic.lc` — the synthetic corpus (acceptance)
   - `qr/qr_demo.lc` — the interactive scanner

   On OpenXTalk / a desktop or mobile engine, `start using
   lib/xtQRdecoder.livecodescript` and exercise the public API on the same
   fixtures instead.
5. State in your PR **which engine and version** you verified on (e.g. "xTalk
   server 9.6.11, Linux" or "OpenXTalk, macOS") and add the row to
   [`VERIFICATION.md`](VERIFICATION.md). Anything not run on an engine carries
   the label *verified statically; needs an OXT pass* — in the PR, in the
   docs, in the commit message.

A PR that has not been run on a real engine is fine to open as long as it
says so; the gates keep it honest and a maintainer will schedule the engine
pass.

## xTalk style rules

These are not preferences — the 9.6.x engine **rejects** the alternatives, often
with a misleading error pointing at the wrong line.
[`ARCHITECTURE.md`](ARCHITECTURE.md) §4 has the complete list and reasoning; the
essentials are:

- **Prefix every local with `t`, every parameter with `p`.** xTalk reserves a
  huge, *incompletely documented* vocabulary (`result`, `line`, `offset`,
  `mask`, `centers`, `ac`, …). A `t`/`p`-prefixed camelCase name can't collide.
- **No `0x..` hex literals.** Write decimal; put the hex in a comment.
- **Parenthesize every bitwise sub-expression:** `(i bitAnd 1) = 0`, never
  `i bitAnd 1 = 0` (bitwise ops bind *looser* than `=`).
- **No bare `return`.** Use `return <expr>` to yield a value, or
  `exit <handlerName>` to leave early.
- **No `repeat … step N`.** Iterate an index and derive the stride.
- **Never put `else` after an inline `if … then <statement>`.** Expand it.
- **`<?lc … ?>` wraps every file; the loose "main" block goes last**, after all
  handler definitions.
- **0-based arrays** (matching the PHP/Java source). Bit-packed words are
  unsigned 32-bit; route bit ops through `qrCompat` (`qr_u32`, `qr_shl`, …).
- **Pure ASCII source**, no `foo()` in statement position, no `throw` inside
  `catch`, constants literal and declared above use, no `local` inside a block
  — the xTalk Suite's rules, all gated (`docs/ENGINE-LESSONS.md`).

The two checkers catch most of these. When the engine teaches you a new reserved
word, **add it to the `RESERVED` set** in `tools/lint_lcs.py`; when it teaches
you a new rule, record it in `docs/ENGINE-LESSONS.md` with the build and date,
and offer it to the xTalk Suite's engine notes.

## Testing philosophy (please don't skip)

- **Verify expected values independently before writing a test.** Never assert a
  value you haven't derived from an oracle (ZXing, the `qrcode` Python lib, ISO
  18004). A fabricated fixture can pass a *broken* decoder.
- **Include a multi-part / edge case**, not just the happy path.
- **Prove the test can fail.** A new assertion that pins a defect class should
  come with a seeded mutation in `tools/test_model_mutations.py`.
- Re-run the golden and synthetic runners after any change to the luminance /
  binarizer / detector / decoder path; for a pure optimisation, prove the
  output bit-identical stage by stage before and after.

## License of contributions

By contributing, you agree that your contributions are licensed under the
project's **Apache-2.0** license (see `LICENSE`). Keep the SPDX header on new
`.lc`/`.py` files:

```
-- SPDX-License-Identifier: Apache-2.0
-- Copyright <year> <you>
-- Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
```

Retain ZXing/khanamiryan attribution in any ported file (see `NOTICE`).

## Scope

xtQRdecoder is a **decoder/reader only** — it does not generate QR codes. Known
limitations (e.g. Kanji/Hanzi) are documented in
[`ARCHITECTURE.md`](ARCHITECTURE.md) §8 and `README.md`. New modes and levels are
welcome; please open an issue to discuss large changes first.
