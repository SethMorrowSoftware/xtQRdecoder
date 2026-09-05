# Engine lessons applied - the as-built record

This is xtQRdecoder's record of the xTalk Suite's hard-won OpenXTalk /
LiveCode engine lessons, what this repository did about each, and the
evidence class behind the claim. It is written in the suite's own style so
entries can be offered back to the family list (`docs/OXT-ENGINE-NOTES.md`
in `SethMorrowSoftware/xtalk-suite`) with their provenance intact.

## Evidence classes

| Class | Meaning |
|---|---|
| **ENGINE** | Observed on a real engine. Every ENGINE entry names the build and the date; see [`VERIFICATION.md`](VERIFICATION.md) for the record. |
| **MODEL** | Holds under the headless execution model (`tools/lcs_model.py`, named divergences in `tools/MODEL.md`). A model pass never promotes anything to ENGINE. |
| **STATIC** | Enforced by a gate that runs on every push (`tools/check_engine_rules.py`, `tools/lint_lcs.py`, `tools/build_livecodescript.py --check`). Each gate is mutation-tested by `tools/test_gates.py`. |
| **DESIGN** | Applied by construction; the code is written the way the lesson says, but no gate or engine run has exercised the exact path. Honest label: *verified statically; needs an OXT pass*. |

The one engine record this repository holds is the 0.1.0 release run: the
unit harness (399 assertions, harness 1) and the five golden fixtures green
on a 9.6.11-class xTalk server build (2026-06-03). Nothing added since has
run on an engine. Every date below is the date the change landed, not an
engine date.

## The lessons and what was done

