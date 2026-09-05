#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Seth Morrow
# Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
"""
lcs_model.py - a headless EXECUTION MODEL for the LiveCodeScript subset that
the qr/*.lc modules and suites are written in. TEST TOOLING; nothing shipped
imports it.

WHY THIS EXISTS. There is no headless xTalk engine in CI. This lets the 399
unit assertions and the five golden fixtures run on every commit, against the
ACTUAL .lc text, so a transcription slip in the decoder is caught here rather
than in a scarce engine session.

THE HONESTY CONTRACT (adopted from the family's coinxt/tools/lcs-interp.py):

  * This is a MODEL of the engine, not the engine. If it disagrees with a real
    xTalk engine, THE ENGINE IS RIGHT and this file is the bug.
  * A green run here NEVER promotes anything to engine-verified. The honest
    label for a handler that has only passed here remains
    "verified statically; needs an OXT pass".
  * It REFUSES - raises ModelError naming the handler, the source file:line
    and the construct - anything outside the subset it implements, rather
    than guessing. A silent mis-parse is worse than no tool at all.
  * Being STRICTER than the engine is acceptable, and every such divergence
    is NAMED below. Being looser is a bug.

The subset is exactly what a scan of qr/*.lc (library modules + suite_*.lc)
uses; see tools/MODEL.md for the enumerated list. Everything else is refused
at compile time (or, for the two engine-I/O functions that parse as ordinary
calls, at the moment they would execute).

NAMED DIVERGENCES FROM THE ENGINE (stricter unless marked otherwise):

  D1  Undeclared names. The engine silently evaluates an undeclared name to
      the literal text of its own name (OXT-ENGINE-NOTES 2.1). Here ANY read
      or write of a name that is not a parameter, a handler `local`, a
      script-level `local` or a `constant` is a compile-time ModelError.
  D2  Arrays in string/number context. The engine folds an array to empty
      when it is used as a string or number. Here that is a ModelError, in
      every string/number context (concatenation, chunks, arithmetic, `if`).
      The ONE exception is comparison against empty, modelled from the
      family's engine evidence: `tArr is empty` / `tArr = empty` answers
      FALSE for an array with keys and TRUE for one with none; comparing an
      array with anything else non-empty, or two arrays, is a ModelError.
  D3  `if` / `and` / `or` / `not` require a boolean. The engine also errors
      ("expected true or false") on a non-boolean; this model does the same,
      and additionally `and`/`or` SHORT-CIRCUIT here (a non-boolean or a
      throwing right operand is not evaluated when the left decides). The
      corpus is written to be correct under either rule.
  D4  Engine execution errors are NOT catchable. On the engine a runtime
      error inside `try` is delivered to `catch`. Here only an explicit
      `throw` is catchable; a ModelError (a model refusal or a type error in
      the modelled semantics) always propagates, so a model bug can never be
      mistaken for a decoder "no result".
  D5  `throw` lexically inside a `catch` block is REFUSED at compile time.
      The engine swallows it (OXT-ENGINE-NOTES 3.2), which is a trap.
  D6  `repeat with ... step`, `repeat until`, `repeat N times`, and a
      `repeat with` whose bounds are not integral are refused. The engine
      ignores `step` (3.1); refusing is stricter than mis-honouring it.
  D7  A zero-argument call in STATEMENT position must be bare; `foo()` is
      refused (the engine rejects the whole file, 3.3). A `function` called
      in statement position, or a `command` called in expression position,
      is refused; the engine would fail to find the handler at run time.
  D8  Extra call arguments beyond the declared parameters are refused (the
      engine accepts them via `param()`). Missing arguments read as empty,
      as on the engine. A by-reference (@) parameter must receive a plain
      variable and may not be omitted.
  D9  `else` on the line after a single-line `if ... then stmt` is refused
      as a parse error (the engine binds it to the inline if and silently
      wrecks the block nest; ARCHITECTURE.md rule 12).
  D10 Integer precision. Numbers are doubles on the engine. Here integral
      values are Python ints; the results of `*` and `^` are converted to
      float when they leave the exact-double range [-2^53, 2^53] (matching
      the engine's rounding), but `+` and `-` on integers are exact at any
      size. Code that overflows 2^53 by addition would behave differently
      here (the corpus never does; qrCompat.shl is precision-safe by design).
  D11 `the keys of` returns keys in INSERTION order, one per line. The engine
      documents no order. A script relying on an order passes here and may
      misbehave on an engine (the corpus only tests membership).
  D12 A numeric array key is normalised so that 1, 1.0 and "1" are the same
      key, as on the engine. A key string that is not the canonical decimal
      form ("01", "1.0", " 1") stays a distinct string key, also as on the
      engine; this is stated because the model was checked against it.
  D13 textDecode(..., "UTF-8") replaces malformed sequences with U+FFFD
      rather than throwing (the family's modelled behaviour; the corpus does
      not call textDecode on malformed input). Only UTF-8, ISO-8859-1/Latin-1
      and ASCII are modelled; other charsets are refused.
  D14 Assigning an element of a variable that currently holds a NON-EMPTY
      string (`put 1 into t["a"]` when t is "abc") is refused. The engine
      silently discards the string and makes an array.
  D15 `byteToNum` of an empty string, `numToByte` outside 0..255,
      `numToCodepoint` outside the Unicode range, `byte` chunks of text with
      code points above 255, and the arithmetic operators on a boolean or a
      non-numeric non-empty string are all ModelErrors (the engine variously
      errors, yields empty, or yields 0). Empty IS treated as 0 by the
      arithmetic operators and by add/subtract, as on the engine.
  D16 `=` / `is` / `<>` / `is not` compare numerically when BOTH operands
      are numbers (a number, or text that parses as a decimal number), and
      otherwise as CASE-INSENSITIVE text, which is the engine's default
      (`the caseSensitive` is false). The family model was case-sensitive;
      this one is not, because the corpus compares "true"/"false" and mode
      names produced by its own code and the engine folds case there.
  D17 The engine's `imageData` is not modelled at all: the one handler that
      touches an image object (luminanceSource_decodeRawPlane) is meant to be
      overridden by the host (tools/run_golden.py supplies a PNG decoder) and
      is never compiled. `url(...)` and `the milliseconds` are engine I/O:
      `url` raises a ModelError when it would execute; `the milliseconds`
      reads the wall clock.
  D18 `switch`: `break` must be the LAST statement of its case body, at the
      top level of that body (not nested in an `if`). Any other placement is
      refused; the corpus only uses the tail form. Fall-through between
      adjacent cases and into `default` is modelled.
  D19 Script-level `local`s are visible to every handler in every loaded
      source, regardless of lexical position. The engine resolves them by
      lexical position (OXT-ENGINE-NOTES 1.2); the corpus declares them at
      the top of each module, where the two rules agree, and the combined
      build validator holds the uniqueness discipline.
  D20 `the result` is set by a statement-position call to a user handler
      (the value it returned, or empty). Nothing else sets it here.
  D21 `the itemDelimiter` / `the lineDelimiter` are HANDLER-LOCAL: every
      handler invocation starts at the defaults ("," and LF) and a change
      dies with the handler, so a caller's value is untouched by a callee.
      This is LiveCode's documented "local property" rule and it is what the
      ENGINE-PASSED corpus requires: version.lc's ver_init reads
      `item (3 + ord) of tRow` under "~" while its callee ver_parseBlocks
      sets "/" - under a global never-reset model the version table for
      ordinals M/Q/H comes out corrupt and 15 engine-green assertions fail
      (suite_tables v1-M/v1-H/v5-Q, all of suite_parser's DataBlock rows,
      suite_detectorV2's decode). The family's OXT-ENGINE-NOTES 2.3 records
      the opposite ("global mutable state") as OBSERVED; that observation
      is not reproduced by this corpus on a 9.6.11-class engine and is the
      one place this model knowingly departs from the family notes. Within
      ONE handler the property is still ordinary mutable state, and a
      `repeat for each item|line` snapshots its list at loop entry
      (ARCHITECTURE.md rule 6).

WHAT IS MODELLED (summary; MODEL.md has the full list). Handlers
(function/command/on, optional private, @ by-reference parameters with
copy-on-write by-value arrays); handler and script `local`; literal
`constant`; put into/after/before with chained subscripts; add/subtract/
multiply/divide; set the itemDelimiter/lineDelimiter (handler-local, D21);
get; if/else if/else in block and single-line form; repeat
with/down to/while/forever/for each item|line; exit repeat/next repeat/exit
handler/return/throw; try/catch; switch/case/default/break; statement-position
handler calls; the full LiveCode operator precedence (bitwise operators bind
LOOSER than comparison, so `x bitAnd 1 = 0` parses as `x bitAnd (1 = 0)` and
then errors, exactly as on the engine); unsigned 32-bit bitAnd/bitOr/bitXor/
bitNot; div (truncating) and mod (sign of the dividend); chunk expressions
byte/char/item/line/word (1-based, one trailing delimiter ignored in counts,
OXT-ENGINE-NOTES 2.2); the number of elements/bytes/chars/items/lines/words
of; the keys of; is among the lines/items/words/keys of; is in; is an
integer/a number; and the builtins byteToNum, numToByte, numToCodepoint,
toUpper, trunc, round (half away from zero), abs, sqrt, min, max, textDecode,
binaryEncode/binaryDecode for the "f"/"i" formats used by floatToIntBits.

SPEED. Every handler is compiled ONCE into Python source and exec'd; the
per-statement cost is a few hundred nanoseconds to a few microseconds. The
generated source can be inspected with Model.python_source(name).

Python 3.8+, standard library only.
"""
import math
import re
import struct
import time

__all__ = ["Model", "ModelError", "LCThrow"]

_TWO53 = 9007199254740992
_U32MOD = 4294967296


class LCThrow(Exception):
    """A LiveCodeScript `throw` - the ONLY thing `catch` catches (D4)."""

    def __init__(self, value):
        self.value = value
        Exception.__init__(self, value)


class ModelError(Exception):
    """A refusal or a modelled type error. Never caught by `catch` (D4).
    Carries the handler / file:line trail it passed through."""

    def __init__(self, msg, frames=None):
        self.msg = msg
        self.frames = list(frames or [])
        Exception.__init__(self, msg)

    def add_frame(self, handler, srcfile, line):
        self.frames.append((handler, srcfile, line))

    def __str__(self):
        out = self.msg
        if self.frames:
            out += "\n  trail (innermost first):"
            for h, f, ln in self.frames:
                out += "\n    in %s (%s:%s)" % (h, f, ln)
        return out


class _State(object):
    """The engine's global mutable state that the corpus touches."""
    __slots__ = ("itemdel", "linedel", "result", "nstmt")

    def __init__(self):
        self.itemdel = ","
        self.linedel = "\n"
        self.result = ""
        self.nstmt = 0


# ---------------------------------------------------------------- numbers --

_NUM_RE = re.compile(r"^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$")


def _parse_num(s):
    """Text -> number, or None when the text is not a decimal number."""
    t = s.strip()
    if not t or not _NUM_RE.match(t):
        return None
    try:
        if "." in t or "e" in t or "E" in t:
            f = float(t)
            if f.is_integer() and abs(f) <= _TWO53:
                return int(f)
            return f
        return int(t)
    except ValueError:
        return None


def _num(v):
    """Coerce to a number for arithmetic: empty is 0 (as on the engine);
    a boolean, an array or non-numeric text is an error (D15)."""
    c = v.__class__
    if c is int or c is float:
        return v
    if c is str:
        if v == "":
            return 0
        n = _parse_num(v)
        if n is None:
            raise ModelError("expected a number, got the text %r" % _clip(v))
        return n
    if c is bool:
        raise ModelError("expected a number, got the boolean %s" % v)
    if c is dict:
        raise ModelError("expected a number, got an array (D2)")
    raise ModelError("expected a number, got %r" % (v,))


def _norm(r):
    """Normalise an arithmetic result: integral floats within the exact
    range become ints; huge ints become floats (the engine's doubles, D10)."""
    c = r.__class__
    if c is float:
        if r.is_integer() and -_TWO53 <= r <= _TWO53:
            return int(r)
        return r
    if c is int and not -_TWO53 <= r <= _TWO53:
        return float(r)
    return r


def _clip(s):
    s = str(s)
    return s if len(s) <= 60 else s[:57] + "..."


def _str(v):
    """Value -> text. Numbers print the engine way (integral: no point;
    else up to 6 decimals, trailing zeros trimmed). Arrays refuse (D2)."""
    c = v.__class__
    if c is str:
        return v
    if c is int:
        return str(v)
    if c is bool:
        return "true" if v else "false"
    if c is float:
        if v.is_integer():
            if abs(v) < 1e21:
                return str(int(v))
            return "%.0f" % v
        t = "%.6f" % v
        t = t.rstrip("0").rstrip(".")
        if t in ("-0", ""):
            return "0"
        return t
    if c is dict:
        raise ModelError("an array has no text value (D2); index it or use its keys")
    raise ModelError("cannot convert %r to text" % (v,))


