# The headless execution model (`tools/lcs_model.py`)

`tools/lcs_model.py` runs the actual `qr/*.lc` text without an xTalk engine,
so `tools/run_unit_tests.py` (the 399 unit assertions) and
`tools/run_golden.py` (the five golden fixtures) can gate every commit.
Python 3.8+, standard library only.

## The honesty contract

* **It is a model of the engine, not the engine.** If it disagrees with a
  real xTalk engine, **the engine is right** and the model is the bug.
* **A green run here never promotes anything to engine-verified.** The
  honest label for a handler that has only passed here remains
  *"verified statically; needs an OXT pass"*. The engine pass recorded in the
  README (399/399 on a 9.6.11-class engine) is what makes the suites an
  oracle for the model, not the other way round.
* **It refuses rather than guesses.** Anything outside the subset below is a
  `ModelError` naming the handler, the source `file:line` and the construct;
  `compile_all()` compiles every non-overridden handler before a run so a
  refusal surfaces before any test executes.
* **Stricter than the engine is acceptable and every such divergence is
  named** (the D-list below). Looser is a bug.
* **The oracle rule for maintainers:** the suites are engine-passed, so a
  failing assertion under the model is a *model* bug until proven otherwise.
  Fix `lcs_model.py`; never edit the `.lc` sources or their expected values
  to make the model happy.

## What is modelled

The subset was derived by scanning all 30 library modules and 17 suites; it
is exactly what they use, plus a few operators that cost nothing to model
faithfully (`&&`, `contains`, `begins/ends with`, `is a number/integer`).

**Handlers.** `function` / `command` / `on`, optional `private`; parameters,
`@pName` by reference (subscript writes and whole-value assignment reach the
caller); by-value array arguments are copy-on-write - a handler copies a
by-value parameter on entry only if it writes it (assigns it, subscripts
into it, or passes it on by reference), decided statically. Missing
arguments read as empty. Names are case-insensitive. Handler `local`
(anywhere in the handler; hoisted), script-level `local` (shared by every
loaded source) and literal `constant`.

**Statements.** `put EXPR into|after|before TARGET` (targets: variables and
chained subscripts `tA[i][j]...`); `add`/`subtract`/`multiply`/`divide`;
`set the itemDelimiter|lineDelimiter to EXPR`; `get EXPR` (sets `it`); the
`get binaryDecode(fmt, data, outVar)` form; `if ... then` block form with
`else if`/`else`, and the single-line `if C then STMT`; `repeat with i = a to
b` / `down to` (bounds evaluated once, in-body assignment to the counter is
overwritten by the next iteration); `repeat while`; `repeat` / `repeat
forever`; `repeat for each item|line|word X in Y` (snapshot at loop entry);
`exit repeat`; `next repeat`; `exit HANDLER`; `return EXPR`; `throw EXPR`;
`try / catch VAR / end try`; `switch / case / default / break / end switch`
with fall-through; statement-position calls `name a, b` (zero-argument calls
bare).

**Expressions**, LiveCode precedence, highest to lowest: grouping; unary
`-` `not` `bitNot`; `^`; `*` `/` `div` `mod`; `+` `-`; `&` `&&`; `is a/an
integer|number`, `contains`, `is [not] in`, `is [not] among the
lines|items|words|keys of`, `begins with`, `ends with`, `<` `>` `<=` `>=`;
`=` `<>` `is` `is not`; `bitAnd`; `bitXor`; `bitOr`; `and`; `or`. The
bitwise operators bind looser than comparison on purpose: an unparenthesised
`x bitAnd 1 = 0` parses as `x bitAnd (1 = 0)` and then errors when bitAnd
meets a boolean - the engine's own trap, made visible.

**Values.** Numbers are doubles on the engine; here integral values are
Python ints and everything else floats. `/` is real division (6/3 -> 2);
`div` truncates toward zero; `mod` takes the sign of the dividend; `^` is
power; `bitAnd/bitOr/bitXor/bitNot` operate on unsigned 32-bit integers
(operands truncated toward zero then reduced mod 2^32; `bitNot 0` is
4294967295). Number -> text: integral values print without a decimal point,
others with up to 6 decimals and trailing zeros trimmed. Text -> number:
decimal literals with optional sign and exponent, surrounding whitespace
allowed. Empty is 0 in arithmetic. `=`/`is` compare numerically when both
operands are numeric, otherwise as case-insensitive text; `<` etc. likewise.
Booleans are `true`/`false`; `if`/`and`/`or`/`not` on anything else is an
error. Binary data is a string of code points 0..255 (byteToNum, numToByte,
byte chunks and `the number of bytes` are exact on it; textDecode works on
it). Arrays: string keys with numeric normalisation (1, 1.0 and "1" are one
key); a missing key reads as empty; subscripting an empty (non-array) value
reads as empty; `put empty into tArr` clears it; `the keys of` is one key per
line in insertion order; `the number of elements of` a non-array is 0.