| # | Suite lesson | What xtQRdecoder does | Evidence | Gate |
|---|---|---|---|---|
| 1 | Source is pure ASCII, comments and strings included; curly quotes fail compilation. | Every `.lc`, `.livecodescript`, `.py`, `.js` and `.css` is ASCII (normalised 2026-09-05). The build refuses a non-ASCII combined stack. | STATIC | checker (check 1), build |
| 2 | Vendor the family's unified checker byte-identical, with its rules, rather than a divergent local one. | `tools/check_livecodescript.py` is the suite's `onionxt/tools/check-livecodescript.py` verbatim; `tools/check_engine_rules.py` strips the `<?lc ... ?>` wrapper and maps line numbers back. | STATIC | check_engine_rules.py |
| 3 | A zero-argument call written `foo()` in statement position is fatal. | None in the tree; the checker refuses one. | STATIC | checker (check 8) |
| 4 | `throw` inside a `catch` is swallowed: the error never reaches the caller. | Every rethrow (`luminanceSource_decodeRawPlane`, `dec_tryParser`, `dec_correctBlock`, `dt_detect`) records the error in a local and throws after `end try`. | STATIC + MODEL | checker (check 9); suite_reader's error-tag assertions |
| 5 | The dangling else: a bare `else` after a single-line `if ... then stmt` wrecks the block nest. | `scanButton.livecodescript` expanded to block form; no inline-if-plus-else anywhere. | STATIC | checker (check 20) |
| 6 | Constants must be literals, declared above their first use, in the file that uses them; k-constants are per file. | Every constant is a literal; `kQrLibVersion` lives in `qrReader.lc` next to its only reader; the build refuses a combined stack in which any script-level name is referenced above its declaration. | STATIC | checker (checks 10, 11, 19), build (`_check_lexical_order`) |
| 7 | A `local` declared inside an `if`/`repeat` block breaks compilation of the whole script. | All handler locals are declared at block depth 0. | STATIC | lint (`check_nested_local`) |
| 8 | Script-level locals resolve by lexical position; concatenating modules can silently break scope. | The build checks lexical order over the concatenated text and refuses duplicate script-level declarations and handlers. | STATIC | build |
| 9 | An undeclared name evaluates to its own spelling; nothing tells you. | Lint flags writes to undeclared variables; under the model an undeclared reference is a hard error, which is how the `qr_` helper rename was proven complete. | STATIC + MODEL | lint, run_unit_tests.py |
| 10 | `itemDelimiter` / `lineDelimiter`: save, set, use, restore around the narrowest span; a library hands the host's delimiter back. | The public boundary (`qr_parseHints`) saves and restores; every internal handler sets the delimiter immediately before the chunk read that needs it, never assuming a caller's value. **See the note below: this repository's engine-passed suite contradicts the family's "global mutable state" observation.** | ENGINE (indirect, 9.6.11-class server, 2026-06-03) + MODEL | suite_reader ("parseHints restores the caller's itemDelimiter"); lint's for-each rule |
| 11 | `=` and `is` fold case by default; test reporters must compare byte-exact. | `t_eq`, `goldRow` and `synRow` set `the caseSensitive` (a handler-local property) and check byte lengths. The model implements the property (D22) and the reporter is mutation-checked (a case-folded near-miss fails). | MODEL | run_unit_tests.py HARNESS |
| 12 | An unqualified control reference resolves against the defaultStack; `create` opens the stack it makes. | `luminanceSource_decodeRawPlane` locks messages, creates or reuses a private invisible host stack, makes it the defaultStack, uses a fixed scratch image name, deletes the image and restores the defaultStack and `lockMessages` on every exit, throwing only after `end try`. `qr_imageprobe.lc` uses the same discipline. | DESIGN | none possible headlessly (D17); needs an OXT pass |
| 13 | There is no `folder` property of a stack. | Every install snippet (README, `lib/README.md`, the combined stack's header, both examples) derives the folder from `the effective filename of this stack`. | DESIGN (suite-observed idiom) | checker does not cover; reviewed by hand |
| 14 | `the handlers of stack` is not a property; readiness probes must use proven idioms. | `scanButton`'s `qrEnsureLibrary` tests `is among the lines of the stacksInUse` and then a cheap public call under `try`. | DESIGN | - |
| 15 | `textDecode(..., "UTF-8")` never throws on malformed input. | The bitstream parser does its own strict UTF-8 walk (`dbsp_utf8ToText`), guesses the charset the way ZXing does, and fails closed on an unknown ECI (`Format:`). | MODEL | suite_reader (charset and ECI assertions), verify_tables.py (ECI list) |
| 16 | `the number of keys of` and `does not contain` do not parse. | Not used; `the number of elements of` and `is not in` instead. | STATIC | checker (checks 13, 14) |
| 17 | Bitwise operators bind looser than `=`; write them in call or parenthesised form. | Every bitwise sub-expression is parenthesised. | STATIC | checker (check 16); ARCHITECTURE rule 2 |
| 18 | Shipped is not run: a comment's claim about engine behaviour is not evidence. | Every claim carries a label; the model's output says "not an engine pass" on every green run; `VERIFICATION.md` holds the dated record. | - | the runners' own trailers |
| 19 | A gate is not trusted until it is mutation-tested. | `tools/test_gates.py` seeds 15 defects and requires each gate to catch its own; `tools/test_model_mutations.py` seeds 10 library defects and requires the suites to go red; the corpus `--check` is itself mutation-checked. | STATIC | CI |
| 20 | Generated files are built, not written: `--check` in the gate set. | `lib/xtQRdecoder.livecodescript` (build `--check`) and `qr/fixtures/synthetic` (generator `--check`, pixel comparison) are both gated. | STATIC | CI |
| 21 | The oracle comes first; known-answer vectors are derived in a portable language and committed. | `tools/verify_tables.py` regenerates every table from ISO/IEC 18004 and ZXing's rows (5060 checks); the synthetic corpus comes from the Python `qrcode` encoder; `suite_reader`'s values are derived from ISO mode syntax, an independent GF(256) encoder and ZXing's rules. | MODEL | CI |
| 22 | A report needs its own completeness marker, per-section isolation and a harness version. | `qr_tester.lc`: every panel in its own `try`, "END OF REPORT - N panels ran of K registered", `kQrHarnessVersion`. `qr_synthetic.lc` has the same trailer. | DESIGN | - |
| 23 | Public-surface hygiene: every handler carries a library prefix so a host cannot shadow it. | The eleven unprefixed compat helpers became `qr_u32`, `qr_shl`, `qr_uShr`, `qr_aShr`, `qr_u8`, `qr_byteAt`, `qr_hashCode`, `qr_arraycopy`, `qr_floatToIntBits`, `qr_numberOfTrailingZeros`, `qr_fillArray`; the rest were already prefixed by module. | MODEL (bit-identical on 51 fixtures) | build (duplicate-handler check) |
| 24 | `repeat ... step` is ignored; stride by computing the index. | Not used. | STATIC | ARCHITECTURE rule 11 |
| 25 | Lookup tables and hoisted arithmetic instead of per-call powers in interpreted hot loops. | Per-module `sXXPow2` tables replace `2 ^ n`; word-level accumulation in the binarizers; the golden run executes half the statements it did (46.2M to 22.3M) with bit-identical output at every stage. | MODEL | equivalence harness (stage-by-stage, 51 images) |
| 26 | No side effects on the host app; fail closed on network input. | The demo's URL fetch is off unless `kDemoAllowUrlFetch` is `"on"`; uploads, data: URIs and fetches are capped by `kDemoMaxUploadBytes`; the URL tab is not rendered when fetching is off. | DESIGN | - |
| 27 | Own the lifecycle: idempotent teardown, free what you open, clean up on the throw path. | The scratch image is deleted on every path (a stale one is deleted before creation); the private host stack is kept deliberately as a cache and documented as such. | DESIGN | - |
| 28 | Version the harness and the library, and print both in every report. | `qrLibraryVersion()` returns `kQrLibVersion`; every report page prints it with the harness version and the engine version. | MODEL | suite_reader |

## Where this repository's evidence differs from the family notes

**Delimiter scope (family note 2.3).** The suite records, as OBSERVED on
OpenXTalk, that `the itemDelimiter` and `the lineDelimiter` are global
mutable state: a callee's `set` leaks back into its caller. This
repository's engine-passed unit suite requires the opposite on the build it
ran on. `version.lc`'s `ver_init` reads `item (3 + ord) of tRow` under the
delimiter `"~"` while its callee `ver_parseBlocks` sets `"/"`; under a
global, never-reset delimiter the version table for the M, Q and H ordinals
comes out corrupt and fifteen assertions that were green on the engine
(suite_tables v1-M, v1-H, v5-Q; every DataBlock row of suite_parser;
suite_detectorV2's decode) fail. So on that build (an xTalk server, 9.6.11
class, 2026-06-03) the properties behaved as LiveCode documents them:
handler-local. The headless model therefore models them handler-local
(`tools/MODEL.md` D21) and says so.

The code does not bet on either reading. Internal handlers set the
delimiter immediately before every chunk read that depends on it and never
rely on a caller's value; the public boundary saves and restores the
caller's delimiter explicitly. Under the family's OXT semantics that
restore is what protects the host; under the LiveCode semantics it is a
no-op. What remains open is which engines behave which way; an OXT pass of
`suite_reader`'s "parseHints restores the caller's itemDelimiter" assertion
plus a deliberately leaking probe would settle it for OpenXTalk, and the
result belongs in the family list with its build and date.

**Server-observed rules the family list may not have.** This repository's
`docs/ARCHITECTURE.md` section 4 carries rules that were paid for on the
9.6.11-class server build before the suite's list existed: bitwise
precedence below `=`, the bare `return` "missing factor" error, a
literal-times-literal product rejected as a `div` operand, `centers` and
`ac` as undocumented reserved words, and the delimiter being cached at
entry to `repeat for each`. They are offered as OBSERVED-on-server entries
with that build; none has been re-observed on OpenXTalk.

**The `<?lc` wrapper.** The suite's checker only looks at
`.livecodescript` and `.lcb`. Server files need the wrapper stripped and the
line numbers shifted by one; `tools/check_engine_rules.py` is that adapter
and may be worth folding into the family checker.