def _truth(v):
    if v.__class__ is bool:
        return v
    if v.__class__ is str:
        low = v.lower()
        if low == "true":
            return True
        if low == "false":
            return False
    if v.__class__ is dict:
        raise ModelError("expected true or false, got an array (D2)")
    raise ModelError("expected true or false, got %r" % (_clip(_str(v)),))


# ------------------------------------------------------------- arithmetic --

def _add(a, b):
    return _norm(_num(a) + _num(b))


def _sub(a, b):
    return _norm(_num(a) - _num(b))


def _mul(a, b):
    if a.__class__ is int and b.__class__ is int:
        r = a * b
        return r if -_TWO53 <= r <= _TWO53 else float(r)
    return _norm(_num(a) * _num(b))


def _truediv(a, b):
    a = _num(a)
    b = _num(b)
    if b == 0:
        raise ModelError("division by zero")
    return _norm(a / b)


def _div(a, b):
    """`div`: integer division truncating toward zero."""
    a = _num(a)
    b = _num(b)
    if b == 0:
        raise ModelError("division by zero (div)")
    if a.__class__ is int and b.__class__ is int:
        q = abs(a) // abs(b)
        return q if (a >= 0) == (b >= 0) else -q
    return _norm(float(math.trunc(a / b)))


def _mod(a, b):
    """`mod`: remainder with the sign of the dividend (fmod)."""
    a = _num(a)
    b = _num(b)
    if b == 0:
        raise ModelError("division by zero (mod)")
    if a.__class__ is int and b.__class__ is int:
        r = abs(a) % abs(b)
        return -r if a < 0 else r
    return _norm(math.fmod(a, b))


def _pow(a, b):
    if a.__class__ is int and b.__class__ is int and 0 <= b <= 64:
        r = a ** b
        return r if -_TWO53 <= r <= _TWO53 else float(r)
    a = _num(a)
    b = _num(b)
    try:
        r = a ** b
    except (OverflowError, ZeroDivisionError) as e:
        raise ModelError("cannot raise %s to %s: %s" % (a, b, e))
    if r.__class__ is complex:
        raise ModelError("complex result of ^")
    return _norm(r)


def _neg(a):
    return _norm(-_num(a))


def _u32(v):
    """Operand of a bitwise operator: an UNSIGNED 32-bit integer
    (truncate toward zero, reduce mod 2^32). Booleans are an error, which
    is what makes the engine's `x bitAnd 1 = 0` misparse visible."""
    c = v.__class__
    if c is int:
        return v % _U32MOD
    if c is bool:
        raise ModelError("bitwise operator applied to a boolean "
                         "(hint: `x bitAnd 1 = 0` parses as `x bitAnd (1 = 0)`; "
                         "parenthesise the bitwise sub-expression)")
    n = _num(v)
    if n.__class__ is float:
        n = int(math.trunc(n))
    return n % _U32MOD


def _band(a, b):
    return _u32(a) & _u32(b)


def _bor(a, b):
    return _u32(a) | _u32(b)


def _bxor(a, b):
    return _u32(a) ^ _u32(b)


def _bnot(a):
    return (~_u32(a)) % _U32MOD


# ------------------------------------------------------------- comparison --

def _isnum(v):
    c = v.__class__
    return c is int or c is float


def _eq(a, b):
    """`=` / `is` (D16, D2)."""
    ca = a.__class__
    cb = b.__class__
    if ca is int and cb is int:
        return a == b
    if (ca is int or ca is float) and (cb is int or cb is float):
        return a == b
    if ca is dict or cb is dict:
        return _eq_array(a, b)
    if ca is bool:
        a = "true" if a else "false"
        ca = str
    if cb is bool:
        b = "true" if b else "false"
        cb = str
    if ca is str and cb is str:
        na = _parse_num(a)
        if na is not None:
            nb = _parse_num(b)
            if nb is not None:
                return na == nb
        return a.lower() == b.lower()
    # one number, one text
    if ca is str:
        na = _parse_num(a)
        if na is not None:
            return na == b
        return a.lower() == _str(b).lower()
    nb = _parse_num(b)
    if nb is not None:
        return a == nb
    return _str(a).lower() == b.lower()


def _eq_array(a, b):
    if a.__class__ is dict and b.__class__ is dict:
        raise ModelError("comparing two arrays with = / is (D2)")
    arr, other = (a, b) if a.__class__ is dict else (b, a)
    if other.__class__ is str and other == "":
        return len(arr) == 0
    raise ModelError("comparing an array with a non-empty value (D2)")


def _ne(a, b):
    return not _eq(a, b)


def _cmp_pair(a, b):
    """Return (x, y) ready for </>: both numbers, or both folded strings."""
    ca = a.__class__
    cb = b.__class__
    if ca is dict or cb is dict:
        raise ModelError("ordering comparison with an array (D2)")
    if ca is bool:
        a = "true" if a else "false"
        ca = str
    if cb is bool:
        b = "true" if b else "false"
        cb = str
    if ca is str:
        na = _parse_num(a)
    else:
        na = a
    if cb is str:
        nb = _parse_num(b)
    else:
        nb = b
    if na is not None and nb is not None:
        return na, nb
    return _str(a).lower(), _str(b).lower()


def _lt(a, b):
    x, y = _cmp_pair(a, b)
    return x < y


def _le(a, b):
    x, y = _cmp_pair(a, b)
    return x <= y


def _gt(a, b):
    x, y = _cmp_pair(a, b)
    return x > y


def _ge(a, b):
    x, y = _cmp_pair(a, b)
    return x >= y


def _is_in(needle, hay):
    return _str(needle).lower() in _str(hay).lower()


def _contains(hay, needle):
    return _str(needle).lower() in _str(hay).lower()


def _begins_with(s, prefix):
    return _str(s).lower().startswith(_str(prefix).lower())


def _ends_with(s, suffix):
    return _str(s).lower().endswith(_str(suffix).lower())


def _is_integer(v):
    if v.__class__ is dict or v.__class__ is bool:
        return False
    if v.__class__ is int:
        return True
    if v.__class__ is float:
        return v.is_integer()
    n = _parse_num(v)
    return n is not None and (n.__class__ is int or n.is_integer())


def _is_number(v):
    if v.__class__ is dict or v.__class__ is bool:
        return False
    if v.__class__ is int or v.__class__ is float:
        return True
    return _parse_num(v) is not None


# ----------------------------------------------------------------- arrays --

def _key(v):
    """Array-key normalisation (D12): int stays; canonical integer text
    becomes int; integral float becomes int; other values -> their text."""
    c = v.__class__
    if c is int:
        return v
    if c is str:
        if v and (v.isdigit() or (v[0] == "-" and v[1:].isdigit())):
            if v == "0" or (v[0] != "0" and not v.startswith("-0")):
                return int(v)
            if v.startswith("-") and len(v) > 1 and v[1] != "0":
                return int(v)
        return v
    if c is float:
        if v.is_integer() and abs(v) <= _TWO53:
            return int(v)
        return _str(v)
    if c is bool:
        return "true" if v else "false"
    raise ModelError("an array cannot be used as a key (D2)")


def _copy(v):
    """xTalk arrays are VALUES: every assignment copies."""
    return {k: (_copy(x) if x.__class__ is dict else x) for k, x in v.items()}


def _get_nonarr(root, k):
    """Subscript read on a non-array: empty reads as empty (the corpus relies
    on `pHints["X"]` with pHints empty); anything else is refused."""
    if root == "" or root is None:
        return ""
    raise ModelError("subscript read on a non-array value %r" % (_clip(_str(root)),))


def _get2(root, k1, k2):
    if root.__class__ is not dict:
        return _get_nonarr(root, k1)
    d = root.get(k1, "")
    if d.__class__ is not dict:
        return _get_nonarr(d, k2)
    return d.get(k2, "")


def _get1(root, k):
    if root.__class__ is dict:
        return root.get(k, "")
    return _get_nonarr(root, k)


def _getn(root, keys):
    v = root
    for k in keys:
        v = _get1(v, k)
    return v


def _newarr(cur):
    """Become an array for an element write (D14)."""
    if cur.__class__ is dict:
        return cur
    if cur is None or cur == "":
        return {}
    raise ModelError("element write into a variable holding the non-array value %r (D14)"
                     % (_clip(_str(cur)),))


def _setn(root, keys, value):
    """Write value at root[k1][k2]...; returns the (possibly new) root."""
    root = _newarr(root)
    d = root
    for k in keys[:-1]:
        nxt = d.get(k)
        if nxt.__class__ is not dict:
            nxt = d[k] = _newarr(nxt)
        d = nxt
    d[keys[-1]] = value
    return root


def _count_elements(v):
    return len(v) if v.__class__ is dict else 0


def _keys(v):
    if v.__class__ is not dict:
        return ""
    return "\n".join(_str(k) for k in v)


# ----------------------------------------------------------------- chunks --

def _split(s, d):
    """Chunk split: ONE trailing delimiter is ignored (OXT-ENGINE-NOTES 2.2);
    empty text has no chunks."""
    if s == "":
        return []
    if d == "":
        raise ModelError("empty delimiter")
    if s.endswith(d):
        s = s[:-len(d)]
    return s.split(d)


def _idx(k):
    """1-based chunk index -> int (negative counts from the end)."""
    n = _num(k)
    if n.__class__ is float:
        if not n.is_integer():
            raise ModelError("chunk index %r is not an integer" % (n,))
        n = int(n)
    return n


def _pick(parts, k, d):
    n = len(parts)
    if k < 0:
        k = n + 1 + k
    if 1 <= k <= n:
        return parts[k - 1]
    return ""


def _pick_range(parts, a, b, d):
    n = len(parts)
    if a < 0:
        a = n + 1 + a
    if b < 0:
        b = n + 1 + b
    if a < 1:
        a = 1
    if b > n:
        b = n
    if b < a:
        return ""
    return d.join(parts[a - 1:b])


def _text_for_bytes(v):
    s = _str(v)
    for ch in s:
        if ord(ch) > 255:
            raise ModelError("byte chunk of text containing the non-byte code point U+%04X (D15)" % ord(ch))
    return s


def _byte1(s, k):
    s = _text_for_bytes(s)
    k = _idx(k)
    n = len(s)
    if k < 0:
        k = n + 1 + k
    if 1 <= k <= n:
        return s[k - 1]
    return ""


def _byte_range(s, a, b):
    s = _text_for_bytes(s)
    a = _idx(a)
    b = _idx(b)
    n = len(s)
    if a < 0:
        a = n + 1 + a
    if b < 0:
        b = n + 1 + b
    if a < 1:
        a = 1
    if b < a:
        return ""
    return s[a - 1:b]


def _char1(s, k):
    s = _str(s)
    k = _idx(k)
    n = len(s)
    if k < 0:
        k = n + 1 + k
    if 1 <= k <= n:
        return s[k - 1]
    return ""


def _char_range(s, a, b):
    s = _str(s)
    a = _idx(a)
    b = _idx(b)
    n = len(s)
    if a < 0:
        a = n + 1 + a
    if b < 0:
        b = n + 1 + b
    if a < 1:
        a = 1
    if b < a:
        return ""
    return s[a - 1:b]


def _bytetonum_at(s, k):
    """Peephole for byteToNum(byte K of S): one bounds-checked read."""
    if s.__class__ is not str:
        s = _str(s)
    if k.__class__ is not int:
        k = _idx(k)
    n = len(s)
    if k < 0:
        k = n + 1 + k
    if 1 <= k <= n:
        o = ord(s[k - 1])
        if o > 255:
            raise ModelError("byteToNum of the non-byte code point U+%04X (D15)" % o)
        return o
    raise ModelError("byteToNum of byte %d of a %d-byte value (out of range, D15)" % (k, n))


def _count_bytes(s):
    return len(_text_for_bytes(s))


def _count_chars(s):
    return len(_str(s))


def _words(s):
    return _str(s).split()


# ------------------------------------------------------------- builtins --

def _bytetonum(v):
    s = _str(v)
    if s == "":
        raise ModelError("byteToNum of empty (D15)")
    o = ord(s[0])
    if o > 255:
        raise ModelError("byteToNum of the non-byte code point U+%04X (D15)" % o)
    return o


def _numtobyte(v):
    n = _num(v)
    if n.__class__ is float:
        if not n.is_integer():
            raise ModelError("numToByte of the non-integer %r (D15)" % n)
        n = int(n)
    if not 0 <= n <= 255:
        raise ModelError("numToByte of %d (outside 0..255, D15)" % n)
    return chr(n)


def _numtocodepoint(v):
    n = _num(v)
    if n.__class__ is float:
        if not n.is_integer():
            raise ModelError("numToCodepoint of the non-integer %r" % n)
        n = int(n)
    if not 0 <= n <= 0x10FFFF:
        raise ModelError("numToCodepoint of %d (outside the Unicode range, D15)" % n)
    return chr(n)


def _toupper(v):
    return _str(v).upper()