**Chunks and counts.** `byte|char|item|line|word K of X` and `... A to B of
X` (1-based; negative counts from the end); `the number of
bytes|chars|characters|items|lines|words|elements of`; one trailing
delimiter is ignored when counting items/lines (OXT-ENGINE-NOTES 2.2).

**Constants.** `empty true false comma cr lf linefeed return crlf quote space
tab pi zero..ten`; `the result`, `it`, `the itemDelimiter`, `the
lineDelimiter`, `the milliseconds` (wall clock).

**Builtins.** `byteToNum numToByte numToCodepoint toUpper trunc round(x[,n])
abs sqrt min max textDecode(bytes, "UTF-8"|"ISO-8859-1"|"ASCII")
binaryEncode("f"|"i", x)` and `get binaryDecode("i"|"f", data, var)`.

## What is refused

Everything else, at compile time, including: any other `the ...` property;
`there is`; `send`, `dispatch`, `pass`, `global`, `delete`, `replace`,
`sort`, `create`, `answer`, `wait`, `do`; `repeat ... step` (the engine
ignores the step, OXT-ENGINE-NOTES 3.1), `repeat until`, `repeat N times`,
`repeat for each element|key`; `switch` with a `break` that is not the last
top-level statement of its case; `finally`; a bare `return`; a chained
`a ^ b ^ c`; `foo()` in statement position (3.3); a `function` called as a
statement or a `command` called as a function; extra call arguments; a
by-reference argument that is not a plain variable; `throw` lexically inside
`catch` (3.2); `else` after a single-line `if` (ARCHITECTURE.md rule 12);
smart quotes; loose top-level statements; duplicate handler or script-level
names; a handler-local that shadows a parameter, script-local or constant.
`url(...)` compiles but raises when it would execute (engine I/O).

The engine image-object path (`luminanceSource_decodeRawPlane`) is never
compiled: the host overrides it (`Model.override`), and `run_golden.py`
supplies a pure-Python PNG decoder that produces the engine's imageData
layout (4 bytes per pixel, `0,R,G,B`, row-major, alpha dropped, palette
expanded through the PLTE; colour types 0/2/3/4/6, bit depths 1..16,
non-interlaced).

## Named divergences from the engine

Stricter unless marked. The numbers match the docstring of `lcs_model.py`.