def _trunc(v):
    n = _num(v)
    return int(math.trunc(n))


def _round(v, places=0):
    n = _num(v)
    p = _num(places)
    if p.__class__ is float:
        if not p.is_integer():
            raise ModelError("round: places must be an integer")
        p = int(p)
    scale = 10 ** p if p >= 0 else 1
    x = abs(n) * scale
    r = math.floor(x + 0.5)
    r = r / scale if p > 0 else r
    if n < 0:
        r = -r
    return _norm(float(r))


def _abs(v):
    return _norm(abs(_num(v)))


def _sqrt(v):
    n = _num(v)
    if n < 0:
        raise ModelError("sqrt of a negative number")
    return _norm(math.sqrt(n))


def _min(*args):
    if not args:
        raise ModelError("min() needs an argument")
    return _norm(min(_num(a) for a in args))


def _max(*args):
    if not args:
        raise ModelError("max() needs an argument")
    return _norm(max(_num(a) for a in args))


def _textdecode(data, enc="utf-8"):
    e = _str(enc).lower().replace("_", "-")
    b = _text_for_bytes(data).encode("latin-1")
    if e in ("utf-8", "utf8"):
        return b.decode("utf-8", errors="replace")
    if e in ("iso-8859-1", "latin1", "latin-1", "iso8859-1"):
        return b.decode("latin-1")
    if e in ("ascii", "us-ascii"):
        return b.decode("ascii", errors="replace")
    raise ModelError("textDecode: charset %r is not modelled (D13)" % e)


def _binaryencode(fmt, *args):
    f = _str(fmt)
    if f == "f" and len(args) == 1:
        return struct.pack("<f", float(_num(args[0]))).decode("latin-1")
    if f == "i" and len(args) == 1:
        return struct.pack("<i", int(_num(args[0]))).decode("latin-1")
    raise ModelError("binaryEncode format %r is not modelled" % f)


def _binarydecode(fmt, data, nvars):
    """Returns (count, [values...]) for the caller to store into its
    output variables (get binaryDecode(fmt, data, var) form)."""
    f = _str(fmt)
    b = _text_for_bytes(data).encode("latin-1")
    if f == "i" and nvars == 1:
        if len(b) < 4:
            return 0, [""]
        return 1, [struct.unpack("<i", b[:4])[0]]
    if f == "f" and nvars == 1:
        if len(b) < 4:
            return 0, [""]
        return 1, [_norm(struct.unpack("<f", b[:4])[0])]
    raise ModelError("binaryDecode format %r with %d output variables is not modelled" % (f, nvars))


def _url(*args):
    raise ModelError("url(...) is engine I/O and is not modelled (D17)")


def _ms():
    return int(time.time() * 1000)


# name -> (python helper name, min args, max args, result kind)
_BUILTINS = {
    "bytetonum": ("_bytetonum", 1, 1, "int"),
    "numtobyte": ("_numtobyte", 1, 1, "str"),
    "numtocodepoint": ("_numtocodepoint", 1, 1, "str"),
    "toupper": ("_toupper", 1, 1, "str"),
    "trunc": ("_trunc", 1, 1, "int"),
    "round": ("_round", 1, 2, "num"),
    "abs": ("_abs", 1, 1, "num"),
    "sqrt": ("_sqrt", 1, 1, "num"),
    "min": ("_min", 1, 64, "num"),
    "max": ("_max", 1, 64, "num"),
    "textdecode": ("_textdecode", 1, 2, "str"),
    "binaryencode": ("_binaryencode", 2, 2, "str"),
    "url": ("_url", 1, 1, "any"),
}

_CONSTANTS = {
    "empty": "", "true": True, "false": False, "comma": ",", "cr": "\n",
    "lf": "\n", "linefeed": "\n", "return": "\n", "crlf": "\r\n",
    "quote": '"', "space": " ", "tab": "\t", "pi": 3.14159265358979323846,
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
}

_RUNTIME = {
    "ModelError": ModelError, "_LCThrow": LCThrow, "_num": _num, "_str": _str,
    "_truth": _truth, "_add": _add, "_sub": _sub, "_mul": _mul,
    "_truediv": _truediv, "_div": _div, "_mod": _mod, "_pow": _pow,
    "_neg": _neg, "_u32": _u32, "_band": _band, "_bor": _bor, "_bxor": _bxor,
    "_bnot": _bnot, "_eq": _eq, "_ne": _ne, "_lt": _lt, "_le": _le,
    "_gt": _gt, "_ge": _ge, "_is_in": _is_in, "_contains": _contains,
    "_begins_with": _begins_with, "_ends_with": _ends_with,
    "_is_integer": _is_integer, "_is_number": _is_number, "_key": _key,
    "_copy": _copy, "_get1": _get1, "_get2": _get2, "_getn": _getn,
    "_get_nonarr": _get_nonarr, "_newarr": _newarr, "_setn": _setn,
    "_count_elements": _count_elements, "_keys": _keys, "_split": _split,
    "_idx": _idx, "_pick": _pick, "_pick_range": _pick_range,
    "_byte1": _byte1, "_byte_range": _byte_range, "_char1": _char1,
    "_char_range": _char_range, "_bytetonum_at": _bytetonum_at,
    "_count_bytes": _count_bytes, "_count_chars": _count_chars,
    "_words": _words, "_bytetonum": _bytetonum, "_numtobyte": _numtobyte,
    "_numtocodepoint": _numtocodepoint, "_toupper": _toupper,
    "_trunc": _trunc, "_round": _round, "_abs": _abs, "_sqrt": _sqrt,
    "_min": _min, "_max": _max, "_textdecode": _textdecode,
    "_binaryencode": _binaryencode, "_binarydecode": _binarydecode,
    "_url": _url, "_ms": _ms, "_norm": _norm,
}


# =============================================================== tokenizer --

_TOKEN_RE = re.compile(r"""
    (?P<ws>[ \t]+) |
    (?P<str>"[^"]*") |
    (?P<num>(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?) |
    (?P<id>[A-Za-z_][A-Za-z_0-9]*) |
    (?P<op><>|<=|>=|&&|[-+*/^&=<>(),\[\]@]) |
    (?P<bad>.)
""", re.X)


class Tok(object):
    __slots__ = ("kind", "val", "low", "pos")

    def __init__(self, kind, val, pos):
        self.kind = kind          # 'str' 'num' 'id' 'op' 'end'
        self.val = val
        self.low = val.lower() if kind == "id" else val
        self.pos = pos

    def __repr__(self):
        return "%s:%r" % (self.kind, self.val)


def _tokenize(text, where):
    toks = []
    for m in _TOKEN_RE.finditer(text):
        k = m.lastgroup
        if k == "ws":
            continue
        if k == "bad":
            raise ModelError("%s: cannot tokenize %r in: %s" % (where, m.group(0), text.strip()))
        toks.append(Tok(k, m.group(0), m.start()))
    toks.append(Tok("end", "", len(text)))
    return toks


def _strip_comment(raw):
    """Remove a `--` comment outside string literals."""
    i = 0
    n = len(raw)
    instr = False
    while i < n:
        c = raw[i]
        if c == '"':
            instr = not instr
        elif not instr and c == "-" and raw.startswith("--", i):
            return raw[:i]
        i += 1
    return raw


def _prepare_lines(text, srcname):
    """Comment-stripped, continuation-joined logical lines as
    (first_physical_lineno, text)."""
    out = []
    buf = ""
    start = None
    for i, raw in enumerate(text.split("\n"), 1):
        if raw.endswith("\r"):
            raw = raw[:-1]
        if any(ch in raw for ch in "\u201c\u201d\u2018\u2019"):
            raise ModelError("%s:%d: smart quote in source (the engine refuses these, "
                             "OXT-ENGINE-NOTES 1.4)" % (srcname, i))
        ln = _strip_comment(raw).rstrip()
        if ln.endswith("\\"):
            if start is None:
                start = i
            buf += ln[:-1] + " "
            continue
        if start is None:
            start = i
        out.append((start, (buf + ln).strip()))
        buf = ""
        start = None
    if buf:
        raise ModelError("%s: continuation at end of file" % srcname)
    return out


# ------------------------------------------------------------ keyword sets --

# infix / structural words that can never be variable names in this subset
_RESERVED = set("""
the empty true false comma cr lf linefeed return crlf quote space tab pi
zero one two three four five six seven eight nine ten
not bitnot bitand bitor bitxor and or is div mod contains begins ends in among
byte bytes char chars character characters item items line lines word words
element elements keys number of to into after before with from by then else
if end repeat while until forever each down step exit next switch case default
break try catch finally throw put add subtract multiply divide set get local
constant global function command on private pass send dispatch delete replace
result there it me this stack card field button image
""".split())

_CHUNK_UNITS = {"byte": "byte", "bytes": "byte", "char": "char", "chars": "char",
                "character": "char", "characters": "char", "item": "item",
                "items": "item", "line": "line", "lines": "line", "word": "word",
                "words": "word"}

_COUNT_UNITS = {"elements": "_count_elements", "element": "_count_elements",
                "bytes": "_count_bytes", "byte": "_count_bytes",
                "chars": "_count_chars", "char": "_count_chars",
                "characters": "_count_chars", "character": "_count_chars",
                "items": "items", "item": "items", "lines": "lines", "line": "lines",
                "words": "words", "word": "words"}

# precedence (higher binds tighter)
_P_OR, _P_AND, _P_BOR, _P_BXOR, _P_BAND, _P_EQ, _P_CMP, _P_CAT, _P_ADD, _P_MUL, _P_POW, _P_UNARY = range(1, 13)


def _is_simple(code):
    """A code fragment that can be re-evaluated for free (a name or literal)."""
    return re.match(r"^(?:[A-Za-z_][A-Za-z_0-9]*|-?\d+(?:\.\d+)?|\"[^\"]*\"|'[^']*'|True|False)$", code) is not None


class _ExprCompiler(object):
    """Recursive-descent expression compiler: tokens -> (python_code, kind).
    kind in {'int','num','bool','str','any'} is a STATIC guess used only to
    skip runtime checks that would be no-ops (a comparison is always a
    boolean; a literal int is always an int). Everything else is checked at
    run time."""

    def __init__(self, hc, toks, i=0):
        self.hc = hc            # the handler compiler (scope + model)
        self.toks = toks
        self.i = i

    # -- token helpers
    def peek(self, k=0):
        j = self.i + k
        return self.toks[j] if j < len(self.toks) else self.toks[-1]

    def at_end(self):
        return self.peek().kind == "end"

    def take(self):
        t = self.toks[self.i]
        if t.kind != "end":
            self.i += 1
        return t

    def is_id(self, *words, **kw):
        k = kw.get("k", 0)
        t = self.peek(k)
        return t.kind == "id" and t.low in words

    def is_op(self, *ops, **kw):
        k = kw.get("k", 0)
        t = self.peek(k)
        return t.kind == "op" and t.val in ops

    def expect_id(self, word):
        t = self.take()
        if not (t.kind == "id" and t.low == word):
            self.fail("expected `%s`, found %r" % (word, t.val))
        return t

    def expect_op(self, op):
        t = self.take()
        if not (t.kind == "op" and t.val == op):
            self.fail("expected `%s`, found %r" % (op, t.val or "end of statement"))
        return t

    def fail(self, msg):
        self.hc.fail(msg)

    def tmp(self):
        return self.hc.tmp()

    # -- entry points
    def parse_full(self):
        code, kind = self.parse_expr(0)
        if not self.at_end():
            self.fail("unexpected %r after the expression" % self.peek().val)
        return code, kind

    # -- infix detection
    def peek_infix(self):
        """-> (opname, prec, ntokens) or None. Does not consume."""
        t = self.peek()
        if t.kind == "op":
            v = t.val
            if v in ("=",):
                return ("eq", _P_EQ, 1)
            if v == "<>":
                return ("ne", _P_EQ, 1)
            if v in ("<", ">", "<=", ">="):
                return ({"<": "lt", ">": "gt", "<=": "le", ">=": "ge"}[v], _P_CMP, 1)
            if v == "&":
                return ("cat", _P_CAT, 1)
            if v == "&&":
                return ("catsp", _P_CAT, 1)
            if v == "+":
                return ("add", _P_ADD, 1)
            if v == "-":
                return ("sub", _P_ADD, 1)
            if v == "*":
                return ("mul", _P_MUL, 1)
            if v == "/":
                return ("truediv", _P_MUL, 1)
            if v == "^":
                return ("pow", _P_POW, 1)
            return None
        if t.kind != "id":
            return None
        w = t.low
        if w == "or":
            return ("or", _P_OR, 1)
        if w == "and":
            return ("and", _P_AND, 1)
        if w == "bitor":
            return ("bor", _P_BOR, 1)
        if w == "bitxor":
            return ("bxor", _P_BXOR, 1)
        if w == "bitand":
            return ("band", _P_BAND, 1)
        if w == "div":
            return ("div", _P_MUL, 1)
        if w == "mod":
            return ("mod", _P_MUL, 1)
        if w == "contains":
            return ("contains", _P_CMP, 1)
        if w == "begins" and self.is_id("with", k=1):
            return ("begins", _P_CMP, 2)
        if w == "ends" and self.is_id("with", k=1):
            return ("ends", _P_CMP, 2)
        if w == "is":
            k = 1
            neg = False
            if self.is_id("not", k=k):
                neg = True
                k += 1
            if self.is_id("in", k=k):
                return ("notin" if neg else "in", _P_CMP, k + 1)
            if self.is_id("among", k=k):
                return ("notamong" if neg else "among", _P_CMP, k + 1)
            if self.is_id("a", "an", k=k):
                return ("isnota" if neg else "isa", _P_CMP, k + 1)
            return ("isnot" if neg else "is", _P_EQ, k)
        return None

    # -- expressions
    def parse_expr(self, minp):
        left = self.parse_unary()
        while True:
            info = self.peek_infix()
            if info is None:
                return left
            op, prec, ntok = info
            if prec < minp:
                return left
            for _ in range(ntok):
                self.take()
            if op in ("among", "notamong"):
                self.expect_id("the")
                unit = self.take()
                if unit.kind != "id" or unit.low not in ("lines", "items", "words", "keys"):
                    self.fail("expected lines/items/words/keys after `is among the`")
                self.expect_id("of")
                right = self.parse_factor()
                left = self.gen_among(op, unit.low, left, right)
                continue
            if op in ("isa", "isnota"):
                kind_tok = self.take()
                if kind_tok.kind != "id" or kind_tok.low not in ("integer", "number"):
                    self.fail("`is a %s` is not modelled (only integer/number)" % kind_tok.val)
                fn = "_is_integer" if kind_tok.low == "integer" else "_is_number"
                code = "%s(%s)" % (fn, left[0])
                if op == "isnota":
                    code = "(not %s)" % code
                left = (code, "bool")
                continue
            right = self.parse_expr(prec + 1)
            if op == "pow" and self.is_op("^"):
                self.fail("chained ^ without parentheses is refused (associativity not modelled)")
            left = self.gen_binop(op, left, right)

    def parse_unary(self):
        t = self.peek()
        if t.kind == "op" and t.val == "-":
            self.take()
            nt = self.peek()
            if nt.kind == "num":
                self.take()
                return (repr(-self.num_value(nt.val)), "int" if isinstance(self.num_value(nt.val), int) else "num")
            operand, k = self.parse_unary()
            return ("_neg(%s)" % operand, "num")
        if t.kind == "id" and t.low == "not":
            self.take()
            operand, k = self.parse_unary()
            return ("(not %s)" % self.truth(operand, k), "bool")
        if t.kind == "id" and t.low == "bitnot":
            self.take()
            operand, k = self.parse_unary()
            return ("_bnot(%s)" % operand, "int")
        if t.kind == "id" and t.low == "there":
            self.fail("`there is ...` is engine object-model I/O and is refused")
        return self.parse_postfix()

    def num_value(self, text):
        if "." in text or "e" in text or "E" in text:
            f = float(text)
            if f.is_integer() and abs(f) <= _TWO53:
                return int(f)
            return f
        return int(text)

    def parse_postfix(self):
        """A primary followed by any number of [subscripts]."""
        base = self.parse_primary()
        if self.is_op("["):
            if base[2] != "var":
                self.fail("subscript on something that is not a variable")
            keys = []
            while self.is_op("["):
                self.take()
                kc, kk = self.parse_expr(0)
                self.expect_op("]")
                keys.append(self.keycode(kc, kk))
            return self.gen_subscript_read(base[0], keys)
        return (base[0], base[1])

    def parse_factor(self):
        """Target of `of` (chunks, counts, keys): a primary with subscripts,
        no binary operators - the engine binds these tightly."""
        return self.parse_postfix()

    def parse_primary(self):
        """-> (code, kind, what) where what is 'var' for a plain variable."""
        t = self.take()
        if t.kind == "op" and t.val == "(":
            c, k = self.parse_expr(0)
            self.expect_op(")")
            return ("(%s)" % c, k, "paren")
        if t.kind == "str":
            return (repr(t.val[1:-1]), "str", "lit")
        if t.kind == "num":
            v = self.num_value(t.val)
            return (repr(v), "int" if isinstance(v, int) else "num", "lit")
        if t.kind != "id":
            self.fail("unexpected %r in expression" % (t.val or "end of statement"))
        w = t.low
        if w == "the":
            return self.parse_the()
        if w in _CHUNK_UNITS:
            return self.parse_chunk(_CHUNK_UNITS[w])
        if w in _CONSTANTS:
            v = _CONSTANTS[w]
            kind = "bool" if isinstance(v, bool) else ("int" if isinstance(v, int) else ("num" if isinstance(v, float) else "str"))
            return (repr(v), kind, "lit")
        if self.is_op("("):
            return self.parse_call(t)
        if w in _RESERVED and w != "it":
            self.fail("reserved word `%s` used as a value" % t.val)
        code, kind = self.hc.var_read(t.val)
        return (code, kind, "var")

    def parse_the(self):
        t = self.take()
        w = t.low
        if w == "result":
            return ("_S.result", "any", "the")
        if w == "itemdelimiter":
            return ("_S.itemdel", "str", "the")
        if w == "linedelimiter":
            return ("_S.linedel", "str", "the")
        if w == "milliseconds":
            return ("_ms()", "int", "the")
        if w == "keys":
            self.expect_id("of")
            target, tk = self.parse_factor()
            return ("_keys(%s)" % target, "str", "the")
        if w == "number":
            self.expect_id("of")
            u = self.take()
            if u.kind != "id" or u.low not in _COUNT_UNITS:
                self.fail("`the number of %s of` is not modelled" % u.val)
            self.expect_id("of")
            target, tk = self.parse_factor()
            fn = _COUNT_UNITS[u.low]
            if fn == "items":
                return ("len(_split(_str(%s), _S.itemdel))" % target, "int", "the")
            if fn == "lines":
                return ("len(_split(_str(%s), _S.linedel))" % target, "int", "the")
            if fn == "words":
                return ("len(_words(%s))" % target, "int", "the")
            return ("%s(%s)" % (fn, target), "int", "the")
        self.fail("`the %s` is not modelled" % t.val)

    def parse_chunk(self, unit):
        a, ak = self.parse_expr(0)
        b = None
        if self.is_id("to"):
            self.take()
            b, bk = self.parse_expr(0)
        self.expect_id("of")
        target, tk = self.parse_factor()
        if unit == "byte":
            if b is None:
                return ("_byte1(%s, %s)" % (target, a), "str", "chunk")
            return ("_byte_range(%s, %s, %s)" % (target, a, b), "str", "chunk")
        if unit == "char":
            if b is None:
                return ("_char1(%s, %s)" % (target, a), "str", "chunk")
            return ("_char_range(%s, %s, %s)" % (target, a, b), "str", "chunk")
        if unit == "item":
            parts = "_split(_str(%s), _S.itemdel)" % target
            d = "_S.itemdel"
        elif unit == "line":
            parts = "_split(_str(%s), _S.linedel)" % target
            d = "_S.linedel"
        else:
            parts = "_words(%s)" % target
            d = "' '"
        if b is None:
            return ("_pick(%s, _idx(%s), %s)" % (parts, a, d), "str", "chunk")
        return ("_pick_range(%s, _idx(%s), _idx(%s), %s)" % (parts, a, b, d), "str", "chunk")

    def parse_args(self):
        """After `(`: comma-separated expressions up to `)`. Returns a list
        of (code, kind, raw_token_start, raw_token_end)."""
        args = []
        if self.is_op(")"):
            self.take()
            return args
        while True:
            start = self.i
            c, k = self.parse_expr(0)
            args.append((c, k, start, self.i))
            if self.is_op(","):
                self.take()
                continue
            self.expect_op(")")
            return args

    def parse_call(self, name_tok):
        self.expect_op("(")
        low = name_tok.low
        start = self.i
        args = self.parse_args()
        # the binaryDecode(fmt, data, outVar) form is handled by `get`
        if low == "binarydecode":
            self.fail("binaryDecode is only modelled in the form `get binaryDecode(fmt, data, var)`")
        if low == "bitnot":
            if len(args) != 1:
                self.fail("bitNot takes one operand")
            return ("_bnot(%s)" % args[0][0], "int", "call")
        # peephole: byteToNum(byte K of S)
        if low == "bytetonum" and len(args) == 1:
            m = re.match(r"^_byte1\((.*)\)$", args[0][0])
            if m and _balanced(m.group(1)):
                return ("_bytetonum_at(%s)" % m.group(1), "int", "call")
        model = self.hc.model
        if low in model.handlers:
            h = model.handlers[low]
            if low not in model.overrides:
                if h.kind != "function":
                    self.fail("`%s` is a command; a command cannot be called in expression position (D7)" % h.name)
                if any(h.byref):
                    self.fail("function `%s` has @ parameters; calling it in expression position is not modelled" % h.name)
                if len(args) > len(h.params):
                    self.fail("`%s` called with %d arguments but declares %d (D8)" % (h.name, len(args), len(h.params)))
            self.hc.note_call(low)
            return ("h_%s(%s)" % (low, ", ".join(a[0] for a in args)), "any", "call")
        if low in model.overrides:
            return ("h_%s(%s)" % (low, ", ".join(a[0] for a in args)), "any", "call")
        if low in _BUILTINS:
            fn, lo, hi, kind = _BUILTINS[low]
            if not lo <= len(args) <= hi:
                self.fail("%s() takes %d..%d arguments, got %d" % (name_tok.val, lo, hi, len(args)))
            return ("%s(%s)" % (fn, ", ".join(a[0] for a in args)), kind, "call")
        self.fail("unknown function `%s`" % name_tok.val)

    # -- code generation helpers
    def truth(self, code, kind):
        if kind == "bool":
            return code
        return "_truth(%s)" % code

    def keycode(self, code, kind):
        if kind == "int":
            return code
        if kind in ("str", "num", "bool") and _is_literal(code):
            return repr(_key(_literal_value(code)))
        if _is_simple(code):
            return "(%s if %s.__class__ is int else _key(%s))" % (code, code, code)
        t = self.tmp()
        return "(%s if (%s := %s).__class__ is int else _key(%s))" % (t, t, code, t)

    def gen_subscript_read(self, root, keys):
        if len(keys) == 1:
            return ("(%s.get(%s, '') if %s.__class__ is dict else _get_nonarr(%s, %s))"
                    % (root, keys[0], root, root, keys[0]), "any")
        if len(keys) == 2:
            return ("_get2(%s, %s, %s)" % (root, keys[0], keys[1]), "any")
        return ("_getn(%s, (%s,))" % (root, ", ".join(keys)), "any")

    def gen_among(self, op, unit, left, right):
        if unit == "keys":
            code = "(%s.__class__ is dict and _key(%s) in %s)" % (right[0], left[0], right[0])
        elif unit == "lines":
            code = "(_str(%s).lower() in [x.lower() for x in _split(_str(%s), _S.linedel)])" % (left[0], right[0])
        elif unit == "items":
            code = "(_str(%s).lower() in [x.lower() for x in _split(_str(%s), _S.itemdel)])" % (left[0], right[0])
        else:
            code = "(_str(%s).lower() in [x.lower() for x in _words(%s)])" % (left[0], right[0])
        if op == "notamong":
            code = "(not %s)" % code
        return (code, "bool")

    def _pair(self, a, b):
        """Bind operands to re-evaluable references: returns
        (refA, refB, assignA, assignB)."""
        if _is_simple(a):
            ra, aa = a, a
        else:
            ra = self.tmp()
            aa = "(%s := %s)" % (ra, a)
        if _is_simple(b):
            rb, ab = b, b
        else:
            rb = self.tmp()
            ab = "(%s := %s)" % (rb, b)
        return ra, rb, aa, ab

    def gen_binop(self, op, left, right):
        a, ak = left
        b, bk = right
        if op == "and":
            return ("(%s and %s)" % (self.truth(a, ak), self.truth(b, bk)), "bool")
        if op == "or":
            return ("(%s or %s)" % (self.truth(a, ak), self.truth(b, bk)), "bool")
        if op == "cat":
            return ("(%s + %s)" % (self.strcode(a, ak), self.strcode(b, bk)), "str")
        if op == "catsp":
            return ("(%s + ' ' + %s)" % (self.strcode(a, ak), self.strcode(b, bk)), "str")
        if op in ("in", "notin"):
            code = "_is_in(%s, %s)" % (a, b)
            return (("(not %s)" % code) if op == "notin" else code, "bool")
        if op == "contains":
            return ("_contains(%s, %s)" % (a, b), "bool")
        if op == "begins":
            return ("_begins_with(%s, %s)" % (a, b), "bool")
        if op == "ends":
            return ("_ends_with(%s, %s)" % (a, b), "bool")
        # numeric / comparison operators: int-int fast path, helper otherwise
        if op in ("eq", "is"):
            return (self._fast("==", "_eq", a, b, ak, bk), "bool")
        if op in ("ne", "isnot"):
            return (self._fast("!=", "_ne", a, b, ak, bk), "bool")
        if op in ("lt", "le", "gt", "ge"):
            sym = {"lt": "<", "le": "<=", "gt": ">", "ge": ">="}[op]
            return (self._fast(sym, "_" + op, a, b, ak, bk), "bool")
        if op in ("add", "sub"):
            return (self._fast("+" if op == "add" else "-", "_" + op, a, b, ak, bk), "num")
        ra, rb, aa, ab = self._pair(a, b)
        if op == "mul":
            return ("_mul(%s, %s)" % (a, b), "num")
        if op == "truediv":
            return ("_truediv(%s, %s)" % (a, b), "num")
        if op == "pow":
            return ("_pow(%s, %s)" % (a, b), "num")
        if op in ("div", "mod"):
            # fast path: non-negative int // (or %) positive int literal
            fn = "_div" if op == "div" else "_mod"
            sym = "//" if op == "div" else "%"
            if bk == "int" and _is_literal(b) and _literal_value(b) > 0:
                fast = "(%s %s %s)" % (ra, sym, rb)
                if ak == "int" and _is_literal(a):
                    if _literal_value(a) >= 0:
                        return (fast, "int")
                    return ("%s(%s, %s)" % (fn, a, b), "num")
                cond = "(%s.__class__ is int and %s >= 0)" % (aa, ra)
                return ("(%s if %s else %s(%s, %s))" % (fast, cond, fn, ra, rb), "num")
            return ("%s(%s, %s)" % (fn, a, b), "num")
        if op in ("band", "bor", "bxor"):
            sym = {"band": "&", "bor": "|", "bxor": "^"}[op]
            fn = {"band": "_band", "bor": "_bor", "bxor": "_bxor"}[op]
            fast = "(%s %s %s)" % (ra, sym, rb)
            ca = self._u32check(aa, ra, ak)
            cb = self._u32check(ab, rb, bk)
            if ca is True and cb is True:
                return (fast, "int")
            cond = "(%s & %s)" % (ca if ca is not True else "True", cb if cb is not True else "True")
            return ("(%s if %s else %s(%s, %s))" % (fast, cond, fn, ra, rb), "int")
        self.fail("operator %s is not modelled" % op)

    def _u32check(self, assign, ref, kind):
        """Condition code for 'this operand is already an unsigned 32-bit int'
        (True when a literal settles it at compile time)."""
        if _is_literal(ref):
            v = _literal_value(ref)
            if kind == "int" and 0 <= v <= 4294967295:
                return True
            return "False"
        return "(%s.__class__ is int and 0 <= %s <= 4294967295)" % (assign, ref)

    def _fast(self, sym, helper, a, b, ak, bk):
        """`(a sym b) if <both operands are ints> else helper(a, b)`. Every
        operand that is not a plain name/literal is bound by a walrus INSIDE
        the condition, in left-to-right order, so the branches can refer to
        its temp. A non-int literal settles it: helper only."""
        ra, rb, aa, ab = self._pair(a, b)
        parts = []
        for assign, ref, kind in ((aa, ra, ak), (ab, rb, bk)):
            if _is_literal(ref):
                if kind == "int":
                    continue                # an int literal needs no check
                return "%s(%s, %s)" % (helper, a, b)   # float/text literal
            if kind == "int" and assign == ref:
                continue                    # a name already known int
            parts.append("(%s.__class__ is int)" % assign)
        fast = "(%s %s %s)" % (ra, sym, rb)
        if not parts:
            return fast
        return "(%s if %s else %s(%s, %s))" % (fast, " & ".join(parts), helper, ra, rb)

    def strcode(self, code, kind):
        if kind == "str":
            return code
        if _is_literal(code):
            return repr(_str(_literal_value(code)))
        if _is_simple(code):
            return "(%s if %s.__class__ is str else _str(%s))" % (code, code, code)
        t = self.tmp()
        return "(%s if (%s := %s).__class__ is str else _str(%s))" % (t, t, code, t)