| # | Divergence |
|---|---|
| D1 | Reading or writing an undeclared name is a compile-time error. The engine silently evaluates it to its own literal name (OXT-ENGINE-NOTES 2.1). |
| D2 | An array in string/number context is an error (the engine folds it to empty). The one exception, from the family's engine evidence: comparing an array against `empty` answers false when it has keys and true when it has none. |
| D3 | `if`/`and`/`or`/`not` require a boolean (as on the engine); `and`/`or` short-circuit here. |
| D4 | Engine execution errors are not catchable: only an explicit `throw` reaches `catch`; a `ModelError` always propagates, so a model bug can never masquerade as a decoder "no result". |
| D5 | `throw` inside `catch` is refused (the engine swallows it, 3.2). |
| D6 | `repeat ... step`, `repeat until`, `repeat N times` and non-integral `repeat with` bounds are refused. |
| D7 | `foo()` in statement position, a function called as a statement, a command called as a function: refused. |
| D8 | Extra call arguments are refused; a `@` parameter must receive a plain variable and may not be omitted. |
| D9 | `else` after a single-line `if ... then stmt` is refused. |
| D10 | Ints are exact; `*` and `^` results outside +/-2^53 become floats (the engine's rounding), but `+`/`-` on huge ints stay exact. The corpus never overflows 2^53. |
| D11 | `the keys of` is insertion-ordered (the engine documents no order). |
| D12 | Numeric key normalisation: 1, 1.0, "1" are one key; "01", "1.0", " 1" stay distinct string keys (as on the engine). |
| D13 | `textDecode(..., "UTF-8")` substitutes U+FFFD for malformed input; only UTF-8, ISO-8859-1 and ASCII are modelled. |
| D14 | An element write into a variable holding a non-empty string is refused (the engine discards the string). |
| D15 | `byteToNum` of empty, `numToByte` outside 0..255, `numToCodepoint` outside Unicode, `byte` chunks of non-byte text, and arithmetic on a boolean or non-numeric text are errors. Empty is 0 in arithmetic, as on the engine. |
| D16 | `=`/`is` compare numerically when both sides are numeric, else as case-insensitive text (the engine default). The family model was case-sensitive; this corpus relies on folding. |
| D17 | No image object, no `url`; `the milliseconds` reads the wall clock. |
| D18 | `break` must be the last top-level statement of its case. |
| D19 | Script-level `local`s are visible everywhere regardless of lexical position (the engine resolves by position, 1.2; the corpus declares them at the top of each module). |
| D20 | `the result` is set only by a statement-position call to a user handler. |
| D21 | **`the itemDelimiter` / `the lineDelimiter` are handler-local**: each handler starts at the defaults and a callee's change never leaks back to its caller (LiveCode's documented "local property" rule). This is the one place the model knowingly departs from the family's OXT-ENGINE-NOTES 2.3 ("global mutable state"), because the ENGINE-PASSED corpus requires it: `version.lc`'s `ver_init` reads `item (3 + ord) of tRow` under `"~"` while its callee `ver_parseBlocks` sets `"/"`; under a global never-reset model the version table for the M/Q/H ordinals is corrupt and 15 engine-green assertions fail (suite_tables v1-M, v1-H, v5-Q; every DataBlock row of suite_parser; suite_detectorV2's decode). Within one handler the property is ordinary mutable state, and `repeat for each item|line` snapshots at loop entry (ARCHITECTURE.md rule 6). |
| D22 | **`the caseSensitive` is modelled like the delimiters (D21): handler-local**, false on entry to every handler, restored for the caller on exit - LiveCode's documented rule for this property too. While it is true, `=`, `<>`, `<`/`>`, `contains`, `is in`, `begins/ends with` and `is among` compare text byte-exactly; numeric comparisons are unaffected. Only the test reporters (`t_eq`, `goldRow`, `synRow`) set it, and no handler relies on a caller's value leaking in, so the family's 2.3 dispute does not touch it. |

Two further notes that are not divergences but should be read before
trusting a golden result:

* **Alpha.** `test.png` has 25,806 pixels with alpha < 255 (all RGB
  30,30,30 in the rotated photo's corners). The PNG decoder drops alpha and
  keeps the stored RGB; whether the engine's `imageData` premultiplies
  (which would make them black) is not known here. The fixture decodes under
  both readings, so the uncertainty is not load-bearing for the golden
  result, but it is real.
* **`repeat with` leaves the counter at its last value** here; the engine
  may leave it one past the bound. Nothing in the corpus reads a counter
  after its loop.

## Speed

Each handler is compiled once into Python source (`Model.python_source(name)`
shows it) with int fast paths on the arithmetic and comparison operators and
inline dictionary access for subscripts. Measured on the corpus:

* unit suites: 399 assertions, ~0.13 s, ~5 million statements/second
  (`--count`);
* golden: hello_world.png 0.16 s; 139225861-...png 1.1 s; test.png (776x640)
  ~3 s per API call, of which ~1.8 s is the pure-Python PNG unfilter.

## Using and extending it

```python
from lcs_model import Model, strip_server_tags
m = Model([("qrCompat.lc", strip_server_tags(text)), ...], overrides={"t_fail": fn})
m.override("luminanceSource_decodeRawPlane", my_png_decoder)
m.compile_all()                       # refuse anything outside the subset now
m.call("qrDecodeFromData", png_bytes_as_latin1_str, "TRY_HARDER")
m.get_local("sCurPass"); m.set_local("sCurPass", 0)
Model.eq(a, b); Model.to_text(v)      # the model's own `=` and text conversion
```

To add a builtin function: one entry in `_BUILTINS` (helper, arity, result
kind) plus the helper. To add a `the ...` property: `_ExprCompiler.parse_the`.
To add a statement: `_HandlerCompiler.parse_simple` (tokens -> `_Stmt`) and
`emit_stmt` (`_Stmt` -> Python lines). Every new construct must either be
modelled from documented/observed engine behaviour or refused; if it is
stricter than the engine, add a numbered entry to the D-list in both the
docstring and this file.