def _is_literal(code):
    return re.match(r"^(?:-?\d+(?:\.\d+)?|'[^']*'|\"[^\"]*\"|True|False)$", code) is not None


def _literal_value(code):
    import ast as _ast
    return _ast.literal_eval(code)


def _balanced(s):
    d = 0
    instr = False
    for ch in s:
        if ch == "'" and not instr:
            instr = True
        elif ch == "'" and instr:
            instr = False
        elif not instr:
            if ch == "(":
                d += 1
            elif ch == ")":
                d -= 1
                if d < 0:
                    return False
    return d == 0 and not instr


# ========================================================= handler compiler --

def _int_bound(v):
    n = _num(v)
    if n.__class__ is float:
        if not n.is_integer():
            raise ModelError("repeat with: bound %r is not an integer (D6)" % (n,))
        n = int(n)
    return n


_RUNTIME["_int_bound"] = _int_bound


class _Handler(object):
    def __init__(self, name, kind, params, byref, srcname, lineno, body):
        self.name = name
        self.low = name.lower()
        self.kind = kind            # 'function' | 'command'
        self.params = params        # lowercase names
        self.byref = byref          # parallel list of bool
        self.srcname = srcname
        self.lineno = lineno
        self.body = body            # [(lineno, text)]
        self.pysrc = None
        self.fn = None


def _head(toks):
    """The leading keyword(s) of a statement line, normalised."""
    if not toks or toks[0].kind != "id":
        return ""
    w = toks[0].low
    if w == "end" and len(toks) > 1 and toks[1].kind == "id":
        return "end " + toks[1].low
    if w == "else" and len(toks) > 1 and toks[1].kind == "id" and toks[1].low == "if":
        return "else if"
    if w == "exit" and len(toks) > 1 and toks[1].kind == "id" and toks[1].low == "repeat":
        return "exit repeat"
    if w == "next" and len(toks) > 1 and toks[1].kind == "id" and toks[1].low == "repeat":
        return "next repeat"
    return w


def _find_top(toks, words, last=False):
    """Index of the first (or last) top-level identifier token in `words`."""
    depth = 0
    found = None
    for i, t in enumerate(toks):
        if t.kind == "op":
            if t.val in "([":
                depth += 1
            elif t.val in ")]":
                depth -= 1
        elif t.kind == "id" and depth == 0 and t.low in words:
            if not last:
                return i
            found = i
    return found


class _Stmt(object):
    __slots__ = ("kind", "line", "text", "a", "b", "c", "d")

    def __init__(self, kind, line, text, a=None, b=None, c=None, d=None):
        self.kind = kind
        self.line = line
        self.text = text
        self.a = a
        self.b = b
        self.c = c
        self.d = d


class _HandlerCompiler(object):
    def __init__(self, model, h):
        self.model = model
        self.h = h
        self.scope = {}                 # low -> python name
        self.byref = set(p for p, r in zip(h.params, h.byref) if r)
        self.params = set(h.params)
        self.written_params = set()
        self.script_writes = set()
        self.tmpn = 0
        self.cur_line = h.lineno
        self.cur_text = ""
        self.uses_it = False
        self.calls = set()
        for p in h.params:
            self.scope[p] = "v_" + p

    # ---------------------------------------------------------- utilities
    def fail(self, msg):
        raise ModelError("REFUSED (%s:%d, handler %s): %s\n    line: %s"
                         % (self.h.srcname, self.cur_line, self.h.name, msg, self.cur_text.strip()))

    def tmp(self):
        self.tmpn += 1
        return "_t%d" % self.tmpn

    def note_call(self, low):
        self.calls.add(low)

    def var_read(self, name):
        low = name.lower()
        if low == "it":
            if not self.uses_it:
                self.fail("`it` read in a handler with no `get`")
            return ("v_it", "any")
        if low in self.scope:
            return (self.scope[low], "any")
        if low in self.model.script_locals:
            return ("s_" + low, "any")
        if low in self.model.constants:
            v = self.model.constants[low]
            kind = "bool" if isinstance(v, bool) else ("int" if isinstance(v, int) else ("num" if isinstance(v, float) else "str"))
            return (repr(v), kind)
        if low in self.model.handlers or low in self.model.overrides:
            self.fail("`%s` is a handler name used as a value; a zero-argument function call needs `()` (D1/D7)" % name)
        self.fail("undeclared variable `%s` (D1: the engine would silently use the literal name)" % name)

    def var_write(self, name):
        """Python name for an assignment target; records param/script writes."""
        low = name.lower()
        if low in self.scope:
            if low in self.params and low not in self.byref:
                self.written_params.add(low)
            return self.scope[low]
        if low in self.model.script_locals:
            self.script_writes.add(low)
            return "s_" + low
        if low in self.model.constants:
            self.fail("assignment to constant `%s`" % name)
        if low == "it":
            self.fail("`it` can only be set by `get`")
        self.fail("assignment to undeclared variable `%s` (D1)" % name)

    def declare_local(self, name):
        low = name.lower()
        if low in _RESERVED:
            self.fail("local `%s` is a reserved word in this model" % name)
        if low in self.scope:
            self.fail("`%s` declared twice (the engine: name shadows another variable)" % name)
        if low in self.model.script_locals or low in self.model.constants:
            self.fail("local `%s` shadows a script-level declaration" % name)
        self.scope[low] = "v_" + low

    # ------------------------------------------------------------ parsing
    def compile(self):
        h = self.h
        # pass 1: hoist every `local` declaration (mid-handler is legal)
        for lineno, text in h.body:
            self.cur_line, self.cur_text = lineno, text
            if re.match(r"^local\b", text, re.I):
                toks = _tokenize(text, "%s:%d" % (h.srcname, lineno))
                self.parse_local(toks)
            elif re.match(r"^get\b", text, re.I):
                self.uses_it = True
        # pass 2: parse the block structure
        lines = [(ln, tx, None) for ln, tx in h.body]
        stmts, idx = self.parse_block(lines, 0, lambda head, toks: False, "handler")
        if idx != len(lines):
            self.cur_line, self.cur_text = lines[idx][0], lines[idx][1]
            self.fail("unexpected `%s` (block structure)" % _head(self.toks_of(lines, idx)))
        # pass 3: code generation
        body = []
        self.emit_block(stmts, body, 2, loop_depth=0, in_catch=False, in_try=False)
        return self.assemble(body)

    def toks_of(self, lines, idx):
        ln, tx, cached = lines[idx]
        if cached is None:
            cached = _tokenize(tx, "%s:%d" % (self.h.srcname, ln))
            lines[idx] = (ln, tx, cached)
        return cached

    def parse_local(self, toks):
        # local a, b, c
        i = 1
        while i < len(toks) and toks[i].kind != "end":
            t = toks[i]
            if t.kind != "id":
                self.fail("bad local declaration")
            self.declare_local(t.val)
            i += 1
            if i < len(toks) and toks[i].kind == "op" and toks[i].val == ",":
                i += 1
                continue
            if toks[i].kind != "end":
                self.fail("bad local declaration (only `local a, b, c` is modelled)")

    def parse_block(self, lines, idx, stop, what):
        """Parse statements until `stop(head, toks)` is true. Returns
        (stmts, idx_of_stop_line)."""
        stmts = []
        while idx < len(lines):
            ln, tx, _ = lines[idx]
            if tx == "":
                idx += 1
                continue
            toks = self.toks_of(lines, idx)
            head = _head(toks)
            if stop(head, toks):
                return stmts, idx
            self.cur_line, self.cur_text = ln, tx
            if head == "if":
                st, idx = self.parse_if(lines, idx, toks)
            elif head == "repeat":
                st, idx = self.parse_repeat(lines, idx, toks)
            elif head == "switch":
                st, idx = self.parse_switch(lines, idx, toks)
            elif head == "try":
                st, idx = self.parse_try(lines, idx, toks)
            elif head in ("else", "else if", "end if", "end repeat", "end switch", "end try",
                          "case", "default", "catch", "break", "end", "finally"):
                if head == "else" or head == "else if":
                    self.fail("`%s` with no open block `if` here - if the previous statement is a "
                              "single-line `if ... then stmt`, that is the engine trap of "
                              "ARCHITECTURE.md rule 12 (D9)" % head)
                if head == "break":
                    self.fail("`break` must be the last statement of its case, at the top level of the case (D18)")
                self.fail("unexpected `%s` inside %s" % (head, what))
            else:
                st = self.parse_simple(toks, ln, tx)
                idx += 1
            stmts.append(st)
        return stmts, idx

    def parse_if(self, lines, idx, toks):
        ln, tx, _ = lines[idx]
        then_i = _find_top(toks, ("then",))
        if then_i is None:
            self.fail("`if` without `then`")
        cond = toks[1:then_i]
        if not cond:
            self.fail("`if` with an empty condition")
        rest = toks[then_i + 1:]
        if rest and rest[0].kind != "end":
            # single-line form
            rh = _head(rest)
            if rh in ("if", "repeat", "switch", "try"):
                self.fail("single-line `if ... then` followed by a block opener is not modelled")
            st = self.parse_simple(rest, ln, tx)
            return _Stmt("if", ln, tx, [(cond, [st])], None), idx + 1
        # block form
        branches = []
        else_body = None
        cur_cond = cond
        idx += 1
        stop = lambda head, t: head in ("else", "else if", "end if")
        while True:
            body, idx = self.parse_block(lines, idx, stop, "if")
            if idx >= len(lines):
                self.cur_line, self.cur_text = ln, tx
                self.fail("`if` block never closed by `end if`")
            branches.append((cur_cond, body))
            t2 = self.toks_of(lines, idx)
            head = _head(t2)
            self.cur_line, self.cur_text = lines[idx][0], lines[idx][1]
            if head == "end if":
                if len(t2) != 3:
                    self.fail("trailing text after `end if`")
                return _Stmt("if", ln, tx, branches, else_body), idx + 1
            if else_body is not None:
                self.fail("`%s` after `else`" % head)
            if head == "else if":
                ti = _find_top(t2, ("then",))
                if ti is None or ti != len(t2) - 2:
                    self.fail("`else if` must be a block form ending in `then`")
                cur_cond = t2[2:ti]
                idx += 1
                continue
            # bare else
            if len(t2) != 2:
                self.fail("`else` followed by a statement on the same line is not modelled")
            idx += 1
            else_body, idx = self.parse_block(lines, idx, lambda h, t: h == "end if", "else")
            if idx >= len(lines):
                self.cur_line, self.cur_text = ln, tx
                self.fail("`if` block never closed by `end if`")
            self.cur_line, self.cur_text = lines[idx][0], lines[idx][1]
            t3 = self.toks_of(lines, idx)
            if len(t3) != 3:
                self.fail("trailing text after `end if`")
            return _Stmt("if", ln, tx, branches, else_body), idx + 1

    def parse_repeat(self, lines, idx, toks):
        ln, tx, _ = lines[idx]
        n = len(toks) - 1
        stop = lambda head, t: head == "end repeat"
        if n == 1 or (n == 2 and toks[1].low == "forever"):
            node = _Stmt("repeat_forever", ln, tx)
        elif toks[1].kind == "id" and toks[1].low == "with":
            # repeat with VAR = A to B  |  down to B
            if not (toks[2].kind == "id" and toks[3].kind == "op" and toks[3].val == "="):
                self.fail("`repeat with` needs `var = from to|down to to`")
            var = toks[2]
            ep = _ExprCompiler(self, toks, 4)
            a = ep.parse_expr(0)
            down = False
            if ep.is_id("down"):
                ep.take()
                down = True
            ep.expect_id("to")
            b = ep.parse_expr(0)
            if ep.is_id("step"):
                self.fail("`repeat with ... step` is refused: the engine does not honour step (D6)")
            if not ep.at_end():
                self.fail("unexpected %r after the repeat bounds" % ep.peek().val)
            node = _Stmt("repeat_with", ln, tx, var, a, b, down)
        elif toks[1].kind == "id" and toks[1].low == "while":
            ep = _ExprCompiler(self, toks, 2)
            c = ep.parse_full()
            node = _Stmt("repeat_while", ln, tx, c)
        elif toks[1].kind == "id" and toks[1].low == "until":
            self.fail("`repeat until` is not modelled (D6)")
        elif toks[1].kind == "id" and toks[1].low == "for":
            if not (toks[2].kind == "id" and toks[2].low == "each"):
                self.fail("bad `repeat for` form")
            unit = toks[3].low if toks[3].kind == "id" else ""
            if unit not in ("item", "line", "word"):
                self.fail("`repeat for each %s` is not modelled (only item/line/word)" % toks[3].val)
            var = toks[4]
            if var.kind != "id":
                self.fail("bad loop variable")
            if not (toks[5].kind == "id" and toks[5].low == "in"):
                self.fail("`repeat for each` needs `in`")
            ep = _ExprCompiler(self, toks, 6)
            e = ep.parse_full()
            node = _Stmt("repeat_each", ln, tx, unit, var, e)
        else:
            self.fail("this `repeat` form is not modelled (D6)")
        body, idx2 = self.parse_block(lines, idx + 1, stop, "repeat")
        if idx2 >= len(lines):
            self.cur_line, self.cur_text = ln, tx
            self.fail("`repeat` never closed by `end repeat`")
        if node.kind == "repeat_with":
            node.d = (node.d, body)         # (down?, body)
        else:
            node.d = body
        return node, idx2 + 1

    def parse_switch(self, lines, idx, toks):
        ln, tx, _ = lines[idx]
        ep = _ExprCompiler(self, toks, 1)
        subj = ep.parse_full()
        segments = []          # [label_expr_or_None, body, has_break]
        idx += 1
        stop = lambda head, t: head in ("case", "default", "break", "end switch")
        seen_default = False
        while True:
            body, idx = self.parse_block(lines, idx, stop, "switch")
            if idx >= len(lines):
                self.cur_line, self.cur_text = ln, tx
                self.fail("`switch` never closed by `end switch`")
            if body:
                if not segments:
                    self.cur_line, self.cur_text = ln, tx
                    self.fail("statements before the first `case` in a switch")
                segments[-1][1].extend(body)
            t2 = self.toks_of(lines, idx)
            head = _head(t2)
            self.cur_line, self.cur_text = lines[idx][0], lines[idx][1]
            if head == "end switch":
                return _Stmt("switch", ln, tx, subj, segments), idx + 1
            if head == "break":
                if len(t2) != 2:
                    self.fail("trailing text after `break`")
                if not segments or segments[-1][2]:
                    self.fail("`break` outside a case body")
                segments[-1][2] = True
                idx += 1
                # only case/default/end switch may follow a break (D18)
                j = idx
                while j < len(lines) and lines[j][1] == "":
                    j += 1
                if j < len(lines):
                    nh = _head(self.toks_of(lines, j))
                    if nh not in ("case", "default", "end switch"):
                        self.cur_line, self.cur_text = lines[j][0], lines[j][1]
                        self.fail("statement after `break` in a case is unreachable/refused (D18)")
                continue
            if head == "default":
                if len(t2) != 2:
                    self.fail("trailing text after `default`")
                if seen_default:
                    self.fail("two `default` labels")
                seen_default = True
                segments.append([None, [], False])
                idx += 1
                continue
            # case EXPR
            ep2 = _ExprCompiler(self, t2, 1)
            label = ep2.parse_full()
            segments.append([label, [], False])
            idx += 1

    def parse_try(self, lines, idx, toks):
        ln, tx, _ = lines[idx]
        if len(toks) != 2:
            self.fail("trailing text after `try`")
        body, idx = self.parse_block(lines, idx + 1, lambda h, t: h in ("catch", "end try", "finally"), "try")
        if idx >= len(lines):
            self.cur_line, self.cur_text = ln, tx
            self.fail("`try` never closed")
        t2 = self.toks_of(lines, idx)
        self.cur_line, self.cur_text = lines[idx][0], lines[idx][1]
        if _head(t2) != "catch":
            self.fail("`try` without `catch` is not modelled")
        if len(t2) != 3 or t2[1].kind != "id":
            self.fail("`catch` needs exactly one variable")
        var = t2[1]
        self.var_write(var.val)     # must be declared
        cbody, idx = self.parse_block(lines, idx + 1, lambda h, t: h in ("end try", "finally", "catch"), "catch")
        if idx >= len(lines):
            self.cur_line, self.cur_text = ln, tx
            self.fail("`try` never closed by `end try`")
        t3 = self.toks_of(lines, idx)
        self.cur_line, self.cur_text = lines[idx][0], lines[idx][1]
        if _head(t3) != "end try":
            self.fail("`%s` is not modelled in a try" % _head(t3))
        return _Stmt("try", ln, tx, body, var, cbody), idx + 1

    def parse_target(self, toks, ln, tx):
        """`name` or `name[k1][k2]...` -> (pyname, [keycode...], low)."""
        if not toks or toks[0].kind != "id":
            self.fail("assignment target must be a variable")
        if toks[0].low in _RESERVED or toks[0].low in _CONSTANTS:
            self.fail("assignment to the reserved word `%s`" % toks[0].val)
        ep = _ExprCompiler(self, toks, 1)
        keys = []
        while ep.is_op("["):
            ep.take()
            kc, kk = ep.parse_expr(0)
            ep.expect_op("]")
            keys.append(ep.keycode(kc, kk))
        if not ep.at_end():
            self.fail("bad assignment target: %s" % " ".join(t.val for t in toks))
        pyname = self.var_write(toks[0].val)
        return pyname, keys, toks[0].low

    def parse_simple(self, toks, ln, tx):
        self.cur_line, self.cur_text = ln, tx
        head = _head(toks)
        if head == "put":
            i = _find_top(toks, ("into", "after", "before"))
            if i is None:
                self.fail("`put` without into/after/before")
            val = toks[1:i] + [toks[-1]]
            if len(val) == 1:
                self.fail("`put` with an empty value")
            ep = _ExprCompiler(self, val, 0)
            v = ep.parse_full()
            tgt = self.parse_target(toks[i + 1:-1] + [toks[-1]], ln, tx)
            return _Stmt("put", ln, tx, v, toks[i].low, tgt)
        if head in ("add", "subtract"):
            word = "to" if head == "add" else "from"
            i = _find_top(toks, (word,), last=True)
            if i is None:
                self.fail("`%s` without `%s`" % (head, word))
            ep = _ExprCompiler(self, toks[1:i] + [toks[-1]], 0)
            v = ep.parse_full()
            tgt = self.parse_target(toks[i + 1:-1] + [toks[-1]], ln, tx)
            return _Stmt(head, ln, tx, v, tgt)
        if head in ("multiply", "divide"):
            i = _find_top(toks, ("by",))
            if i is None:
                self.fail("`%s` without `by`" % head)
            tgt = self.parse_target(toks[1:i] + [toks[-1]], ln, tx)
            ep = _ExprCompiler(self, toks[i + 1:], 0)
            v = ep.parse_full()
            return _Stmt(head, ln, tx, v, tgt)
        if head == "set":
            if not (len(toks) > 4 and toks[1].low == "the" and toks[2].kind == "id"
                    and toks[2].low in ("itemdelimiter", "linedelimiter") and toks[3].low == "to"):
                self.fail("only `set the itemDelimiter|lineDelimiter to EXPR` is modelled")
            ep = _ExprCompiler(self, toks, 4)
            v = ep.parse_full()
            return _Stmt("setdelim", ln, tx, toks[2].low, v)
        if head == "get":
            # special form: get binaryDecode(fmt, data, outVar)
            if len(toks) > 2 and toks[1].kind == "id" and toks[1].low == "binarydecode" and toks[2].kind == "op" and toks[2].val == "(":
                ep = _ExprCompiler(self, toks, 3)
                fmt = ep.parse_expr(0)
                ep.expect_op(",")
                data = ep.parse_expr(0)
                ep.expect_op(",")
                out = ep.take()
                if out.kind != "id":
                    self.fail("binaryDecode: the output must be a variable")
                ep.expect_op(")")
                if not ep.at_end():
                    self.fail("trailing text after binaryDecode(...)")
                pyname = self.var_write(out.val)
                return _Stmt("bindecode", ln, tx, fmt, data, pyname)
            ep = _ExprCompiler(self, toks, 1)
            v = ep.parse_full()
            return _Stmt("get", ln, tx, v)
        if head == "exit repeat":
            if len(toks) != 3:
                self.fail("trailing text after `exit repeat`")
            return _Stmt("exit_repeat", ln, tx)
        if head == "next repeat":
            if len(toks) != 3:
                self.fail("trailing text after `next repeat`")
            return _Stmt("next_repeat", ln, tx)
        if head == "exit":
            if len(toks) == 3 and toks[1].kind == "id" and toks[1].low == self.h.low:
                return _Stmt("exit_handler", ln, tx)
            self.fail("`exit` must name this handler (`exit %s`) or be `exit repeat`" % self.h.name)
        if head == "return":
            if len(toks) == 2:
                self.fail("bare `return` is an engine error (missing factor); use `return EXPR` or `exit %s`" % self.h.name)
            ep = _ExprCompiler(self, toks, 1)
            v = ep.parse_full()
            return _Stmt("return", ln, tx, v)
        if head == "throw":
            ep = _ExprCompiler(self, toks, 1)
            v = ep.parse_full()
            return _Stmt("throw", ln, tx, v)
        if head == "local":
            return _Stmt("local", ln, tx)
        if head in ("pass", "send", "dispatch", "global", "constant", "delete", "replace",
                    "sort", "create", "answer", "ask", "open", "close", "write", "read",
                    "wait", "do", "call", "include", "require"):
            self.fail("`%s` is outside the modelled subset" % head)
        if toks[0].kind == "id" and (toks[0].low in self.model.handlers or toks[0].low in self.model.overrides):
            return self.parse_call_stmt(toks, ln, tx)
        if toks[0].kind == "id" and toks[0].low not in _RESERVED:
            self.fail("unknown handler or unsupported statement `%s`" % toks[0].val)
        self.fail("unsupported statement")

    def parse_call_stmt(self, toks, ln, tx):
        name = toks[0]
        low = name.low
        if len(toks) > 2 and toks[1].kind == "op" and toks[1].val == "(" and toks[2].kind == "op" and toks[2].val == ")":
            self.fail("`%s()` in statement position is a parse error on the engine; write it bare (D7)" % name.val)
        h = self.model.handlers.get(low)
        overridden = low in self.model.overrides
        if h is not None and not overridden and h.kind != "command":
            self.fail("`%s` is a function; calling a function in statement position is refused (D7)" % h.name)
        # split args at top-level commas
        args = []
        if len(toks) > 2:
            ep = _ExprCompiler(self, toks, 1)
            while True:
                start = ep.i
                c, k = ep.parse_expr(0)
                args.append((c, k, toks[start:ep.i]))
                if ep.is_op(","):
                    ep.take()
                    continue
                if not ep.at_end():
                    self.fail("unexpected %r in the argument list" % ep.peek().val)
                break
        if h is not None and not overridden:
            if len(args) > len(h.params):
                self.fail("`%s` called with %d arguments but declares %d (D8)" % (h.name, len(args), len(h.params)))
            for k, r in enumerate(h.byref):
                if not r:
                    continue
                if k >= len(args):
                    self.fail("`%s`: by-reference parameter @%s may not be omitted (D8)" % (h.name, h.params[k]))
                atoks = args[k][2]
                if not (len(atoks) == 1 and atoks[0].kind == "id"):
                    self.fail("`%s`: by-reference parameter @%s needs a plain variable, got `%s` (D8)"
                              % (h.name, h.params[k], " ".join(t.val for t in atoks)))
        self.note_call(low)
        return _Stmt("call", ln, tx, low, args, h if not overridden else None)

    # ------------------------------------------------------------ codegen
    def emit_block(self, stmts, out, ind, loop_depth, in_catch, in_try):
        if not stmts:
            out.append("    " * ind + "pass")
            return
        for st in stmts:
            self.emit_stmt(st, out, ind, loop_depth, in_catch, in_try)

    def line_marker(self, st, out, ind):
        pad = "    " * ind
        out.append("%s_L = %d" % (pad, st.line))
        if self.model.count_statements:
            out.append("%s_S.nstmt += 1" % pad)

    def value_with_copy(self, v, out, pad):
        """Emit code binding a temp to the value, copied if it is an array.
        Returns the reference code."""
        code, kind = v
        if kind in ("int", "num", "str", "bool"):
            return code
        t = self.tmp()
        out.append("%s%s = %s" % (pad, t, code))
        out.append("%sif %s.__class__ is dict: %s = _copy(%s)" % (pad, t, t, t))
        return t

    def emit_write(self, tgt, valref, out, pad):
        pyname, keys, low = tgt
        if not keys:
            out.append("%s%s = %s" % (pad, pyname, valref))
        elif len(keys) == 1:
            k = keys[0]
            if not _is_simple(k):
                t = self.tmp()
                out.append("%s%s = %s" % (pad, t, k))
                k = t
            out.append("%sif %s.__class__ is not dict: %s = _newarr(%s)" % (pad, pyname, pyname, pyname))
            out.append("%s%s[%s] = %s" % (pad, pyname, k, valref))
        else:
            out.append("%s%s = _setn(%s, (%s,), %s)" % (pad, pyname, pyname, ", ".join(keys), valref))

    def target_read(self, tgt, out, pad):
        """Read the current value of a target; keys are bound to temps so
        the following write uses the same keys. Returns (readcode, tgt')."""
        pyname, keys, low = tgt
        if not keys:
            return pyname, tgt
        bound = []
        for k in keys:
            if _is_simple(k):
                bound.append(k)
            else:
                t = self.tmp()
                out.append("%s%s = %s" % (pad, t, k))
                bound.append(t)
        if len(bound) == 1:
            rc = "(%s.get(%s, '') if %s.__class__ is dict else _get_nonarr(%s, %s))" % (pyname, bound[0], pyname, pyname, bound[0])
        else:
            rc = "_getn(%s, (%s,))" % (pyname, ", ".join(bound))
        return rc, (pyname, bound, low)

    def emit_stmt(self, st, out, ind, loop_depth, in_catch, in_try):
        pad = "    " * ind
        self.cur_line, self.cur_text = st.line, st.text
        k = st.kind
        if k == "local":
            return
        if k in ("if", "repeat_with", "repeat_while", "repeat_forever", "repeat_each", "switch", "try"):
            self.line_marker(st, out, ind)
            getattr(self, "emit_" + k)(st, out, ind, loop_depth, in_catch, in_try)
            return
        self.line_marker(st, out, ind)
        if k == "put":
            v, prep, tgt = st.a, st.b, st.c
            if prep == "into":
                ref = self.value_with_copy(v, out, pad)
                self.emit_write(tgt, ref, out, pad)
                return
            ec = _ExprCompiler(self, [], 0)
            sc = ec.strcode(v[0], v[1])
            pyname, keys, low = tgt
            if not keys and prep == "after":
                out.append("%sif %s.__class__ is not str: %s = _str(%s)" % (pad, pyname, pyname, pyname))
                out.append("%s%s += %s" % (pad, pyname, sc))
                return
            rc, tgt2 = self.target_read(tgt, out, pad)
            if prep == "after":
                self.emit_write(tgt2, "(_str(%s) + %s)" % (rc, sc), out, pad)
            else:
                self.emit_write(tgt2, "(%s + _str(%s))" % (sc, rc), out, pad)
            return
        if k in ("add", "subtract", "multiply", "divide"):
            v, tgt = st.a, st.b
            rc, tgt2 = self.target_read(tgt, out, pad)
            ec = _ExprCompiler(self, [], 0)
            op = {"add": "add", "subtract": "sub", "multiply": "mul", "divide": "truediv"}[k]
            code, kind = ec.gen_binop(op, (rc, "any"), v)
            self.emit_write(tgt2, code, out, pad)
            return
        if k == "setdelim":
            attr = "itemdel" if st.a == "itemdelimiter" else "linedel"
            out.append("%s_S.%s = _str(%s)" % (pad, attr, st.b[0]))
            return
        if k == "get":
            ref = self.value_with_copy(st.a, out, pad)
            out.append("%sv_it = %s" % (pad, ref))
            return
        if k == "bindecode":
            out.append("%s_bd = _binarydecode(%s, %s, 1)" % (pad, st.a[0], st.b[0]))
            out.append("%s%s = _bd[1][0]" % (pad, st.c))
            out.append("%sv_it = _bd[0]" % pad)
            return
        if k == "exit_repeat":
            if loop_depth == 0:
                self.fail("`exit repeat` outside a repeat")
            out.append("%sbreak" % pad)
            return
        if k == "next_repeat":
            if loop_depth == 0:
                self.fail("`next repeat` outside a repeat")
            out.append("%scontinue" % pad)
            return
        if k == "exit_handler":
            out.append("%sreturn ''" % pad)
            return
        if k == "return":
            out.append("%sreturn %s" % (pad, st.a[0]))
            return
        if k == "throw":
            if in_catch:
                self.fail("`throw` inside a `catch` block is swallowed by the engine (OXT-ENGINE-NOTES 3.2); refused (D5)")
            out.append("%sraise _LCThrow(_str(%s))" % (pad, st.a[0]))
            return
        if k == "call":
            self.emit_call(st, out, pad)
            return
        self.fail("internal: no codegen for %s" % k)

    def emit_call(self, st, out, pad):
        low, args, h = st.a, st.b, st.c
        cells = []
        argcodes = []
        for i, (code, kind, atoks) in enumerate(args):
            if h is not None and h.byref[i]:
                name = atoks[0].val
                pyname = self.var_write(name)
                cell = self.tmp()
                out.append("%s%s = [%s]" % (pad, cell, pyname))
                cells.append((cell, pyname))
                argcodes.append(cell)
            else:
                argcodes.append(code)
        out.append("%s_S.result = h_%s(%s)" % (pad, low, ", ".join(argcodes)))
        for cell, pyname in cells:
            out.append("%s%s = %s[0]" % (pad, pyname, cell))

    def emit_if(self, st, out, ind, loop_depth, in_catch, in_try):
        pad = "    " * ind
        first = True
        for cond_toks, body in st.a:
            self.cur_line, self.cur_text = st.line, st.text
            ep = _ExprCompiler(self, cond_toks + [Tok("end", "", 0)], 0)
            c, kind = ep.parse_full()
            out.append("%s%s %s:" % (pad, "if" if first else "elif", ep.truth(c, kind)))
            first = False
            self.emit_block(body, out, ind + 1, loop_depth, in_catch, in_try)
        if st.b is not None:
            out.append("%selse:" % pad)
            self.emit_block(st.b, out, ind + 1, loop_depth, in_catch, in_try)

    def emit_repeat_with(self, st, out, ind, loop_depth, in_catch, in_try):
        pad = "    " * ind
        var, a, b, (down, body) = st.a, st.b, st.c, st.d
        pyname = self.var_write(var.val)
        ta, tb = self.tmp(), self.tmp()
        out.append("%s%s = _int_bound(%s)" % (pad, ta, a[0]))
        out.append("%s%s = _int_bound(%s)" % (pad, tb, b[0]))
        if down:
            out.append("%sfor %s in range(%s, %s - 1, -1):" % (pad, pyname, ta, tb))
        else:
            out.append("%sfor %s in range(%s, %s + 1):" % (pad, pyname, ta, tb))
        self.emit_block(body, out, ind + 1, loop_depth + 1, in_catch, in_try)

    def emit_repeat_while(self, st, out, ind, loop_depth, in_catch, in_try):
        pad = "    " * ind
        ep = _ExprCompiler(self, [], 0)
        out.append("%swhile %s:" % (pad, ep.truth(st.a[0], st.a[1])))
        self.emit_block(st.d, out, ind + 1, loop_depth + 1, in_catch, in_try)

    def emit_repeat_forever(self, st, out, ind, loop_depth, in_catch, in_try):
        pad = "    " * ind
        out.append("%swhile True:" % pad)
        self.emit_block(st.d, out, ind + 1, loop_depth + 1, in_catch, in_try)

    def emit_repeat_each(self, st, out, ind, loop_depth, in_catch, in_try):
        pad = "    " * ind
        unit, var, e = st.a, st.b, st.c
        pyname = self.var_write(var.val)
        if unit == "item":
            src = "_split(_str(%s), _S.itemdel)" % e[0]
        elif unit == "line":
            src = "_split(_str(%s), _S.linedel)" % e[0]
        else:
            src = "_words(%s)" % e[0]
        out.append("%sfor %s in %s:" % (pad, pyname, src))
        self.emit_block(st.d, out, ind + 1, loop_depth + 1, in_catch, in_try)

    def emit_switch(self, st, out, ind, loop_depth, in_catch, in_try):
        pad = "    " * ind
        subj, segments = st.a, st.b
        n = len(segments)
        sv, si = self.tmp(), self.tmp()
        out.append("%s%s = %s" % (pad, sv, subj[0]))
        default_idx = None
        first = True
        for idx, (label, body, brk) in enumerate(segments):
            if label is None:
                default_idx = idx
                continue
            ec = _ExprCompiler(self, [], 0)
            cond, kind = ec.gen_binop("eq", (sv, "any"), label)
            out.append("%s%s %s: %s = %d" % (pad, "if" if first else "elif", cond, si, idx))
            first = False
        fallback = default_idx if default_idx is not None else n
        if first:
            out.append("%s%s = %d" % (pad, si, fallback))
        else:
            out.append("%selse: %s = %d" % (pad, si, fallback))
        last_break = -1
        for idx, (label, body, brk) in enumerate(segments):
            if body:
                out.append("%sif %d < %s <= %d:" % (pad, last_break, si, idx))
                self.emit_block(body, out, ind + 1, loop_depth, in_catch, in_try)
            if brk:
                last_break = idx

    def emit_try(self, st, out, ind, loop_depth, in_catch, in_try):
        pad = "    " * ind
        body, var, cbody = st.a, st.b, st.c
        out.append("%stry:" % pad)
        self.emit_block(body, out, ind + 1, loop_depth, in_catch, True)
        exc = self.tmp()
        out.append("%sexcept _LCThrow as %s:" % (pad, exc))
        pyname = self.var_write(var.val)
        out.append("%s    %s = %s.value" % (pad, pyname, exc))
        self.emit_block(cbody, out, ind + 1, loop_depth, True, in_try)

    # ----------------------------------------------------------- assembly
    def assemble(self, body):
        h = self.h
        params = []
        for p, r in zip(h.params, h.byref):
            params.append(("r_%s=None" % p) if r else ("v_%s=''" % p))
        src = ["def h_%s(%s):" % (h.low, ", ".join(params))]
        if self.script_writes:
            src.append("    global %s" % ", ".join("s_" + s for s in sorted(self.script_writes)))
        for p, r in zip(h.params, h.byref):
            if r:
                src.append("    if r_%s is None: r_%s = ['']" % (p, p))
                src.append("    v_%s = r_%s[0]" % (p, p))
            elif p in self.written_params:
                src.append("    if v_%s.__class__ is dict: v_%s = _copy(v_%s)" % (p, p, p))
        locs = [pn for low, pn in self.scope.items() if low not in self.params]
        if self.uses_it:
            locs.append("v_it")
        if locs:
            src.append("    %s = ''" % " = ".join(sorted(locs)))
        bodytext = "\n".join(body)
        uses_delims = ("_S.itemdel" in bodytext) or ("_S.linedel" in bodytext)
        if uses_delims:
            # itemDelimiter / lineDelimiter are HANDLER-LOCAL properties (D21):
            # each handler starts at the defaults and the caller's values are
            # restored on exit.
            src.append("    _sd_i = _S.itemdel; _sd_l = _S.linedel")
            src.append("    _S.itemdel = ','; _S.linedel = '\\n'")
        src.append("    _L = %d" % h.lineno)
        src.append("    try:")
        src.extend(body)
        src.append("    except _LCThrow:")
        src.append("        raise")
        src.append("    except ModelError as _e:")
        src.append("        _e.add_frame(%r, %r, _L)" % (h.name, h.srcname))
        src.append("        raise")
        src.append("    except RecursionError:")
        src.append("        raise ModelError('recursion too deep', [(%r, %r, _L)])" % (h.name, h.srcname))
        src.append("    except Exception as _e:")
        src.append("        raise ModelError('%%s: %%s' %% (_e.__class__.__name__, _e), [(%r, %r, _L)])" % (h.name, h.srcname))
        if any(h.byref) or uses_delims:
            src.append("    finally:")
            for p, r in zip(h.params, h.byref):
                if r:
                    src.append("        r_%s[0] = v_%s" % (p, p))
            if uses_delims:
                src.append("        _S.itemdel = _sd_i; _S.linedel = _sd_l")
        src.append("    return ''")
        return "\n".join(src) + "\n"


# ==================================================================== model --

_HEADER_RE = re.compile(r"^(?:(private)\s+)?(function|command|on)\s+([A-Za-z_]\w*)\s*(.*)$", re.I)
_CONST_RE = re.compile(r"^constant\s+([A-Za-z_]\w*)\s*=\s*(.+)$", re.I)
_LOCAL_RE = re.compile(r"^local\s+(.+)$", re.I)


class Model(object):
    """Model(sources=[(name, text), ...]) - every source shares ONE script
    scope (the engine's `include` inlines the modules into one script, and
    the combined lib build is one script). Handlers compile on first call;
    compile_all() compiles everything not overridden so a refusal surfaces
    before any test runs."""

    def __init__(self, sources, overrides=None, count_statements=False):
        self.handlers = {}          # low -> _Handler
        self.script_locals = set()  # low
        self.constants = {}         # low -> value
        self.constant_names = {}    # low -> declared spelling
        self.overrides = {}         # low -> callable
        self.count_statements = count_statements
        self.state = _State()
        self.ns = dict(_RUNTIME)
        self.ns["_S"] = self.state
        self.sources = []
        for name, text in sources:
            self._load(name, text)
        for low in self.handlers:
            self.ns["h_" + low] = self._stub(low)
        for low in self.script_locals:
            self.ns["s_" + low] = ""
        if overrides:
            for name, fn in overrides.items():
                self.override(name, fn)

    # ------------------------------------------------------------ loading
    def _load(self, srcname, text):
        self.sources.append(srcname)
        lines = _prepare_lines(text, srcname)
        i = 0
        n = len(lines)
        first = True
        while i < n:
            ln, tx = lines[i]
            i += 1
            if tx == "":
                continue
            if first and re.match(r'^script\s+"', tx, re.I):
                first = False
                continue
            first = False
            if re.match(r"^<\?lc\s*$", tx) or tx == "?>":
                continue
            m = _CONST_RE.match(tx)
            if m:
                self._declare_constant(srcname, ln, m.group(1), m.group(2).strip())
                continue
            m = _LOCAL_RE.match(tx)
            if m:
                for piece in m.group(1).split(","):
                    nm = piece.strip()
                    if not re.match(r"^[A-Za-z_]\w*$", nm):
                        raise ModelError("%s:%d: bad script-level local declaration: %s" % (srcname, ln, tx))
                    low = nm.lower()
                    if low in self.script_locals or low in self.constants:
                        raise ModelError("%s:%d: script-level name `%s` declared twice (the engine: hard compile "
                                         "error, OXT-ENGINE-NOTES 1.6)" % (srcname, ln, nm))
                    if low in _RESERVED:
                        raise ModelError("%s:%d: script-level local `%s` is a reserved word in this model" % (srcname, ln, nm))
                    self.script_locals.add(low)
                continue
            m = _HEADER_RE.match(tx)
            if m:
                kind = m.group(2).lower()
                kind = "function" if kind == "function" else "command"
                name = m.group(3)
                params, byref = self._parse_params(srcname, ln, name, m.group(4))
                body = []
                endre = re.compile(r"^end\s+%s\s*$" % re.escape(name), re.I)
                closed = False
                while i < n:
                    ln2, tx2 = lines[i]
                    i += 1
                    if endre.match(tx2):
                        closed = True
                        break
                    if _HEADER_RE.match(tx2):
                        raise ModelError("%s:%d: handler `%s` opened inside handler `%s` (missing `end %s`?)"
                                         % (srcname, ln2, tx2.split()[1] if len(tx2.split()) > 1 else tx2, name, name))
                    body.append((ln2, tx2))
                if not closed:
                    raise ModelError("%s:%d: handler `%s` has no `end %s`" % (srcname, ln, name, name))
                low = name.lower()
                if low in self.handlers:
                    prev = self.handlers[low]
                    raise ModelError("%s:%d: handler `%s` already defined at %s:%d (the engine: compile error)"
                                     % (srcname, ln, name, prev.srcname, prev.lineno))
                if low in _BUILTINS or low in _CONSTANTS or low in _RESERVED:
                    raise ModelError("%s:%d: handler name `%s` collides with a modelled builtin/keyword" % (srcname, ln, name))
                self.handlers[low] = _Handler(name, kind, params, byref, srcname, ln, body)
                continue
            raise ModelError("%s:%d: loose top-level statement is not modelled: %s" % (srcname, ln, tx))

    def _parse_params(self, srcname, ln, hname, text):
        params, byref = [], []
        text = text.strip()
        if not text:
            return params, byref
        for piece in text.split(","):
            p = piece.strip()
            ref = False
            if p.startswith("@"):
                ref = True
                p = p[1:].strip()
            if not re.match(r"^[A-Za-z_]\w*$", p):
                raise ModelError("%s:%d: bad parameter `%s` in handler %s" % (srcname, ln, piece.strip(), hname))
            low = p.lower()
            if low in params:
                raise ModelError("%s:%d: parameter `%s` declared twice in handler %s" % (srcname, ln, p, hname))
            if low in _RESERVED:
                raise ModelError("%s:%d: parameter `%s` is a reserved word in this model (handler %s)" % (srcname, ln, p, hname))
            params.append(low)
            byref.append(ref)
        return params, byref

    def _declare_constant(self, srcname, ln, name, valtext):
        low = name.lower()
        if low in self.constants or low in self.script_locals:
            raise ModelError("%s:%d: script-level name `%s` declared twice" % (srcname, ln, name))
        toks = _tokenize(valtext, "%s:%d" % (srcname, ln))
        neg = False
        i = 0
        if toks[0].kind == "op" and toks[0].val == "-":
            neg = True
            i = 1
        t = toks[i]
        if toks[i + 1].kind != "end":
            raise ModelError("%s:%d: constant `%s` must be a single literal (OXT-ENGINE-NOTES 1.3): %s"
                             % (srcname, ln, name, valtext))
        if t.kind == "num":
            v = _ExprCompiler(None, [], 0).num_value(t.val)
            if neg:
                v = -v
        elif t.kind == "str" and not neg:
            v = t.val[1:-1]
        elif t.kind == "id" and t.low in _CONSTANTS and not neg:
            v = _CONSTANTS[t.low]
        else:
            raise ModelError("%s:%d: constant `%s` must be a numeric or string literal: %s" % (srcname, ln, name, valtext))
        self.constants[low] = v
        self.constant_names[low] = name

    # ---------------------------------------------------------- compiling
    def _stub(self, low):
        model = self

        def stub(*args):
            fn = model._compile(low)
            return fn(*args)
        stub.__name__ = "stub_" + low
        return stub

    def _compile(self, low):
        h = self.handlers[low]
        if h.fn is not None:
            return h.fn
        if low in self.overrides:
            return self.ns["h_" + low]
        hc = _HandlerCompiler(self, h)
        src = hc.compile()
        h.pysrc = src
        try:
            code = compile(src, "<lcs %s %s:%d>" % (h.name, h.srcname, h.lineno), "exec")
        except SyntaxError as e:
            raise ModelError("internal codegen error compiling handler %s (%s:%d): %s\n--- generated python ---\n%s"
                             % (h.name, h.srcname, h.lineno, e, src))
        exec(code, self.ns)
        h.fn = self.ns["h_" + low]
        return h.fn

    def compile_all(self, skip=()):
        """Compile every handler that is not overridden (and not in `skip`).
        Raises ONE ModelError listing every refusal, so a run cannot start
        on a corpus that is partly outside the subset."""
        skip = set(s.lower() for s in skip)
        problems = []
        for low in sorted(self.handlers):
            if low in self.overrides or low in skip:
                continue
            try:
                self._compile(low)
            except ModelError as e:
                problems.append(str(e))
        if problems:
            raise ModelError("%d handler(s) refused:\n\n%s" % (len(problems), "\n\n".join(problems)))
        return len([1 for low in self.handlers if self.handlers[low].fn is not None])

    def python_source(self, name):
        low = name.lower()
        self._compile(low)
        return self.handlers[low].pysrc

    # ------------------------------------------------------------ running
    def override(self, name, fn):
        """Replace handler `name` with a Python callable (a native hook).
        Arguments arrive as model values (str / int / float / bool / dict);
        a by-reference parameter arrives as a one-element list cell. Install
        overrides BEFORE compiling callers so the compiler can resolve the
        name; an override of a source handler is never compiled."""
        low = name.lower()
        self.overrides[low] = fn
        self.ns["h_" + low] = fn
        if low in self.handlers:
            self.handlers[low].fn = None

    def call(self, name, *args):
        """Call a handler with by-value arguments; returns its value
        (empty for a command that does not return)."""
        low = name.lower()
        if low not in self.handlers and low not in self.overrides:
            raise ModelError("no handler named `%s`" % name)
        fn = self.ns["h_" + low]
        h = self.handlers.get(low)
        if h is not None and low not in self.overrides:
            if len(args) > len(h.params):
                raise ModelError("`%s` called with %d arguments but declares %d (D8)" % (h.name, len(args), len(h.params)))
            cargs = []
            for i, a in enumerate(args):
                cargs.append([a] if h.byref[i] else a)
            for i in range(len(args), len(h.params)):
                if h.byref[i]:
                    cargs.append([""])
            return fn(*cargs)
        return fn(*args)

    def get_local(self, name):
        low = name.lower()
        if low not in self.script_locals:
            raise ModelError("no script-level local named `%s`" % name)
        return self.ns["s_" + low]

    def set_local(self, name, value):
        low = name.lower()
        if low not in self.script_locals:
            raise ModelError("no script-level local named `%s`" % name)
        self.ns["s_" + low] = value

    @property
    def the_result(self):
        return self.state.result

    @property
    def item_delimiter(self):
        return self.state.itemdel

    @property
    def line_delimiter(self):
        return self.state.linedel

    @property
    def statements_executed(self):
        return self.state.nstmt

    # exported semantics, for harnesses that need the model's own operators
    @staticmethod
    def eq(a, b):
        return _eq(a, b)

    @staticmethod
    def to_text(v):
        return _str(v)

    @staticmethod
    def to_number(v):
        return _num(v)


def strip_server_tags(text):
    """Drop a leading `<?lc` line and a trailing `?>` line (a qr/*.lc module);
    the line numbering of the remaining text is preserved."""
    lines = text.split("\n")
    if lines and lines[0].strip() == "<?lc":
        lines[0] = ""
    j = len(lines) - 1
    while j >= 0 and lines[j].strip() == "":
        j -= 1
    if j >= 0 and lines[j].strip() == "?>":
        lines[j] = ""
    return "\n".join(lines)


def strip_script_header(text):
    """Drop a first line of the form `script "Name"` (a script-only stack)."""
    lines = text.split("\n")
    if lines and re.match(r'^\s*script\s+"', lines[0]):
        lines[0] = ""
    return "\n".join(lines)
