script "xtQRdecoderDemo"
-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Seth Morrow
-- Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
-- ZXing is Apache-2.0; see the NOTICE file for full attribution.

-- xtQRdecoder-demo.livecodescript - the xtQRdecoder showcase stack.
--
-- A self-building, single-file demo of the pure-xTalk QR decoder, laid out
-- the way the xTalk Suite's demos are: paste this whole file into a stack
-- script and the stack builds its own tabbed window on open - no design
-- work in the IDE, no `start using`, no second file. The library itself is
-- CARRIED inside this script between the embed sentinels below, so every
-- qrDecode* function is in scope the moment the script compiles.
--
-- Tabs:
--   Decode    load an image (file picker, paste, drag-and-drop, or one of the
--             seven samples that travel inside this stack), tick the hints,
--             and decode it - robustly or in a single pass - with every result
--             key the library returns laid out beside the text.
--   Pipeline  the same image walked through the library one stage at a time
--             (image decode, greyscale, binarize, detect, sample, decode) with
--             timings, the finder centres, and the de-skewed grid as block art.
--   Samples   the seven embedded images - versions 1 and 3, a mirrored symbol,
--             an inverted one, UTF-8 bytes, 1 px per module, a 25-degree tilt
--             and a real photograph - decoded in one click, each line a
--             PASS/FAIL against its known text: an engine record for this
--             machine that a pass report can quote.
--   About     what the library is, its API in one screen, and the boot
--             self-check log.
--
-- HOW TO USE. In OpenXTalk (or any 9.6.3+ xTalk engine): File > New
-- Mainstack, Object > Stack Script, paste ALL of this file, Apply, then CLOSE
-- the stack window and REOPEN it (or `send "preOpenStack" to this stack`).
-- Opening this .livecodescript file itself loads the script and builds no
-- window - that is the engine, not this demo (xtalk-suite engine notes 5.5).
-- Desktop only: `answer file`, the clipboard and drag-and-drop are desktop
-- features; the mobile path is lib/examples/scanButton.livecodescript.
--
-- HONESTY (the suite convention): the decoder's unit harness and golden
-- photographs were engine-passed on a 9.6.11-class xTalk SERVER build at
-- the 0.1.0 release; everything since, this stack included, is verified
-- statically and under the headless model and NEEDS AN OXT PASS. The boot
-- self-check and the Samples tab exist so that pass can be quoted rather
-- than described: their PASS/FAIL lines are the record (docs/VERIFICATION.md).
--
-- THE LOOK is the suite UI kit v2, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript, vendored byte-identical from the
-- xTalk Suite; tools/sync_demo_embeds.py --check holds the copy). Change
-- the look in the master, never here. The boot self-check block is carried
-- the same way (master: tools/demo-selfcheck.livecodescript).

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync_demo_embeds.py) >>>
-- Pasted from lib/xtQRdecoder.livecodescript so this demo runs with NO
-- `start using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync_demo_embeds.py` instead. The qr/*.lc modules stay
-- the single source of truth, and lib/xtQRdecoder.livecodescript is the
-- right dependency for a real project.
--
-- The library comes FIRST because OpenXTalk resolves script-level
-- constants and locals by lexical position.

-- ---- lib/xtQRdecoder.livecodescript ----
-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Seth Morrow
--
-- xtQRdecoder - a pure xTalk QR Code decoder, combined into a single
-- script-only stack for use on desktop, mobile, and server.
--
-- This file is GENERATED from the qr/*.lc modules by
-- tools/build_livecodescript.py - do not edit it by hand; edit the modules and
-- rebuild. The modules are the single source of truth.
--
-- A line-for-line port of khanamiryan/php-qrcode-detector-decoder, itself a
-- hand-port of ZXing (Apache-2.0). See the repository NOTICE file for full
-- attribution.
--
-- USAGE (desktop / mobile / server) - load it once, e.g. in preOpenStack,
-- from the folder that holds your own stack file:
--   local tDir
--   put the effective filename of this stack into tDir
--   set the itemDelimiter to "/"
--   delete the last item of tDir          -- the folder of the host stack
--   start using stack (tDir & "/xtQRdecoder.livecodescript")
--   put qrDecodeResultRobust(url ("binfile:" & tImagePath), "TRY_HARDER") into tRes
--   if tRes["error"] is empty then answer tRes["text"]
-- (There is no `folder` property of a stack; `the effective filename of this
-- stack` is the engine-proven way to locate a sibling file.)
--
-- PUBLIC API (see the README for the full reference):
--   qrDecodeFromData(imageBytes [,hints])        -> text  (empty on failure)
--   qrDecodeFromFile(path [,hints])              -> text  (empty on failure)
--   qrDecodeResult(imageBytes [,hints])          -> result array (never throws)
--   qrDecodeResultRobust(imageBytes [,hints[,maxDim]]) -> result array (best for photos)
-- =====================================================================


-- ===================== module: qrCompat ================
-- =====================================================================
-- qrCompat.lc  -  Java/PHP integer + bitwise compatibility layer
-- Part of the xTalk port of khanamiryan/php-qrcode-detector-decoder
-- (itself a hand-port of ZXing, Apache-2.0).
--
-- Target: 9.6.3-era xTalk engines and earlier, including headless server builds.
-- Spec reference: section 6, "the hard part: integer, bitwise, helper semantics".
--
-- WHY THIS MODULE EXISTS
-- ZXing assumes Java `int` == signed 32-bit two's-complement that WRAPS on
-- overflow and supports `>>>` (unsigned shift). PHP emulates that imperfectly.
-- xTalk differs again:
--   * bitAnd/bitOr/bitXor/bitNot operate on UNSIGNED 32-bit (0 .. 2^32-1).
--   * arithmetic never wraps; numbers are IEEE-754 doubles (exact <= 2^53).
--   * there are NO shift operators (<<, >>, >>>) in xTalk.
--   * there are NO 0x.. hex literals in xTalk.
-- Every bit operation in the port routes through the helpers below so the
-- 32-bit contract is honoured bit-for-bit. The canonical model (spec 6.1):
-- all bit-packed words are stored UNSIGNED in [0, 2^32). A Java -1 is 4294967295.
--
-- XTALK GOTCHAS BAKED INTO THIS FILE (these tripped up the spec's inline
-- examples, which are pseudo-xTalk, not all valid as written):
--   1. No 0x.. hex literals: hex values are written in decimal with the hex
--      shown in a trailing comment.
--   2. bitAnd/bitOr/bitXor have LOWER precedence than '=', '<', '+', etc. in
--      xTalk, so EVERY bitwise sub-expression is wrapped in parentheses.
--   3. qr_shl() is precision-safe: the spec's `qr_u32(a * (2^n))` overflows 2^53 and
--      silently loses LOW-order bits when shifting a full 32-bit word left by a
--      large count (e.g. BitMatrix.getEnclosingRectangle). See qr_shl() below.
--   4. binaryDecode needs an OUTPUT variable; the spec's one-liner for
--      qr_floatToIntBits is not valid xTalk. Corrected below.
-- =====================================================================


-- ---- universal 32-bit constants (decimal; hex shown in comments) -----
constant kUInt32   = 4294967296     -- 2^32
constant kUIntMax  = 4294967295     -- 0xFFFFFFFF   (Java -1 in our unsigned model)
constant kMaxInt32 = 2147483648     -- 2^31; sign-bit threshold (NOT Integer.MAX_VALUE = 2^31-1)


-- ---- core normalisation ----------------------------------------------
-- Normalise any integer into the unsigned 32-bit range [0, 2^32).
-- Java/PHP -1 -> 4294967295 ; -16777216 -> 4278190080 ; 2^32 -> 0.
function qr_u32 n
   put n mod kUInt32 into n
   if n < 0 then add kUInt32 to n
   return n
end qr_u32

-- Mask to a single unsigned byte (the ubiquitous Java "& 0xFF").
function qr_u8 n
   return (n bitAnd 255)            -- 0xFF
end qr_u8


-- ---- shift emulation (Java <<, >>>, >>) ------------------------------
-- xTalk has no shift operators; emulate with arithmetic. The shift count
-- is masked to 0..31 with `bitAnd 31`, exactly Java's `count & 31` for 32-bit
-- ints (a negative count maps to its unsigned low five bits: -1 -> 31; `mod`
-- would keep the sign and yield 0.5 for qr_shl(1, -1)).

-- Logical/arithmetic LEFT shift, 32-bit  (Java: a << n).
-- PRECISION-SAFE: drop the bits that would shift out past bit 31 BEFORE
-- multiplying, so the product stays < 2^32 (well under the 2^53 exact limit).
-- A naive qr_u32(a * 2^n) loses low bits when a is large and n is large.
function qr_shl a, n
   local m
   put (n bitAnd 31) into n
   put qr_u32(a) into a
   put (2 ^ (32 - n)) into m         -- modulus discards the out-shifted high bits
   return ((a mod m) * (2 ^ n))      -- result is already in [0, 2^32)
end qr_shl

-- UNSIGNED right shift  (Java: a >>> n). Operand treated as unsigned 32-bit.
-- Replaces the PHP shims uRShift() and sdvig3().
function qr_uShr a, n
   put (n bitAnd 31) into n
   return (qr_u32(a) div (2 ^ n))
end qr_uShr

-- ARITHMETIC right shift  (Java: a >> n) on a word interpreted as SIGNED 32-bit.
-- Returns the unsigned 32-bit BIT-PATTERN of the result (i.e. sign-extended).
function qr_aShr a, n
   local d
   put (n bitAnd 31) into n
   put qr_u32(a) into a
   put (2 ^ n) into d
   if a < kMaxInt32 then
      return (a div d)                                  -- top bit clear: same as >>>
   else
      -- top bit set (negative): OR in the high sign-extension bits.
      -- (kUInt32 - (kUInt32 div d)) is exactly the top-n-bits mask.
      return qr_u32(((a div d) bitOr (kUInt32 - (kUInt32 div d))))
   end if
end qr_aShr


-- ---- Integer.qr_numberOfTrailingZeros -----------------------------------
-- Count low-order zero bits; i == 0 -> 32. Used by BitArray.getNextSet/Unset.
function qr_numberOfTrailingZeros i
   local n
   put qr_u32(i) into i
   if i = 0 then return 32
   put 0 into n
   repeat while (i bitAnd 1) = 0
      add 1 to n
      put (i div 2) into i
   end repeat
   return n
end qr_numberOfTrailingZeros


-- ---- Java String.qr_hashCode  (h = 31*h + c) over BYTES -----------------
-- Only used for equality/dedup, never on the decode-critical path. qr_u32 each
-- step so the value matches Java's bit pattern exactly.
function qr_hashCode s
   local h, k
   put 0 into h
   repeat with k = 1 to the number of bytes of s
      put qr_u32((31 * h) + byteToNum(byte k of s)) into h
   end repeat
   return h
end qr_hashCode


-- ---- Float.qr_floatToIntBits --------------------------------------------
-- IEEE-754 single-precision raw bits. The spec's one-liner is NOT valid
-- xTalk (binaryDecode requires an output variable) -- corrected here.
-- binaryEncode/binaryDecode use machine byte order on both sides, so the
-- round-trip is endian-safe. Likely unused on the QR path (it appears only
-- in ResultPoint / PerspectiveTransform hashing) -- included for completeness.
function qr_floatToIntBits f
   local tBits
   get binaryDecode("i", binaryEncode("f", f), tBits)
   return qr_u32(tBits)
end qr_floatToIntBits


-- ---- qr_fillArray  (customFunctions.php) -------------------------------
-- Build a dense, 0-based array of pCount copies of pValue starting at pIndex.
-- QUIRK preserved from PHP: pCount <= 0 returns a SINGLE-element array (one
-- slot holding pValue). BitMatrix / binarizer sizing relies on this in
-- degenerate cases. In every real call site pIndex == 0 and pValue == 0, so
-- this reproduces the PHP "[0]" result, and the integer layer (incl. this
-- helper) is engine-verified by suite_qrCompat. The degenerate pCount<=0 branch
-- is not reached by the QR path; it is kept only for source fidelity.
function qr_fillArray pIndex, pCount, pValue
   local tArr, k
   if pCount <= 0 then
      put pValue into tArr[pIndex]
      return tArr
   end if
   repeat with k = pIndex to (pIndex + pCount - 1)
      put pValue into tArr[k]
   end repeat
   return tArr
end qr_fillArray


-- ---- System.qr_arraycopy  (in place, for performance) -------------------
-- Copy pLen elements from pSrc[pSrcPos..] to pDest[pDestPos..]. 0-based,
-- matching the source. Pass BOTH arrays by reference (@) so the large bit /
-- luminance arrays are never copied by value (spec 5, 11).
-- CAVEAT: forward copy. If src and dest alias with overlapping FORWARD regions
-- the result differs from Java's temp-buffer semantics. No such overlapping
-- self-copy occurs on the QR decode path.
command qr_arraycopy @pSrc, pSrcPos, @pDest, pDestPos, pLen
   local k
   repeat with k = 0 to (pLen - 1)
      put pSrc[pSrcPos + k] into pDest[pDestPos + k]
   end repeat
end qr_arraycopy


-- ---- string byte access (0-based, like PHP $s[$i]) -------------------
-- Returns the unsigned byte value (0..255) at 0-based index i of string s.
-- Keeps call sites readable and 0-based (spec 6.7).
function qr_byteAt s, i
   return byteToNum(byte (i + 1) of s)
end qr_byteAt

-- ===================== module: genericGF ===============
-- =====================================================================
-- genericGF.lc - Galois field GF(256) for QR Reed-Solomon.
-- Port of ZXing Common\Reedsolomon\GenericGF (only QR_CODE_FIELD_256).
-- Spec section 8.5 "ReedSolomon group". Requires: qrCompat.lc, genericGFPoly.lc.
--
-- QR field parameters: primitive 0x011D (285), size 256, generatorBase 0.
-- The exp/log tables are built once (lazily) and kept script-local; all
-- field arithmetic goes through the gf_* functions so callers never touch
-- the tables directly.
--
-- A "polynomial" in this port is simply its 0-based coefficient array, where
-- index 0 is the HIGHEST-degree coefficient (matching ZXing). See genericGFPoly.lc.
-- =====================================================================

constant kGFSize      = 256
constant kGFPrimitive = 285     -- 0x011D
constant kGFGenBase   = 0

local sExp, sLog, sGFReady

-- Build the antilog (exp) and log tables. Safe to call repeatedly.
command gf_init
   local x, i
   put empty into sExp
   put empty into sLog
   put 1 into x
   repeat with i = 0 to (kGFSize - 1)
      put x into sExp[i]
      put (x * 2) into x                 -- generator alpha = 2
      if x >= kGFSize then put ((x bitXor kGFPrimitive) bitAnd (kGFSize - 1)) into x
   end repeat
   repeat with i = 0 to (kGFSize - 2)
      put i into sLog[sExp[i]]
   end repeat
   put 0 into sLog[0]                     -- never used, but defined
   put true into sGFReady
end gf_init

-- lazy guard so callers don't have to remember gf_init
command gf_ensure
   if sGFReady is not true then gf_init
end gf_ensure

-- a + b (== a - b) in GF(2^n) is XOR
function gf_addOrSubtract a, b
   return (a bitXor b)
end gf_addOrSubtract

function gf_exp a
   gf_ensure
   return sExp[a]
end gf_exp

function gf_log a
   gf_ensure
   if a = 0 then throw "RS: log(0) is undefined"
   return sLog[a]
end gf_log

function gf_inverse a
   gf_ensure
   if a = 0 then throw "RS: inverse(0) is undefined"
   return sExp[(kGFSize - sLog[a] - 1)]
end gf_inverse

function gf_multiply a, b
   gf_ensure
   if (a = 0) or (b = 0) then return 0
   return sExp[((sLog[a] + sLog[b]) mod (kGFSize - 1))]
end gf_multiply

function gf_getSize
   return kGFSize
end gf_getSize

function gf_getGeneratorBase
   return kGFGenBase
end gf_getGeneratorBase

-- buildMonomial(degree, coefficient) -> polynomial  coefficient * x^degree
function gf_buildMonomial pDegree, pCoeff
   local tC, i
   if pDegree < 0 then throw "RS: buildMonomial negative degree"
   if pCoeff = 0 then return poly_zero()
   put pCoeff into tC[0]
   repeat with i = 1 to pDegree
      put 0 into tC[i]
   end repeat
   return poly_new(tC)
end gf_buildMonomial

-- ===================== module: genericGFPoly ===========
-- =====================================================================
-- genericGFPoly.lc - polynomials over GF(256).
-- Port of ZXing Common\Reedsolomon\GenericGFPoly. Spec section 8.5.
-- Requires: qrCompat.lc, genericGF.lc.
--
-- REPRESENTATION: a polynomial is its 0-based coefficient array; index 0 is
-- the HIGHEST-degree coefficient (ZXing convention). Arrays are dense
-- (keys 0..n-1 all present), so "the number of elements" == length.
-- Polynomials are treated as immutable: every operation returns a NEW array.
-- The single GF(256) field is implicit (gf_* in genericGF.lc).
-- =====================================================================

-- the zero / one constant polynomials
function poly_zero
   local t
   put 0 into t[0]
   return t
end poly_zero

function poly_one
   local t
   put 1 into t[0]
   return t
end poly_one

-- Build a normalised polynomial from a dense 0-based coefficient array,
-- stripping leading (high-degree) zeros exactly as ZXing's constructor does.
function poly_new pC
   local n, firstNonZero, tOut, i
   put the number of elements of pC into n
   if n = 0 then throw "RS: empty coefficients"
   if (n > 1) and (pC[0] = 0) then
      put 1 into firstNonZero
      repeat while (firstNonZero < n) and (pC[firstNonZero] = 0)
         add 1 to firstNonZero
      end repeat
      if firstNonZero = n then
         put 0 into tOut[0]                       -- the constant polynomial "0"
         return tOut
      end if
      repeat with i = firstNonZero to (n - 1)
         put pC[i] into tOut[i - firstNonZero]
      end repeat
      return tOut
   end if
   -- already normalised (or single element): return a copy
   repeat with i = 0 to (n - 1)
      put pC[i] into tOut[i]
   end repeat
   return tOut
end poly_new

function poly_isZero p
   return (p[0] = 0)
end poly_isZero

function poly_degree p
   return ((the number of elements of p) - 1)
end poly_degree

-- coefficient of x^pDegree
function poly_getCoefficient p, pDegree
   return p[((the number of elements of p) - 1 - pDegree)]
end poly_getCoefficient

-- evaluate the polynomial at x = a in GF(256) (Horner's method)
function poly_evaluateAt p, a
   local n, tRes, i
   put the number of elements of p into n
   if a = 0 then return poly_getCoefficient(p, 0)     -- the x^0 coefficient
   if a = 1 then
      put 0 into tRes
      repeat with i = 0 to (n - 1)
         put gf_addOrSubtract(tRes, p[i]) into tRes
      end repeat
      return tRes
   end if
   put p[0] into tRes
   repeat with i = 1 to (n - 1)
      put gf_addOrSubtract(gf_multiply(a, tRes), p[i]) into tRes
   end repeat
   return tRes
end poly_evaluateAt

-- (this poly) + (other poly)
function poly_addOrSubtract p, q
   local smaller, larger, sumDiff, lengthDiff, lgN, smN, i
   if poly_isZero(p) then return q
   if poly_isZero(q) then return p
   if (the number of elements of p) > (the number of elements of q) then
      put q into smaller
      put p into larger
   else
      put p into smaller
      put q into larger
   end if
   put the number of elements of larger into lgN
   put the number of elements of smaller into smN
   put (lgN - smN) into lengthDiff
   repeat with i = 0 to (lengthDiff - 1)
      put larger[i] into sumDiff[i]
   end repeat
   repeat with i = lengthDiff to (lgN - 1)
      put gf_addOrSubtract(smaller[i - lengthDiff], larger[i]) into sumDiff[i]
   end repeat
   return poly_new(sumDiff)
end poly_addOrSubtract

-- (this poly) * (other poly)
function poly_multiply p, q
   local pn, qn, tProduct, i, j
   if poly_isZero(p) or poly_isZero(q) then return poly_zero()
   put the number of elements of p into pn
   put the number of elements of q into qn
   put qr_fillArray(0, (pn + qn - 1), 0) into tProduct
   repeat with i = 0 to (pn - 1)
      repeat with j = 0 to (qn - 1)
         put gf_addOrSubtract(tProduct[i + j], gf_multiply(p[i], q[j])) into tProduct[i + j]
      end repeat
   end repeat
   return poly_new(tProduct)
end poly_multiply

-- (this poly) * scalar
function poly_multiplyScalar p, pScalar
   local n, tProduct, i
   if pScalar = 0 then return poly_zero()
   if pScalar = 1 then return p
   put the number of elements of p into n
   repeat with i = 0 to (n - 1)
      put gf_multiply(p[i], pScalar) into tProduct[i]
   end repeat
   return poly_new(tProduct)
end poly_multiplyScalar

-- (this poly) * (coefficient * x^degree)
function poly_multiplyByMonomial p, pDegree, pCoeff
   local n, tProduct, i
   if pDegree < 0 then throw "RS: multiplyByMonomial negative degree"
   if pCoeff = 0 then return poly_zero()
   put the number of elements of p into n
   put qr_fillArray(0, (n + pDegree), 0) into tProduct
   repeat with i = 0 to (n - 1)
      put gf_multiply(p[i], pCoeff) into tProduct[i]
   end repeat
   return poly_new(tProduct)
end poly_multiplyByMonomial

-- divide this poly by other; returns array with keys "q" (quotient) and "r" (remainder)
function poly_divide p, q
   local quotient, remainder, dLT, invDLT, degreeDiff, tScale, term, iterQ, tRes
   if poly_isZero(q) then throw "RS: divide by zero polynomial"
   put poly_zero() into quotient
   put p into remainder
   put poly_getCoefficient(q, poly_degree(q)) into dLT
   put gf_inverse(dLT) into invDLT
   repeat while (poly_degree(remainder) >= poly_degree(q)) and (not poly_isZero(remainder))
      put (poly_degree(remainder) - poly_degree(q)) into degreeDiff
      put gf_multiply(poly_getCoefficient(remainder, poly_degree(remainder)), invDLT) into tScale
      put poly_multiplyByMonomial(q, degreeDiff, tScale) into term
      put gf_buildMonomial(degreeDiff, tScale) into iterQ
      put poly_addOrSubtract(quotient, iterQ) into quotient
      put poly_addOrSubtract(remainder, term) into remainder
   end repeat
   put quotient into tRes["q"]
   put remainder into tRes["r"]
   return tRes
end poly_divide

-- ===================== module: reedSolomonDecoder ======
-- =====================================================================
-- reedSolomonDecoder.lc - Euclidean Reed-Solomon decoder over GF(256).
-- Port of ZXing Common\Reedsolomon\ReedSolomonDecoder. Spec section 8.5.
-- Requires: qrCompat.lc, genericGF.lc, genericGFPoly.lc.
--
-- rs_decode mutates the received codeword array IN PLACE (passed by @),
-- correcting up to floor(twoS/2) errors. Throws "RS: ..." on failure
-- (the decoder layer maps that to a Checksum error per spec section 6.6).
-- =====================================================================

-- received: dense 0-based array of codewords (0..255); twoS = number of EC codewords
command rs_decode @pReceived, pTwoS
   local n, poly, syndromeCoeffs, noError, i, ev
   local syndrome, sigmaOmega, sigma, omega, errorLocations, errorMagnitudes
   local numLoc, tPosition

   put the number of elements of pReceived into n
   put poly_new(pReceived) into poly

   -- syndromes: S_i = poly( alpha^(i + generatorBase) ), generatorBase = 0
   put qr_fillArray(0, pTwoS, 0) into syndromeCoeffs
   put true into noError
   repeat with i = 0 to (pTwoS - 1)
      put poly_evaluateAt(poly, gf_exp(i + gf_getGeneratorBase())) into ev
      put ev into syndromeCoeffs[(pTwoS - 1 - i)]
      if ev <> 0 then put false into noError
   end repeat
   if noError then
      exit rs_decode                          -- clean codeword, nothing to correct
   end if

   put poly_new(syndromeCoeffs) into syndrome
   put rs_runEuclidean(gf_buildMonomial(pTwoS, 1), syndrome, pTwoS) into sigmaOmega
   put sigmaOmega["sigma"] into sigma
   put sigmaOmega["omega"] into omega
   put rs_findErrorLocations(sigma) into errorLocations
   put rs_findErrorMagnitudes(omega, errorLocations) into errorMagnitudes

   put the number of elements of errorLocations into numLoc
   repeat with i = 0 to (numLoc - 1)
      put (n - 1 - gf_log(errorLocations[i])) into tPosition
      if tPosition < 0 then throw "RS: bad error location"
      put gf_addOrSubtract(pReceived[tPosition], errorMagnitudes[i]) into pReceived[tPosition]
   end repeat
end rs_decode

-- Extended Euclidean algorithm; returns array with keys "sigma" and "omega".
function rs_runEuclidean a, b, pTwoT
   local rLast, r, tLast, t, rLastLast, tLastLast, q, dLT, dltInverse
   local degreeDiff, tScale, sigmaTildeAtZero, tInverse, sigma, omega, tmp, tRes

   if poly_degree(a) < poly_degree(b) then
      put a into tmp
      put b into a
      put tmp into b
   end if

   put a into rLast
   put b into r
   put poly_zero() into tLast
   put poly_one() into t

   -- run until 2*deg(r) < R  (R == 2t == number of EC codewords). ZXing writes
   -- `while (2 * r.getDegree() >= R)`; PHP compares against the FLOAT R/2. Both
   -- differ from an integer `R div 2` when R is odd (v1-L/Q/H, v3-L), and only
   -- on uncorrectable blocks - but the divergence changed the reported failure.
   repeat while (2 * poly_degree(r)) >= pTwoT
      put rLast into rLastLast
      put tLast into tLastLast
      put r into rLast
      put t into tLast
      if poly_isZero(rLast) then throw "RS: r_{i-1} was zero"
      put rLastLast into r
      put poly_zero() into q
      put poly_getCoefficient(rLast, poly_degree(rLast)) into dLT
      put gf_inverse(dLT) into dltInverse
      repeat while (poly_degree(r) >= poly_degree(rLast)) and (not poly_isZero(r))
         put (poly_degree(r) - poly_degree(rLast)) into degreeDiff
         put gf_multiply(poly_getCoefficient(r, poly_degree(r)), dltInverse) into tScale
         put poly_addOrSubtract(q, gf_buildMonomial(degreeDiff, tScale)) into q
         put poly_addOrSubtract(r, poly_multiplyByMonomial(rLast, degreeDiff, tScale)) into r
      end repeat
      put poly_addOrSubtract(poly_multiply(q, tLast), tLastLast) into t
      if poly_degree(r) >= poly_degree(rLast) then throw "RS: division failed to reduce polynomial"
   end repeat

   put poly_getCoefficient(t, 0) into sigmaTildeAtZero
   if sigmaTildeAtZero = 0 then throw "RS: sigmaTilde(0) was zero"
   put gf_inverse(sigmaTildeAtZero) into tInverse
   put poly_multiplyScalar(t, tInverse) into sigma
   put poly_multiplyScalar(r, tInverse) into omega
   put sigma into tRes["sigma"]
   put omega into tRes["omega"]
   return tRes
end rs_runEuclidean

-- Chien search for the roots of the error-locator polynomial.
function rs_findErrorLocations errorLocator
   local numErrors, tRes, e, i, sz
   put poly_degree(errorLocator) into numErrors
   if numErrors = 1 then                       -- shortcut
      put poly_getCoefficient(errorLocator, 1) into tRes[0]
      return tRes
   end if
   put qr_fillArray(0, numErrors, 0) into tRes
   put 0 into e
   put gf_getSize() into sz
   put 1 into i
   repeat while (i < sz) and (e < numErrors)
      if poly_evaluateAt(errorLocator, i) = 0 then
         put gf_inverse(i) into tRes[e]
         add 1 to e
      end if
      add 1 to i
   end repeat
   if e <> numErrors then throw "RS: error locator degree does not match number of roots"
   return tRes
end rs_findErrorLocations

-- Forney's formula for the error magnitudes.
function rs_findErrorMagnitudes errorEvaluator, pLocations
   local s, tRes, i, j, xiInverse, denominator, term, termPlus1
   put the number of elements of pLocations into s
   put qr_fillArray(0, s, 0) into tRes
   repeat with i = 0 to (s - 1)
      put gf_inverse(pLocations[i]) into xiInverse
      put 1 into denominator
      repeat with j = 0 to (s - 1)
         if i <> j then
            put gf_multiply(pLocations[j], xiInverse) into term
            put gf_addOrSubtract(term, 1) into termPlus1     -- explicit add mirrors ZXing's Apple-JVM JIT workaround (no JIT in xTalk)
            put gf_multiply(denominator, termPlus1) into denominator
         end if
      end repeat
      put gf_multiply(poly_evaluateAt(errorEvaluator, xiInverse), gf_inverse(denominator)) into tRes[i]
      if gf_getGeneratorBase() <> 0 then
         put gf_multiply(tRes[i], xiInverse) into tRes[i]
      end if
   end repeat
   return tRes
end rs_findErrorMagnitudes

-- ===================== module: bitArray ================
-- =====================================================================
-- bitArray.lc - packed bit vector. Port of ZXing Common\BitArray. Spec section 8.2.
-- Requires: qrCompat.lc.
--
-- Instance (Pattern A) is an array:
--   pObj["size"]     - number of valid bits
--   pObj["bits"][w]  - dense 0-based unsigned-32-bit words (w = 0 .. wordCount-1)
-- Words are kept dense so "the number of elements of pObj['bits']" == wordCount,
-- matching Java's bits.length (which getNextSet/Unset iterate against).
-- All packed words stay in [0, 2^32) (spec section 6.1); shifts go through qrCompat.
-- =====================================================================

function bitArray_new pSize
   local tObj, tWordCount, k
   if pSize is empty then put 0 into pSize
   put pSize into tObj["size"]
   put ((pSize + 31) div 32) into tWordCount
   if tWordCount < 1 then put 1 into tWordCount     -- mirror no-arg ctor (>=1 word)
   repeat with k = 0 to (tWordCount - 1)
      put 0 into tObj["bits"][k]
   end repeat
   return tObj
end bitArray_new

function bitArray_getSize pObj
   return pObj["size"]
end bitArray_getSize

function bitArray_getSizeInBytes pObj
   return ((pObj["size"] + 7) div 8)
end bitArray_getSizeInBytes

-- grow the dense word array so it can hold at least pBitsNeeded bits
command bitArray_ensureCapacity @pObj, pBitsNeeded
   local tWordCount, tNeed, k
   put the number of elements of pObj["bits"] into tWordCount
   put ((pBitsNeeded + 31) div 32) into tNeed
   if tNeed > tWordCount then
      repeat with k = tWordCount to (tNeed - 1)
         put 0 into pObj["bits"][k]
      end repeat
   end if
end bitArray_ensureCapacity

function bitArray_get pObj, i
   return ((pObj["bits"][(i div 32)] bitAnd qr_shl(1, (i bitAnd 31))) <> 0)
end bitArray_get

command bitArray_set @pObj, i
   local w
   put (i div 32) into w
   put qr_u32(pObj["bits"][w] bitOr qr_shl(1, (i bitAnd 31))) into pObj["bits"][w]
end bitArray_set

command bitArray_flip @pObj, i
   local w
   put (i div 32) into w
   put qr_u32(pObj["bits"][w] bitXor qr_shl(1, (i bitAnd 31))) into pObj["bits"][w]
end bitArray_flip

command bitArray_setBulk @pObj, i, pNewBits
   put qr_u32(pNewBits) into pObj["bits"][(i div 32)]
end bitArray_setBulk

command bitArray_clear @pObj
   local n, i
   put the number of elements of pObj["bits"] into n
   repeat with i = 0 to (n - 1)
      put 0 into pObj["bits"][i]
   end repeat
end bitArray_clear

-- index of the first set bit at or after pFrom (returns size if none)
function bitArray_getNextSet pObj, pFrom
   local tSize, tWordCount, tBitsOffset, tCurrent, tResult
   put pObj["size"] into tSize
   if pFrom >= tSize then return tSize
   put the number of elements of pObj["bits"] into tWordCount
   put (pFrom div 32) into tBitsOffset
   put pObj["bits"][tBitsOffset] into tCurrent
   put (tCurrent bitAnd qr_u32(bitNot(qr_shl(1, (pFrom bitAnd 31)) - 1))) into tCurrent
   repeat while tCurrent = 0
      add 1 to tBitsOffset
      if tBitsOffset = tWordCount then return tSize
      put pObj["bits"][tBitsOffset] into tCurrent
   end repeat
   put ((tBitsOffset * 32) + qr_numberOfTrailingZeros(tCurrent)) into tResult
   return min(tResult, tSize)
end bitArray_getNextSet

-- index of the first unset bit at or after pFrom (returns size if none)
function bitArray_getNextUnset pObj, pFrom
   local tSize, tWordCount, tBitsOffset, tCurrent, tResult
   put pObj["size"] into tSize
   if pFrom >= tSize then return tSize
   put the number of elements of pObj["bits"] into tWordCount
   put (pFrom div 32) into tBitsOffset
   put qr_u32(bitNot(pObj["bits"][tBitsOffset])) into tCurrent
   put (tCurrent bitAnd qr_u32(bitNot(qr_shl(1, (pFrom bitAnd 31)) - 1))) into tCurrent
   repeat while tCurrent = 0
      add 1 to tBitsOffset
      if tBitsOffset = tWordCount then return tSize
      put qr_u32(bitNot(pObj["bits"][tBitsOffset])) into tCurrent
   end repeat
   put ((tBitsOffset * 32) + qr_numberOfTrailingZeros(tCurrent)) into tResult
   return min(tResult, tSize)
end bitArray_getNextUnset

-- set bits [pStart, pEnd)  (end exclusive, matching ZXing)
command bitArray_setRange @pObj, pStart, pEnd
   local tFirstInt, tLastInt, i, tFirstBit, tLastBit, tMask, e
   if (pEnd < pStart) or (pStart < 0) or (pEnd > pObj["size"]) then throw "BitArray: bad range"
   if pEnd = pStart then
      exit bitArray_setRange
   end if
   put (pEnd - 1) into e                       -- treat as last inclusive bit
   put (pStart div 32) into tFirstInt
   put (e div 32) into tLastInt
   repeat with i = tFirstInt to tLastInt
      if i > tFirstInt then
         put 0 into tFirstBit
      else
         put (pStart bitAnd 31) into tFirstBit
      end if
      if i < tLastInt then
         put 31 into tLastBit
      else
         put (e bitAnd 31) into tLastBit
      end if
      put qr_u32(qr_shl(2, tLastBit) - qr_shl(1, tFirstBit)) into tMask   -- ones firstBit..lastBit
      put qr_u32(pObj["bits"][i] bitOr tMask) into pObj["bits"][i]
   end repeat
end bitArray_setRange

-- true iff every bit in [pStart, pEnd) equals pValue (boolean)
function bitArray_isRange pObj, pStart, pEnd, pValue
   local tFirstInt, tLastInt, i, tFirstBit, tLastBit, tMask, tWanted, e
   if (pEnd < pStart) or (pStart < 0) or (pEnd > pObj["size"]) then throw "BitArray: bad range"
   if pEnd = pStart then return true
   put (pEnd - 1) into e
   put (pStart div 32) into tFirstInt
   put (e div 32) into tLastInt
   repeat with i = tFirstInt to tLastInt
      if i > tFirstInt then
         put 0 into tFirstBit
      else
         put (pStart bitAnd 31) into tFirstBit
      end if
      if i < tLastInt then
         put 31 into tLastBit
      else
         put (e bitAnd 31) into tLastBit
      end if
      put qr_u32(qr_shl(2, tLastBit) - qr_shl(1, tFirstBit)) into tMask
      if pValue then
         put tMask into tWanted
      else
         put 0 into tWanted
      end if
      if (pObj["bits"][i] bitAnd tMask) <> tWanted then return false
   end repeat
   return true
end bitArray_isRange

command bitArray_appendBit @pObj, pBit
   local w
   bitArray_ensureCapacity pObj, (pObj["size"] + 1)
   if pBit then
      put (pObj["size"] div 32) into w
      put qr_u32(pObj["bits"][w] bitOr qr_shl(1, (pObj["size"] bitAnd 31))) into pObj["bits"][w]
   end if
   add 1 to pObj["size"]
end bitArray_appendBit

-- append the low pNumBits of pValue, most-significant bit first
command bitArray_appendBits @pObj, pValue, pNumBits
   local nbl
   if (pNumBits < 0) or (pNumBits > 32) then throw "BitArray: numBits must be 0..32"
   bitArray_ensureCapacity pObj, (pObj["size"] + pNumBits)
   repeat with nbl = pNumBits down to 1
      bitArray_appendBit pObj, ((qr_uShr(pValue, (nbl - 1)) bitAnd 1) = 1)
   end repeat
end bitArray_appendBits

command bitArray_xor @pObj, pOther
   local n, i
   if pObj["size"] <> pOther["size"] then throw "BitArray: sizes don't match"
   put the number of elements of pObj["bits"] into n
   repeat with i = 0 to (n - 1)
      put qr_u32(pObj["bits"][i] bitXor pOther["bits"][i]) into pObj["bits"][i]
   end repeat
end bitArray_xor

-- read pNumBytes bytes (MSB-first) starting at bit pBitOffset; returns dense 0-based array
function bitArray_toBytes pObj, pBitOffset, pNumBytes
   local tOut, i, j, theByte, bo
   put pBitOffset into bo
   repeat with i = 0 to (pNumBytes - 1)
      put 0 into theByte
      repeat with j = 0 to 7
         if bitArray_get(pObj, bo) then put qr_u32(theByte bitOr qr_shl(1, (7 - j))) into theByte
         add 1 to bo
      end repeat
      put theByte into tOut[i]
   end repeat
   return tOut
end bitArray_toBytes

-- reverse the bit order within [0, size)  (classic bit-reversal; spec section 6.2)
command bitArray_reverse @pObj
   local tSize, tLen, tOldLen, tOrigCount, i, x, newBits
   local leftOffset, currentInt, nextInt
   put pObj["size"] into tSize
   put ((tSize - 1) div 32) into tLen
   put (tLen + 1) into tOldLen
   put the number of elements of pObj["bits"] into tOrigCount
   repeat with i = 0 to (tOrigCount - 1)            -- newBits starts all-zero, same length
      put 0 into newBits[i]
   end repeat
   repeat with i = 0 to (tOldLen - 1)
      put qr_u32(pObj["bits"][i]) into x
      put ((qr_uShr(x, 1) bitAnd 1431655765) bitOr qr_u32(qr_shl((x bitAnd 1431655765), 1))) into x   -- 0x55555555
      put ((qr_uShr(x, 2) bitAnd 858993459) bitOr qr_u32(qr_shl((x bitAnd 858993459), 2))) into x     -- 0x33333333
      put ((qr_uShr(x, 4) bitAnd 252645135) bitOr qr_u32(qr_shl((x bitAnd 252645135), 4))) into x     -- 0x0f0f0f0f
      put ((qr_uShr(x, 8) bitAnd 16711935) bitOr qr_u32(qr_shl((x bitAnd 16711935), 8))) into x       -- 0x00ff00ff
      put ((qr_uShr(x, 16) bitAnd 65535) bitOr qr_u32(qr_shl((x bitAnd 65535), 16))) into x           -- 0x0000ffff
      put x into newBits[(tLen - i)]
   end repeat
   if tSize <> (tOldLen * 32) then
      put ((tOldLen * 32) - tSize) into leftOffset
      put qr_uShr(newBits[0], leftOffset) into currentInt
      repeat with i = 1 to (tOldLen - 1)
         put newBits[i] into nextInt
         put qr_u32(currentInt bitOr qr_shl(nextInt, (32 - leftOffset))) into currentInt
         put currentInt into newBits[(i - 1)]
         put qr_uShr(nextInt, leftOffset) into currentInt
      end repeat
      put currentInt into newBits[(tOldLen - 1)]
   end if
   put newBits into pObj["bits"]
end bitArray_reverse

function bitArray_clone pObj
   return pObj          -- xTalk deep-copies arrays on return
end bitArray_clone

-- ===================== module: bitMatrix ===============
-- =====================================================================
-- bitMatrix.lc - packed 2-D bit grid. Port of ZXing Common\BitMatrix. Spec section 8.1.
-- Requires: qrCompat.lc, bitArray.lc (for getRow/setRow/rotate180).
--
-- Instance (Pattern A) is an array:
--   pObj["width"], pObj["height"]
--   pObj["rowSize"]  = (width + 31) div 32   (words per row)
--   pObj["bits"][w]  = dense 0-based unsigned-32-bit words, length rowSize*height
--
-- getEnclosingRectangle/getTopLeftOnBit/getBottomRightOnBit use the Java
-- `theBits << (31-bit)` / `>>> bit` idioms. These are exactly why qrCompat.qr_shl
-- is precision-safe: qr_shl(theBits,31-bit)=0 iff the low (bit+1) bits are zero,
-- matching Java's overflow-discard semantics bit-for-bit (spec section 6.2).
--
-- HOT PATH: get/set/unset/flip run once per pixel in the binarizers, the finder
-- and the sampler. They use a power-of-two table (sBMPow2[b] = 2^b, built once
-- by bitMatrix_new) instead of the qr_shl/qr_uShr/qr_u32 helper calls: for a word in
-- [0, 2^32) and a bit index in 0..31, `word div 2^b` IS qr_uShr(word, b) and
-- `word bitOr 2^b` IS qr_u32(word bitOr qr_shl(1, b)) - bit-identical, proven under
-- the headless model on every fixture, with no `^` operator on the hot path
-- (some OXT parsers are reported to reject `^` inside a compound expression).
-- Every matrix comes from bitMatrix_new, so the table always exists.
--
-- NOTE: the giant hard-coded debug array literal in PHP BitMatrix::set() is
-- dead cruft and is intentionally NOT ported (spec section 8.1 warning).
-- =====================================================================

local sBMPow2, sBMPow2Ready      -- sBMPow2[b] = 2^b, b = 0..31; built once

command bm_ensurePow2
   local b, v
   if sBMPow2Ready is true then exit bm_ensurePow2
   put 1 into v
   repeat with b = 0 to 31
      put v into sBMPow2[b]
      put (v * 2) into v
   end repeat
   put true into sBMPow2Ready
end bm_ensurePow2

function bitMatrix_new pWidth, pHeight
   local tObj, tRowSize, tCount, k, tBits
   bm_ensurePow2
   if pWidth < 1 then throw "BitMatrix: dimensions must be > 0"
   if pHeight is empty then put pWidth into pHeight
   if pHeight < 1 then throw "BitMatrix: dimensions must be > 0"
   put pWidth into tObj["width"]
   put pHeight into tObj["height"]
   put ((pWidth + 31) div 32) into tRowSize
   put tRowSize into tObj["rowSize"]
   put (tRowSize * pHeight) into tCount
   -- zero-fill a FLAT local, then assign it into tObj["bits"] once (one nested
   -- write instead of tCount of them; the matrix is image-sized on the binarizer
   -- path, so this is rowSize*height words per allocation).
   repeat with k = 0 to (tCount - 1)
      put 0 into tBits[k]
   end repeat
   put tBits into tObj["bits"]
   return tObj
end bitMatrix_new

function bitMatrix_getWidth pObj
   return pObj["width"]
end bitMatrix_getWidth

function bitMatrix_getHeight pObj
   return pObj["height"]
end bitMatrix_getHeight

-- A read outside the matrix answers false (white). ZXing/PHP behave that way
-- for the reads the detector actually makes (padding bits are zero; PHP's get
-- auto-vivifies a missing word to 0), and the finder's cross-check loops walk
-- one pixel past every edge, so the guard makes those reads independent of
-- whether the engine short-circuits `and` or errors on arithmetic over empty.
function bitMatrix_get pObj, x, y
   local tOffset
   if (x < 0) or (y < 0) or (x >= pObj["width"]) or (y >= pObj["height"]) then
      return false
   end if
   put ((y * pObj["rowSize"]) + (x div 32)) into tOffset
   return (((pObj["bits"][tOffset] div sBMPow2[x bitAnd 31]) bitAnd 1) = 1)
end bitMatrix_get

command bitMatrix_set @pObj, x, y
   local tOffset
   put ((y * pObj["rowSize"]) + (x div 32)) into tOffset
   put (pObj["bits"][tOffset] bitOr sBMPow2[x bitAnd 31]) into pObj["bits"][tOffset]
end bitMatrix_set

command bitMatrix_unset @pObj, x, y
   local tOffset
   put ((y * pObj["rowSize"]) + (x div 32)) into tOffset
   put (pObj["bits"][tOffset] bitAnd (4294967295 - sBMPow2[x bitAnd 31])) into pObj["bits"][tOffset]
end bitMatrix_unset

command bitMatrix_flip @pObj, x, y
   local tOffset
   put ((y * pObj["rowSize"]) + (x div 32)) into tOffset
   put (pObj["bits"][tOffset] bitXor sBMPow2[x bitAnd 31]) into pObj["bits"][tOffset]
end bitMatrix_flip

command bitMatrix_clear @pObj
   local n, i
   put the number of elements of pObj["bits"] into n
   repeat with i = 0 to (n - 1)
      put 0 into pObj["bits"][i]
   end repeat
end bitMatrix_clear

command bitMatrix_setRegion @pObj, pLeft, pTop, pWidth, pHeight
   local tRight, tBottom, y, x, tRowSize, tOffset, tIdx
   if (pTop < 0) or (pLeft < 0) then throw "BitMatrix: left and top must be nonnegative"
   if (pHeight < 1) or (pWidth < 1) then throw "BitMatrix: height and width must be at least 1"
   put (pLeft + pWidth) into tRight
   put (pTop + pHeight) into tBottom
   if (tBottom > pObj["height"]) or (tRight > pObj["width"]) then throw "BitMatrix: region must fit inside matrix"
   put pObj["rowSize"] into tRowSize
   repeat with y = pTop to (tBottom - 1)
      put (y * tRowSize) into tOffset
      repeat with x = pLeft to (tRight - 1)
         put (tOffset + (x div 32)) into tIdx
         put qr_u32(pObj["bits"][tIdx] bitOr qr_shl(1, (x bitAnd 31))) into pObj["bits"][tIdx]
      end repeat
   end repeat
end bitMatrix_setRegion

-- returns a new BitArray holding row y (width bits)
function bitMatrix_getRow pObj, y
   local tRow, x, tRowSize, tOffset
   put pObj["rowSize"] into tRowSize
   put bitArray_new(pObj["width"]) into tRow
   put (y * tRowSize) into tOffset
   repeat with x = 0 to (tRowSize - 1)
      bitArray_setBulk tRow, (x * 32), pObj["bits"][tOffset + x]
   end repeat
   return tRow
end bitMatrix_getRow

command bitMatrix_setRow @pObj, y, pRow
   local x, tRowSize, tOffset
   put pObj["rowSize"] into tRowSize
   put (y * tRowSize) into tOffset
   repeat with x = 0 to (tRowSize - 1)
      put qr_u32(pRow["bits"][x]) into pObj["bits"][tOffset + x]
   end repeat
end bitMatrix_setRow

command bitMatrix_rotate180 @pObj
   local h, i, topRow, bottomRow
   put pObj["height"] into h
   repeat with i = 0 to (((h + 1) div 2) - 1)
      put bitMatrix_getRow(pObj, i) into topRow
      put bitMatrix_getRow(pObj, (h - 1 - i)) into bottomRow
      bitArray_reverse topRow
      bitArray_reverse bottomRow
      bitMatrix_setRow pObj, i, bottomRow
      bitMatrix_setRow pObj, (h - 1 - i), topRow
   end repeat
end bitMatrix_rotate180

command bitMatrix_xor @pObj, pMask
   local n, i
   if (pObj["width"] <> pMask["width"]) or (pObj["height"] <> pMask["height"]) \
         or (pObj["rowSize"] <> pMask["rowSize"]) then
      throw "BitMatrix: input matrix dimensions do not match"
   end if
   put the number of elements of pObj["bits"] into n
   repeat with i = 0 to (n - 1)
      put qr_u32(pObj["bits"][i] bitXor pMask["bits"][i]) into pObj["bits"][i]
   end repeat
end bitMatrix_xor

-- {left, top, width, height} of the smallest rectangle covering all set bits,
-- as a dense 0-based array; returns empty if no bits are set.
function bitMatrix_getEnclosingRectangle pObj
   local tLeft, tTop, tRight, tBottom, w, h, rs, y, x32, theBits, tBitN, tRes
   put pObj["width"] into w
   put pObj["height"] into h
   put pObj["rowSize"] into rs
   put w into tLeft
   put h into tTop
   put -1 into tRight
   put -1 into tBottom
   repeat with y = 0 to (h - 1)
      repeat with x32 = 0 to (rs - 1)
         put pObj["bits"][y * rs + x32] into theBits
         if theBits <> 0 then
            if y < tTop then put y into tTop
            if y > tBottom then put y into tBottom
            if (x32 * 32) < tLeft then
               put 0 into tBitN
               repeat while qr_shl(theBits, (31 - tBitN)) = 0
                  add 1 to tBitN
               end repeat
               if ((x32 * 32) + tBitN) < tLeft then put ((x32 * 32) + tBitN) into tLeft
            end if
            if ((x32 * 32) + 31) > tRight then
               put 31 into tBitN
               repeat while qr_uShr(theBits, tBitN) = 0
                  subtract 1 from tBitN
               end repeat
               if ((x32 * 32) + tBitN) > tRight then put ((x32 * 32) + tBitN) into tRight
            end if
         end if
      end repeat
   end repeat
   if (tRight < tLeft) or (tBottom < tTop) then return empty
   put tLeft into tRes[0]
   put tTop into tRes[1]
   put (tRight - tLeft + 1) into tRes[2]
   put (tBottom - tTop + 1) into tRes[3]
   return tRes
end bitMatrix_getEnclosingRectangle

-- {x, y} of the top-left set bit as a dense 0-based array; empty if none.
function bitMatrix_getTopLeftOnBit pObj
   local tCount, bitsOffset, rs, y, x, theBits, tBitN, tRes
   put the number of elements of pObj["bits"] into tCount
   put pObj["rowSize"] into rs
   put 0 into bitsOffset
   repeat while (bitsOffset < tCount) and (pObj["bits"][bitsOffset] = 0)
      add 1 to bitsOffset
   end repeat
   if bitsOffset = tCount then return empty
   put (bitsOffset div rs) into y
   put ((bitsOffset mod rs) * 32) into x
   put pObj["bits"][bitsOffset] into theBits
   put 0 into tBitN
   repeat while qr_shl(theBits, (31 - tBitN)) = 0
      add 1 to tBitN
   end repeat
   add tBitN to x
   put x into tRes[0]
   put y into tRes[1]
   return tRes
end bitMatrix_getTopLeftOnBit

-- {x, y} of the bottom-right set bit as a dense 0-based array; empty if none.
function bitMatrix_getBottomRightOnBit pObj
   local tCount, bitsOffset, rs, y, x, theBits, tBitN, tRes
   put the number of elements of pObj["bits"] into tCount
   put pObj["rowSize"] into rs
   put (tCount - 1) into bitsOffset
   repeat while (bitsOffset >= 0) and (pObj["bits"][bitsOffset] = 0)
      subtract 1 from bitsOffset
   end repeat
   if bitsOffset < 0 then return empty
   put (bitsOffset div rs) into y
   put ((bitsOffset mod rs) * 32) into x
   put pObj["bits"][bitsOffset] into theBits
   put 31 into tBitN
   repeat while qr_uShr(theBits, tBitN) = 0
      subtract 1 from tBitN
   end repeat
   add tBitN to x
   put x into tRes[0]
   put y into tRes[1]
   return tRes
end bitMatrix_getBottomRightOnBit

function bitMatrix_clone pObj
   return pObj          -- xTalk deep-copies arrays on return
end bitMatrix_clone

-- the transpose of a SQUARE matrix, as a new matrix: (x,y) -> (y,x). This is
-- ZXing BitMatrixParser.mirror() (which flips the bits across the diagonal in
-- place); the decoder uses it for the mirrored-symbol retry.
function bitMatrix_transposed pObj
   local tW, tH, tOut, x, y
   put pObj["width"] into tW
   put pObj["height"] into tH
   if tW <> tH then throw "BitMatrix: transpose needs a square matrix"
   put bitMatrix_new(tW, tH) into tOut
   repeat with y = 0 to (tH - 1)
      repeat with x = 0 to (tW - 1)
         if bitMatrix_get(pObj, x, y) then bitMatrix_set tOut, y, x
      end repeat
   end repeat
   return tOut
end bitMatrix_transposed

-- invert every module in place: ZXing BitMatrix.flip() with no arguments -
-- complement every word, then clear the padding bits beyond the logical width
-- in the last word of each row so they stay zero. Used for the ALSO_INVERTED
-- retry (a white-on-black symbol).
command bitMatrix_flipAll @pObj
   local tBits, tCount, k, tRem, tMask, y, tOff, rs
   put pObj["bits"] into tBits
   put the number of elements of tBits into tCount
   repeat with k = 0 to (tCount - 1)
      put (4294967295 - tBits[k]) into tBits[k]    -- 0xFFFFFFFF - w == bitNot w within [0, 2^32)
   end repeat
   put (pObj["width"] mod 32) into tRem
   if tRem <> 0 then
      put pObj["rowSize"] into rs
      put (qr_shl(1, tRem) - 1) into tMask
      repeat with y = 0 to (pObj["height"] - 1)
         put ((y * rs) + rs - 1) into tOff
         put (tBits[tOff] bitAnd tMask) into tBits[tOff]
      end repeat
   end if
   put tBits into pObj["bits"]
end bitMatrix_flipAll

-- ===================== module: bitSource ===============
-- =====================================================================
-- bitSource.lc - MSB-first bit reader over a byte array.
-- Port of ZXing Common\BitSource. Spec section 8.3. Requires: qrCompat.lc.
--
-- Instance (Pattern A):
--   pObj["bytes"][k]    - dense 0-based array of byte values 0..255
--   pObj["byteOffset"]  - current byte index
--   pObj["bitOffset"]   - current bit within that byte (0 = MSB)
--
-- readBits is a COMMAND (it mutates the offsets) that returns its value via
-- `the result` (spec section 5 convention: mutators are commands). Call site:
--     bitSource_readBits tSrc, 4
--     put the result into tValue
-- This drives DecodedBitStreamParser.
-- =====================================================================

function bitSource_new pBytes
   local tObj
   put pBytes into tObj["bytes"]
   put 0 into tObj["byteOffset"]
   put 0 into tObj["bitOffset"]
   return tObj
end bitSource_new

function bitSource_getByteOffset pObj
   return pObj["byteOffset"]
end bitSource_getByteOffset

function bitSource_getBitOffset pObj
   return pObj["bitOffset"]
end bitSource_getBitOffset

function bitSource_available pObj
   return ((8 * ((the number of elements of pObj["bytes"]) - pObj["byteOffset"])) - pObj["bitOffset"])
end bitSource_available

command bitSource_readBits @pObj, pNumBits
   local n, tResult, bitsLeft, toRead, bitsToNotRead, tMask, curByte
   put pNumBits into n
   if (n < 1) or (n > 32) or (n > bitSource_available(pObj)) then
      throw "BitSource: illegal numBits " & n
   end if
   put 0 into tResult

   -- (1) finish the current partial byte, if any
   if pObj["bitOffset"] > 0 then
      put (8 - pObj["bitOffset"]) into bitsLeft
      put min(n, bitsLeft) into toRead
      put (bitsLeft - toRead) into bitsToNotRead
      put qr_shl((255 div (2 ^ (8 - toRead))), bitsToNotRead) into tMask
      put pObj["bytes"][pObj["byteOffset"]] into curByte
      put qr_uShr((curByte bitAnd tMask), bitsToNotRead) into tResult
      subtract toRead from n
      add toRead to pObj["bitOffset"]
      if pObj["bitOffset"] = 8 then
         put 0 into pObj["bitOffset"]
         add 1 to pObj["byteOffset"]
      end if
   end if

   -- (2) whole bytes, then a trailing partial byte
   if n > 0 then
      repeat while n >= 8
         put pObj["bytes"][pObj["byteOffset"]] into curByte
         put qr_u32((qr_shl(tResult, 8)) bitOr (curByte bitAnd 255)) into tResult
         add 1 to pObj["byteOffset"]
         subtract 8 from n
      end repeat
      if n > 0 then
         put (8 - n) into bitsToNotRead
         put qr_shl((255 div (2 ^ bitsToNotRead)), bitsToNotRead) into tMask
         put pObj["bytes"][pObj["byteOffset"]] into curByte
         put qr_u32((qr_shl(tResult, n)) bitOr qr_uShr((curByte bitAnd tMask), bitsToNotRead)) into tResult
         add n to pObj["bitOffset"]
      end if
   end if

   return tResult
end bitSource_readBits

-- ===================== module: luminanceSource =========
-- =====================================================================
-- luminanceSource.lc - luminance plane for the binarizers. Spec section 7.
-- Port of ZXing LuminanceSource / GDLuminanceSource (server variant).
-- Requires: qrCompat.lc (only for completeness; uses builtins).
--
-- Instance (Pattern A):
--   pObj["width"], pObj["height"]
--   pObj["lum"][i]   - flat 0-based greyscale 0..255, row-major (i = y*width + x)
--
-- TWO construction paths, deliberately separated:
--   * newFromImageData(w,h,raw)  - PURE byte math (section 7.3). Fully unit-testable
--     with synthetic 4-byte/pixel data; no engine image object involved.
--   * newFromData(bytes)         - decodes a PNG/JPG/GIF/BMP via the engine
--     IMAGE OBJECT (section 7.1). This is the ONE piece that may not work in a
--     headless cPanel server; qr_imageprobe.lc tests exactly that. Not part
--     of the unit suite.
-- =====================================================================

-- section 7.3 greyscale: per pixel, if r==g==b luminance=r, else (r+2g+b)/4 (trunc).
-- raw layout per section 7.2: 4 bytes/pixel, byte1=0/alpha, byte2=R, byte3=G, byte4=B.
function luminanceSource_newFromImageData pW, pH, pRaw
   local tObj, p, o, n, tLum
   put pW into tObj["width"]
   put pH into tObj["height"]
   put (pW * pH) into n
   -- Hot loop (one iteration per pixel; spec section 11 - the documented cost
   -- centre). TWO statements per pixel:
   --   * accumulate into a FLAT local (tLum) stored into tObj["lum"] ONCE;
   --   * the loop counter p is the 0-based pixel index; the byte offset o is
   --     carried with `add 4` (pixel p reads bytes 4p+2/4p+3/4p+4 = R/G/B);
   --   * the greyscale rule "r if r=g=b, else (r+2g+b)/4 truncated" is written
   --     branch-free as (r + 2g + b) div 4: when r=g=b that is (4r) div 4 = r,
   --     and for non-negative integers div IS the truncated quotient. Bit-
   --     identical to the branching form (proven under the headless model).
   put 0 into o
   repeat with p = 0 to (n - 1)
      put ((byteToNum(byte (o + 2) of pRaw) + (2 * byteToNum(byte (o + 3) of pRaw)) \
            + byteToNum(byte (o + 4) of pRaw)) div 4) into tLum[p]
      add 4 to o
   end repeat
   put tLum into tObj["lum"]
   return tObj
end luminanceSource_newFromImageData

-- convenience: wrap an existing flat 0-based luminance array
function luminanceSource_newFromLuminances pW, pH, pLum
   local tObj
   put pW into tObj["width"]
   put pH into tObj["height"]
   put pLum into tObj["lum"]
   return tObj
end luminanceSource_newFromLuminances

-- IMAGE-OBJECT PATH (section 7.1). Requires a working engine image object;
-- qr_imageprobe.lc confirms this path on a given engine.
--
-- Decode the image bytes to a raw 4-byte/pixel plane via the engine image
-- object, ONCE. Returns {["width"],["height"],["raw"]}. Separated from the
-- greyscale/downsample step so a robust reader can decode the (costly) image a
-- single time and then derive several luminance sources at different scales
-- from the same raw plane (spec section 11: image decode + pixel loops dominate).
--
-- HOST-APP SAFETY (xtalk-suite engine notes 5.3 / 5.5, lessons L2-02, L3-03):
-- an unqualified control reference resolves against THE DEFAULTSTACK (whatever
-- stack is frontmost, i.e. the host's), and `create stack` opens the stack it
-- makes. Until 2026-09 this handler created its scratch image on the host's
-- own front card after the first call, firing newImage/deleteImage into the
-- host's scripts and marking its stack dirty. Now: remember the host's
-- defaultStack, park the scratch image on the library's own invisible
-- "qrHostStack", lock messages around the create/fill/read/delete, and put the
-- defaultStack (and the lockMessages state) back on EVERY exit - the failing
-- one included (the throw happens after `end try`: a throw inside a catch is
-- lost on OXT, engine notes 3.2). The scratch image has a fixed name and is
-- deleted before reuse, so an aborted call can never leak a control.
-- EVIDENCE: verified statically and by construction from the suite's engine
-- notes; this exact sequence needs an OXT pass on a desktop engine (it cannot
-- run under the headless model, which supplies its own PNG decoder here).
--
-- pMaxDim is accepted for signature compatibility but does not resize here:
-- downsampling is performed by the caller (luminanceSource_fromRawPlane), so this
-- handler always returns the full-resolution pixels. (The imageData layout after
-- an in-engine resize is build-specific, so resizing is left to the host app.)
function luminanceSource_decodeRawPlane pImageData, pMaxDim
   local tW, tH, tRaw, tName, e, tPlane, tSavedStack, tSavedLock, tErr, tHost
   put "qrHostStack" into tHost
   put "qrScratchImage" into tName
   put the defaultStack into tSavedStack
   put the lockMessages into tSavedLock
   put empty into tErr
   put 0 into tW
   put 0 into tH
   put empty into tRaw
   lock messages
   try
      if there is not a stack tHost then
         create invisible stack tHost
      end if
      set the defaultStack to tHost
      if there is an image tName then delete image tName
      create invisible image tName
      set the lockLoc of image tName to true
      put pImageData into image tName                  -- decode PNG/JPG/GIF/BMP
      put the formattedWidth of image tName into tW
      put the formattedHeight of image tName into tH
      set the width of image tName to tW
      set the height of image tName to tH
      put the imageData of image tName into tRaw       -- 4 bytes/pixel, row-major
      delete image tName
   catch e
      put e into tErr
   end try
   if tSavedStack is not empty then set the defaultStack to tSavedStack
   set the lockMessages to tSavedLock
   if tErr is not empty then
      throw "NotFound: the engine image object could not decode the image -- " & tErr
   end if
   -- Guard a silent decode failure. On a build whose engine lacks a codec for
   -- this format (notably JPEG on some headless xTalk server builds), the
   -- image object decodes to 0x0 / empty imageData rather than erroring -- which
   -- the rest of the pipeline would mistake for a blank photo and report as a
   -- generic "no QR". Surface the real reason instead (spec section 7.1).
   if (tW <= 0) or (tH <= 0) then
      throw "NotFound: image did not decode (0 x 0) -- unsupported format? this engine build may lack a JPEG codec; try a PNG"
   end if
   if (the number of bytes of tRaw) < (tW * tH * 4) then
      throw "NotFound: image decoded to " & tW & " x " & tH & " but pixel data was incomplete (image codec problem)"
   end if
   put tW into tPlane["width"]
   put tH into tPlane["height"]
   put tRaw into tPlane["raw"]
   return tPlane
end luminanceSource_decodeRawPlane

-- the integer nearest-neighbour downsample step so neither side exceeds pMaxDim
-- (1 = no downsample). Empty/<=0 pMaxDim means full resolution.
function luminanceSource_stepForDims pW, pH, pMaxDim
   local tStep
   put 1 into tStep
   if (pMaxDim is not empty) and (pMaxDim > 0) then
      repeat while ((pW div tStep) > pMaxDim) or ((pH div tStep) > pMaxDim)
         add 1 to tStep
      end repeat
   end if
   return tStep
end luminanceSource_stepForDims

-- build a luminance source from an already-decoded raw plane, downsampling so
-- neither side exceeds pMaxDim (omit pMaxDim for full resolution).
function luminanceSource_fromRawPlane pPlane, pMaxDim
   local tStep
   put luminanceSource_stepForDims(pPlane["width"], pPlane["height"], pMaxDim) into tStep
   return luminanceSource_fromRawPlaneStep(pPlane, tStep)
end luminanceSource_fromRawPlane

-- the same, for an explicit integer downsample step (1 = full resolution); the
-- robust reader plans its resolution ladder in steps so no rung repeats work
function luminanceSource_fromRawPlaneStep pPlane, pStep
   local tW, tH
   put pPlane["width"] into tW
   put pPlane["height"] into tH
   if pStep > 1 then
      return luminanceSource_downsampleRaw(tW, tH, pPlane["raw"], pStep)
   end if
   return luminanceSource_newFromImageData(tW, tH, pPlane["raw"])
end luminanceSource_fromRawPlaneStep

-- decode image bytes straight to a luminance source (optionally downsampled).
-- Behaviour-preserving wrapper over decodeRawPlane + fromRawPlane; this is the
-- single-pass front door the golden fixtures are verified against.
function luminanceSource_newFromData pImageData, pMaxDim
   local tPlane
   -- ask the engine to resample to pMaxDim during decode (fast path); the
   -- interpreted fromRawPlane is then a no-op when the plane is already small
   -- enough, or the correctness fallback if the engine returned full-res pixels.
   put luminanceSource_decodeRawPlane(pImageData, pMaxDim) into tPlane
   return luminanceSource_fromRawPlane(tPlane, pMaxDim)
end luminanceSource_newFromData

-- Build a luminance source from a 4-byte/pixel raw plane, sampling every
-- pStep-th pixel in x and y (nearest-neighbour downsample), in ONE pass: the
-- kept pixel's R/G/B bytes (o+2, o+3, o+4) go straight through the section 7.3
-- greyscale rule of newFromImageData above. (Until 2026-09 this rebuilt a
-- reduced raw string first and then converted it - two passes over every kept
-- pixel; the bytes read and the values written are identical.)
function luminanceSource_downsampleRaw pW, pH, pRaw, pStep
   local tOutW, tOutH, sx, sy, tOStep, o, p, tLum, tObj
   put (((pW - 1) div pStep) + 1) into tOutW
   put (((pH - 1) div pStep) + 1) into tOutH
   -- Within a row each kept pixel is pStep source pixels (= pStep*4 bytes) past
   -- the previous one, so o advances by a constant add per kept pixel.
   put (pStep * 4) into tOStep
   put 0 into p
   repeat with sy = 0 to (tOutH - 1)
      put (((sy * pStep) * pW) * 4) into o
      repeat with sx = 0 to (tOutW - 1)
         put ((byteToNum(byte (o + 2) of pRaw) + (2 * byteToNum(byte (o + 3) of pRaw)) \
               + byteToNum(byte (o + 4) of pRaw)) div 4) into tLum[p]
         add tOStep to o
         add 1 to p
      end repeat
   end repeat
   put tOutW into tObj["width"]
   put tOutH into tObj["height"]
   put tLum into tObj["lum"]
   return tObj
end luminanceSource_downsampleRaw

function luminanceSource_getWidth pObj
   return pObj["width"]
end luminanceSource_getWidth

function luminanceSource_getHeight pObj
   return pObj["height"]
end luminanceSource_getHeight

-- whole flat luminance array (no copy semantics rely on caller)
function luminanceSource_getMatrix pObj
   return pObj["lum"]
end luminanceSource_getMatrix

-- dense 0-based array of the `width` luminance values in row y
function luminanceSource_getRow pObj, y
   local tRow, x, w, base
   put pObj["width"] into w
   put (y * w) into base
   repeat with x = 0 to (w - 1)
      put pObj["lum"][base + x] into tRow[x]
   end repeat
   return tRow
end luminanceSource_getRow

-- crop to a sub-rectangle, returning a new source (lazy: used by rare paths)
function luminanceSource_crop pObj, pLeft, pTop, pW, pH
   local tObj, x, y, srcBase, dstIdx, sw
   put pW into tObj["width"]
   put pH into tObj["height"]
   put pObj["width"] into sw
   put 0 into dstIdx
   repeat with y = 0 to (pH - 1)
      put ((pTop + y) * sw + pLeft) into srcBase
      repeat with x = 0 to (pW - 1)
         put pObj["lum"][srcBase + x] into tObj["lum"][dstIdx]
         add 1 to dstIdx
      end repeat
   end repeat
   return tObj
end luminanceSource_crop

-- ===================== module: globalHistogramBinarizer 
-- =====================================================================
-- globalHistogramBinarizer.lc - global black-point via 32-bucket histogram.
-- Port of ZXing GlobalHistogramBinarizer. Spec section 8 / module inventory.
-- Requires: qrCompat.lc, bitMatrix.lc, luminanceSource.lc.
--
-- ghb_getBlackMatrix(pSrc) -> BitMatrix (true = black). Samples 4 rows to
-- build a 32-bucket luminance histogram, estimates a black point, then
-- thresholds the whole image. Throws "NotFound: ..." when contrast is too low
-- (mirrors ZXing throwing NotFoundException; spec section 6.6).
-- =====================================================================

local sGHPow2, sGHPow2Ready      -- sGHPow2[b] = 2^b, b = 0..31; built once

command ghb_ensurePow2
   local b, v
   if sGHPow2Ready is true then exit ghb_ensurePow2
   put 1 into v
   repeat with b = 0 to 31
      put v into sGHPow2[b]
      put (v * 2) into v
   end repeat
   put true into sGHPow2Ready
end ghb_ensurePow2

constant kLumBits    = 5
constant kLumShift   = 3      -- 8 - kLumBits
constant kLumBuckets = 32     -- 1 << kLumBits

function ghb_estimateBlackPoint pBuckets
   local numBuckets, maxBucketCount, firstPeak, firstPeakSize, x
   local secondPeak, secondPeakScore, dist, score, temp
   local bestValley, bestValleyScore, fromFirst
   put kLumBuckets into numBuckets

   -- tallest peak
   put 0 into maxBucketCount
   put 0 into firstPeak
   put 0 into firstPeakSize
   repeat with x = 0 to (numBuckets - 1)
      if pBuckets[x] > firstPeakSize then
         put x into firstPeak
         put pBuckets[x] into firstPeakSize
      end if
      if pBuckets[x] > maxBucketCount then put pBuckets[x] into maxBucketCount
   end repeat

   -- second-tallest peak, weighted toward distance from the first
   put 0 into secondPeak
   put 0 into secondPeakScore
   repeat with x = 0 to (numBuckets - 1)
      put (x - firstPeak) into dist
      put (pBuckets[x] * dist * dist) into score
      if score > secondPeakScore then
         put x into secondPeak
         put score into secondPeakScore
      end if
   end repeat

   -- ensure firstPeak is the darker one
   if firstPeak > secondPeak then
      put firstPeak into temp
      put secondPeak into firstPeak
      put temp into secondPeak
   end if

   -- too little contrast -> give up (don't risk false positives)
   if (secondPeak - firstPeak) <= (numBuckets div 16) then
      throw "NotFound: too little dynamic range in luminance"
   end if

   -- lowest valley between the peaks, biased toward the white peak
   put (secondPeak - 1) into bestValley
   put -1 into bestValleyScore
   repeat with x = (secondPeak - 1) down to (firstPeak + 1)
      put (x - firstPeak) into fromFirst
      put (fromFirst * fromFirst * (secondPeak - x) * (maxBucketCount - pBuckets[x])) into score
      if score > bestValleyScore then
         put x into bestValley
         put score into bestValleyScore
      end if
   end repeat

   return qr_shl(bestValley, kLumShift)
end ghb_estimateBlackPoint

function ghb_getBlackMatrix pSrc
   local tW, tH, tLum, tMatrix, x, y, tRow, tRight, tLeft, tPixel
   local tBuckets, b, blackPoint, tOffset, tRowBase, tBits, tRowSize, tWordOff, tAcc, tBit
   put pSrc["width"] into tW
   put pSrc["height"] into tH
   put pSrc["lum"] into tLum
   put bitMatrix_new(tW, tH) into tMatrix

   -- histogram from 4 sampled rows (y = 1..4 of fifths), centre columns
   repeat with b = 0 to (kLumBuckets - 1)
      put 0 into tBuckets[b]
   end repeat
   -- the centre-column bounds don't depend on y, so compute them once; inside
   -- each sampled row, hoist the row base so indexing is one add (tRowBase + x).
   put ((tW * 4) div 5) into tRight
   put (tW div 5) into tLeft
   repeat with y = 1 to 4
      put ((tH * y) div 5) into tRow
      put (tRow * tW) into tRowBase
      repeat with x = tLeft to (tRight - 1)
         put tLum[tRowBase + x] into tPixel
         add 1 to tBuckets[qr_uShr(tPixel, kLumShift)]
      end repeat
   end repeat

   put ghb_estimateBlackPoint(tBuckets) into blackPoint

   -- threshold the whole image: pixel < blackPoint => black. HOT PATH (2026-09):
   -- the matrix is fresh (all zero), so each 32-pixel word is accumulated in a
   -- local and stored once - exactly the bits bitMatrix_set would have set one
   -- command call at a time (proven bit-identical under the headless model).
   ghb_ensurePow2
   put tMatrix["bits"] into tBits
   put tMatrix["rowSize"] into tRowSize
   repeat with y = 0 to (tH - 1)
      put (y * tW) into tOffset
      put (y * tRowSize) into tWordOff
      put 0 into tAcc
      put 0 into tBit
      repeat with x = 0 to (tW - 1)
         if tLum[tOffset + x] < blackPoint then add sGHPow2[tBit] to tAcc
         add 1 to tBit
         if tBit = 32 then
            if tAcc <> 0 then put tAcc into tBits[tWordOff]
            add 1 to tWordOff
            put 0 into tAcc
            put 0 into tBit
         end if
      end repeat
      if tAcc <> 0 then put tAcc into tBits[tWordOff]
   end repeat
   put tBits into tMatrix["bits"]

   return tMatrix
end ghb_getBlackMatrix

-- ===================== module: hybridBinarizer =========
-- =====================================================================
-- hybridBinarizer.lc - local adaptive threshold (the default binarizer).
-- Port of ZXing HybridBinarizer. Spec section 8 / module inventory.
-- Requires: qrCompat.lc, bitMatrix.lc, luminanceSource.lc, globalHistogramBinarizer.lc.
--
-- hb_getBlackMatrix(pSrc) -> BitMatrix (true = black). Divides the image into
-- 8x8 blocks, computes each block's average (smoothed over a 5x5 neighbourhood
-- of block averages), and thresholds each pixel against the local average.
-- Falls back to the global histogram binarizer for images below MINIMUM_DIMENSION
-- (40 px) on either side (spec: HybridBinarizer flattens the inheritance and
-- calls the global path directly).
--
-- NOTE on the block-scan: ZXing has a micro-optimisation that, once a block's
-- dynamic range exceeds MIN_DYNAMIC_RANGE, sums the remaining rows without
-- updating min/max. xTalk's `repeat with` ignores in-body changes to its
-- loop counter, so that early-out cannot be expressed by mutating the counter
-- without double-counting. We sum all 64 pixels in a plain double loop - the
-- RESULT is identical (the sum is the same; once range>24 the final low-range
-- branch is skipped either way), only the per-block cost differs. (spec section 11)
-- =====================================================================

-- HOT PATH (2026-09): the threshold step writes the black matrix's 32-bit
-- words directly. A block row is 8 pixels; when those 8 bits fall inside ONE
-- word (the common, aligned case) they are accumulated in a local and OR-ed
-- into the word once; the clamped last block of a row may straddle two words
-- and takes the per-pixel path. The bits set are exactly those bitMatrix_set
-- would have set one command call at a time (proven bit-identical under the
-- headless model on every fixture).
local sHBPow2, sHBPow2Ready      -- sHBPow2[b] = 2^b, b = 0..31; built once

command hb_ensurePow2
   local b, v
   if sHBPow2Ready is true then exit hb_ensurePow2
   put 1 into v
   repeat with b = 0 to 31
      put v into sHBPow2[b]
      put (v * 2) into v
   end repeat
   put true into sHBPow2Ready
end hb_ensurePow2

constant kBlockSizePower = 3      -- 8x8 blocks
constant kBlockSize      = 8      -- 1 << kBlockSizePower
constant kBlockMask      = 7      -- kBlockSize - 1
constant kMinDimension   = 40
constant kMinDynRange    = 24     -- MIN_DYNAMIC_RANGE

-- clamp helper (ZXing `cap`)
function hb_cap pV, pMin, pMax
   if pV < pMin then return pMin
   if pV > pMax then return pMax
   return pV
end hb_cap

-- one black-point per 8x8 block: blackPoints[subHeight][subWidth] flattened
-- as a 1-D 0-based array indexed (tBy * subWidth + tBx).
function hb_calculateBlackPoints pSrc, pSubW, pSubH, pW, pH
   local tLum, tBy, tBx, tYoff, tXoff
   local tSum, minPix, maxPix, yy, xx, tRowBase
   local tPixel, tAvg, averageNeighbor, tBP
   put pSrc["lum"] into tLum
   repeat with tBy = 0 to (pSubH - 1)
      put (tBy * kBlockSize) into tYoff
      if (tYoff + kBlockSize) > pH then put (pH - kBlockSize) into tYoff
      repeat with tBx = 0 to (pSubW - 1)
         put (tBx * kBlockSize) into tXoff
         if (tXoff + kBlockSize) > pW then put (pW - kBlockSize) into tXoff
         put 0 into tSum
         put 255 into minPix
         put 0 into maxPix
         -- hoist the row base out of the inner loop: index arithmetic per pixel
         -- drops from (row*pW + col) -- a multiply + two adds -- to one add
         -- (tRowBase + xx). Same flat index, so the sum/min/max are identical.
         repeat with yy = 0 to (kBlockSize - 1)
            put (((tYoff + yy) * pW) + tXoff) into tRowBase
            repeat with xx = 0 to (kBlockSize - 1)
               put tLum[tRowBase + xx] into tPixel
               add tPixel to tSum
               if tPixel < minPix then put tPixel into minPix
               if tPixel > maxPix then put tPixel into maxPix
            end repeat
         end repeat
         put (tSum div (kBlockSize * kBlockSize)) into tAvg
         if (maxPix - minPix) <= kMinDynRange then
            -- low range: likely a single colour. Black point = min/2, unless
            -- this block is darker than the average of its (already computed)
            -- top/left neighbours.
            put (minPix div 2) into tAvg
            if (tBy > 0) and (tBx > 0) then
               put ( tBP[(tBy-1) * pSubW + tBx] \
                   + (2 * tBP[tBy * pSubW + (tBx-1)]) \
                   + tBP[(tBy-1) * pSubW + (tBx-1)] ) into averageNeighbor
               put (averageNeighbor div 4) into averageNeighbor
               if minPix < averageNeighbor then put averageNeighbor into tAvg
            end if
         end if
         put tAvg into tBP[tBy * pSubW + tBx]
      end repeat
   end repeat
   return tBP
end hb_calculateBlackPoints

-- threshold the 8x8 block at (tBx,tBy) against the 5x5-smoothed local average.
-- pBits (the matrix's flat word array), pLum (the whole luminance plane) and
-- pBP (the black points) are taken BY REFERENCE: @ guarantees the large arrays
-- are never copied per block (this runs once per 8x8 block, i.e. tens of
-- thousands of times on a big image). Same big-array-by-ref idiom as qr_arraycopy.
command hb_thresholdBlock @pBits, @pLum, @pBP, tBx, tBy, pSubW, pSubH, pW, pH, pRowSize
   local tXoff, tYoff, tTop, leftBlk, tSum, dy, dx, tAvg, yy, xx
   local tNbBase, tRowY, tRowBase, tBit0, tOneWord, tAcc, tOff, x
   put (tBx * kBlockSize) into tXoff
   if (tXoff + kBlockSize) > pW then put (pW - kBlockSize) into tXoff
   put (tBy * kBlockSize) into tYoff
   if (tYoff + kBlockSize) > pH then put (pH - kBlockSize) into tYoff

   put hb_cap(tBy, 2, pSubH - 3) into tTop
   put hb_cap(tBx, 2, pSubW - 3) into leftBlk
   put 0 into tSum
   repeat with dy = -2 to 2
      put (((tTop + dy) * pSubW) + leftBlk) into tNbBase
      repeat with dx = -2 to 2
         add pBP[tNbBase + dx] to tSum
      end repeat
   end repeat
   put (tSum div 25) into tAvg

   -- the 8 pixels of a block row share one 32-bit word when the block's first
   -- bit index within its word is <= 24 (every 8-aligned block; only a clamped
   -- last block can straddle two words)
   put (tXoff bitAnd 31) into tBit0
   put (tBit0 <= 24) into tOneWord
   repeat with yy = 0 to (kBlockSize - 1)
      put (tYoff + yy) into tRowY
      put ((tRowY * pW) + tXoff) into tRowBase
      if tOneWord then
         put 0 into tAcc
         repeat with xx = 0 to (kBlockSize - 1)
            if pLum[tRowBase + xx] <= tAvg then add sHBPow2[tBit0 + xx] to tAcc
         end repeat
         if tAcc <> 0 then
            put ((tRowY * pRowSize) + (tXoff div 32)) into tOff
            put (pBits[tOff] bitOr tAcc) into pBits[tOff]
         end if
      else
         repeat with xx = 0 to (kBlockSize - 1)
            if pLum[tRowBase + xx] <= tAvg then
               put (tXoff + xx) into x
               put ((tRowY * pRowSize) + (x div 32)) into tOff
               put (pBits[tOff] bitOr sHBPow2[x bitAnd 31]) into pBits[tOff]
            end if
         end repeat
      end if
   end repeat
end hb_thresholdBlock

function hb_getBlackMatrix pSrc
   local tW, tH, tSubW, tSubH, tBP, tMatrix, tBx, tBy, tLum, tBits, tRowSize
   put pSrc["width"] into tW
   put pSrc["height"] into tH

   -- small images: fall back to the global histogram path (flattened inheritance)
   if (tW < kMinDimension) or (tH < kMinDimension) then
      return ghb_getBlackMatrix(pSrc)
   end if

   put (tW div kBlockSize) into tSubW
   if (tW bitAnd kBlockMask) <> 0 then add 1 to tSubW
   put (tH div kBlockSize) into tSubH
   if (tH bitAnd kBlockMask) <> 0 then add 1 to tSubH

   put hb_calculateBlackPoints(pSrc, tSubW, tSubH, tW, tH) into tBP
   put bitMatrix_new(tW, tH) into tMatrix
   -- Hoist the luminance plane and the matrix's word array into locals ONCE,
   -- then pass them (and the black points) by reference per block, instead of
   -- re-evaluating a subarray extraction on every one of the tSubW*tSubH
   -- iterations; the words go back into the matrix once at the end.
   hb_ensurePow2
   put pSrc["lum"] into tLum
   put tMatrix["bits"] into tBits
   put tMatrix["rowSize"] into tRowSize
   repeat with tBy = 0 to (tSubH - 1)
      repeat with tBx = 0 to (tSubW - 1)
         hb_thresholdBlock tBits, tLum, tBP, tBx, tBy, tSubW, tSubH, tW, tH, tRowSize
      end repeat
   end repeat
   put tBits into tMatrix["bits"]
   return tMatrix
end hb_getBlackMatrix

-- ===================== module: binaryBitmap ============
-- =====================================================================
-- binaryBitmap.lc - caches the black matrix for the reader. Spec section 3, sectionmodule inv.
-- Port of ZXing BinaryBitmap. Requires: bitMatrix.lc, hybridBinarizer.lc,
-- globalHistogramBinarizer.lc, luminanceSource.lc.
--
-- Instance (Pattern A):
--   pObj["src"]       - luminanceSource array
--   pObj["binarizer"] - "hybrid" (default) or "global"
--   pObj["matrix"]    - cached BitMatrix (computed lazily by the selected binarizer)
--   pObj["hasMatrix"] - whether the cache is populated
--
-- The detector pulls the binarized BitMatrix from here; binaryBitmap_getBlackMatrix
-- computes it once (HybridBinarizer, the default) and caches it.
-- =====================================================================

-- pBinarizer (optional): "hybrid" (default) or "global". The hybrid local
-- adaptive threshold is best for uneven lighting/glare; the global histogram is
-- a useful fallback for low-contrast or evenly-lit images where hybrid's small
-- blocks can misfire. A robust reader tries both (see qrDecodeResultRobust).
function binaryBitmap_new pSrc, pBinarizer
   local tObj
   put pSrc into tObj["src"]
   put false into tObj["hasMatrix"]
   if pBinarizer is "global" then
      put "global" into tObj["binarizer"]
   else
      put "hybrid" into tObj["binarizer"]
   end if
   return tObj
end binaryBitmap_new

function binaryBitmap_getWidth pObj
   return pObj["src"]["width"]
end binaryBitmap_getWidth

function binaryBitmap_getHeight pObj
   return pObj["src"]["height"]
end binaryBitmap_getHeight

-- lazily compute + cache the black matrix (default: hybrid binarizer)
command binaryBitmap_ensureMatrix @pObj
   if pObj["hasMatrix"] then
      exit binaryBitmap_ensureMatrix
   end if
   if pObj["binarizer"] is "global" then
      put ghb_getBlackMatrix(pObj["src"]) into pObj["matrix"]
   else
      put hb_getBlackMatrix(pObj["src"]) into pObj["matrix"]
   end if
   put true into pObj["hasMatrix"]
end binaryBitmap_ensureMatrix

function binaryBitmap_getBlackMatrix pObj
   binaryBitmap_ensureMatrix pObj
   return pObj["matrix"]
end binaryBitmap_getBlackMatrix

-- ASCII preview of the cached matrix ("X" = black, " " = white), for debugging
-- and for the section 10.5 cross-oracle dump against the PHP reference.
function binaryBitmap_toString pObj
   local m, w, h, x, y, s, tLine
   binaryBitmap_ensureMatrix pObj
   put pObj["matrix"] into m
   put m["width"] into w
   put m["height"] into h
   put empty into s
   repeat with y = 0 to (h - 1)
      put empty into tLine
      repeat with x = 0 to (w - 1)
         if bitMatrix_get(m, x, y) then
            put "X" after tLine
         else
            put " " after tLine
         end if
      end repeat
      put tLine & cr after s
   end repeat
   return s
end binaryBitmap_toString

-- ===================== module: errorCorrectionLevel ====
-- =====================================================================
-- errorCorrectionLevel.lc - QR error-correction levels. Spec section 8.5.
-- Port of ZXing Qrcode\Decoder\ErrorCorrectionLevel. Requires: nothing.
--
-- THE ORDINAL/BIT SUBTLETY (spec section 13 checklist item):
-- ZXing orders the enum L, M, Q, H (ordinals 0,1,2,3) but the 2-bit field
-- stored in the format information is:  M=00, L=01, H=10, Q=11.
-- The ECBlocks array in Version is indexed by getOrdinal() (the L,M,Q,H order),
-- NOT by the bit value. Reproduce both mappings exactly; do not "fix" them.
--
-- Representation: an EC level is just its ORDINAL integer 0..3 (L,M,Q,H).
-- Helpers convert to/from the 2-bit format-info value and the name.
-- =====================================================================

-- ordinal (0..3) -> name  (ZXing order L,M,Q,H)
function ecl_name pOrdinal
   switch pOrdinal
      case 0
         return "L"
      case 1
         return "M"
      case 2
         return "Q"
      case 3
         return "H"
   end switch
   throw "Format: bad EC ordinal " & pOrdinal
end ecl_name

-- the 2-bit value stored in format info, by ordinal.  L=01,M=00,Q=11,H=10
function ecl_bits pOrdinal
   switch pOrdinal
      case 0
         return 1     -- L = 01
      case 1
         return 0     -- M = 00
      case 2
         return 3     -- Q = 11
      case 3
         return 2     -- H = 10
   end switch
   throw "Format: bad EC ordinal " & pOrdinal
end ecl_bits

-- decode the 2-bit format-info field -> ordinal (0..3).  00->M(1),01->L(0),10->H(3),11->Q(2)
function ecl_forBits pBits
   switch pBits
      case 0
         return 1     -- 00 -> M
      case 1
         return 0     -- 01 -> L
      case 2
         return 3     -- 10 -> H
      case 3
         return 2     -- 11 -> Q
   end switch
   throw "Format: EC bits out of range " & pBits
end ecl_forBits

-- ===================== module: mode ====================
-- =====================================================================
-- mode.lc - QR encoding-mode table. Spec section 8.5.
-- Port of ZXing Qrcode\Decoder\Mode. Requires: nothing.
--
-- A "mode" is identified by its canonical NAME string (e.g. "NUMERIC").
-- mode_forBits(v) maps the 4-bit mode indicator -> name (throws on unknown).
-- mode_charCountBits(name, version) returns the character-count bit width for
-- the version range: offset 0 if v<=9, 1 if v<=26, else 2.
--
-- Table (verbatim, spec section 8.5):
--   mode                 ccBits [v1-9,v10-26,v27-40]   4-bit value
--   TERMINATOR           0,0,0                          0x00
--   NUMERIC              10,12,14                       0x01
--   ALPHANUMERIC         9,11,13                        0x02
--   STRUCTURED_APPEND    0,0,0                          0x03
--   BYTE                 8,16,16                        0x04
--   FNC1_FIRST_POSITION  0,0,0                          0x05
--   ECI                  0,0,0                          0x07
--   KANJI                8,10,12                        0x08
--   FNC1_SECOND_POSITION 0,0,0                          0x09
--   HANZI (GB2312)       8,10,12                        0x0D
-- =====================================================================

-- 4-bit mode indicator -> canonical name
function mode_forBits pBits
   switch pBits
      case 0
         return "TERMINATOR"
      case 1
         return "NUMERIC"
      case 2
         return "ALPHANUMERIC"
      case 3
         return "STRUCTURED_APPEND"
      case 4
         return "BYTE"
      case 5
         return "FNC1_FIRST_POSITION"
      case 7
         return "ECI"
      case 8
         return "KANJI"
      case 9
         return "FNC1_SECOND_POSITION"
      case 13                       -- 0x0D
         return "HANZI"
   end switch
   throw "Format: unknown mode bits " & pBits
end mode_forBits

-- version range index: 0 for v1-9, 1 for v10-26, 2 for v27-40
function mode_versionOffset pVersion
   if pVersion <= 9 then
      return 0
   end if
   if pVersion <= 26 then
      return 1
   end if
   return 2
end mode_versionOffset

-- character-count bit width for the given mode name and version
function mode_charCountBits pName, pVersion
   local tOff, tTriple
   put mode_versionOffset(pVersion) into tOff
   switch pName
      case "NUMERIC"
         put "10,12,14" into tTriple
         break
      case "ALPHANUMERIC"
         put "9,11,13" into tTriple
         break
      case "BYTE"
         put "8,16,16" into tTriple
         break
      case "KANJI"
         put "8,10,12" into tTriple
         break
      case "HANZI"
         put "8,10,12" into tTriple
         break
      default
         return 0                  -- TERMINATOR/ECI/FNC1/STRUCTURED_APPEND
   end switch
   set the itemDelimiter to comma
   return (item (tOff + 1) of tTriple)
end mode_charCountBits

-- ===================== module: dataMask ================
-- =====================================================================
-- dataMask.lc - the 8 QR data-mask predicates. Spec section 8.5.
-- Port of ZXing Qrcode\Decoder\DataMask. Requires: qrCompat.lc, bitMatrix.lc.
--
-- dataMask_isMasked(ref, i, j) -> boolean   (i = row, j = column)
--   ref  formula
--   0    ((i + j) bitAnd 1) = 0
--   1    (i bitAnd 1) = 0
--   2    j mod 3 = 0
--   3    (i + j) mod 3 = 0
--   4    (((i div 2) + (j div 3)) bitAnd 1) = 0
--   5    ((i*j) mod 2) + ((i*j) mod 3) = 0
--   6    (((i*j) mod 2) + ((i*j) mod 3)) bitAnd 1 = 0
--   7    ((((i+j) bitAnd 1) + ((i*j) mod 3)) bitAnd 1) = 0
--
-- dataMask_unmask(bits, dimension, ref) flips every (i,j) where the predicate
-- is true, in place (bits passed by @). Masking is an involution, so the same
-- routine both applies and removes the mask.
-- =====================================================================

function dataMask_isMasked pRef, i, j
   local tmp
   switch pRef
      case 0
         return (((i + j) bitAnd 1) = 0)
      case 1
         return ((i bitAnd 1) = 0)
      case 2
         return ((j mod 3) = 0)
      case 3
         return (((i + j) mod 3) = 0)
      case 4
         return ((((i div 2) + (j div 3)) bitAnd 1) = 0)
      case 5
         put (i * j) into tmp
         return ((((tmp mod 2) + (tmp mod 3)) ) = 0)
      case 6
         put (i * j) into tmp
         return ((((tmp mod 2) + (tmp mod 3)) bitAnd 1) = 0)
      case 7
         return (((((i + j) bitAnd 1) + ((i * j) mod 3)) bitAnd 1) = 0)
   end switch
   throw "Format: bad data mask reference " & pRef
end dataMask_isMasked

local sDMPow2, sDMPow2Ready      -- sDMPow2[b] = 2^b, b = 0..31; built once

command dm_ensurePow2
   local b, v
   if sDMPow2Ready is true then exit dm_ensurePow2
   put 1 into v
   repeat with b = 0 to 31
      put v into sDMPow2[b]
      put (v * 2) into v
   end repeat
   put true into sDMPow2Ready
end dm_ensurePow2

-- flip the masked cells of the dimension x dimension matrix, in place. The
-- flips go to the matrix's word array directly (x = j, y = i) - the same bits
-- bitMatrix_flip toggles one command call at a time.
command dataMask_unmask @pBits, pDimension, pRef
   local i, j, tWords, tRowSize, tRowBase, tOff
   dm_ensurePow2
   put pBits["bits"] into tWords
   put pBits["rowSize"] into tRowSize
   repeat with i = 0 to (pDimension - 1)
      put (i * tRowSize) into tRowBase
      repeat with j = 0 to (pDimension - 1)
         if dataMask_isMasked(pRef, i, j) then
            put (tRowBase + (j div 32)) into tOff
            put (tWords[tOff] bitXor sDMPow2[j bitAnd 31]) into tWords[tOff]
         end if
      end repeat
   end repeat
   put tWords into pBits["bits"]
end dataMask_unmask

-- ===================== module: formatInformation =======
-- =====================================================================
-- formatInformation.lc - decode the 15-bit QR format info. Spec section 8.5.
-- Port of ZXing Qrcode\Decoder\FormatInformation.
-- Requires: qrCompat.lc, errorCorrectionLevel.lc.
--
-- The format info encodes a 2-bit EC level + 3-bit data-mask reference, BCH(15,5)
-- protected and XOR-masked with 0x5412. Decoding:
--   * compare each 15-bit read directly against the masked lookup column (the
--     0x5412 mask is pre-applied to the table, so there is no run-time XOR),
--   * pick the lookup entry with the fewest differing bits, accept if <= 3,
--   * compare the two on-symbol copies and keep the better.
-- Returns an array: ["ecLevel"] = EC ordinal (0..3, L/M/Q/H), ["dataMask"] = 0..7.
--
-- FORMAT_INFO_DECODE_LOOKUP rows are "dataBits,maskedSequence" (verified by
-- regenerating from BCH gen 0x537 ^ 0x5412 - see tools/verify, 32 entries).
-- dataBits high 2 bits = EC field value (M=00,L=01,H=10,Q=11), low 3 = mask ref.
-- =====================================================================

-- The QR format-info mask (0x5412). The lookup column sFmtSeq below already
-- has this applied (entries = bch(data) XOR this), so on-symbol reads are
-- compared directly - no run-time XOR needed. Kept for documentation.
constant kFormatInfoMaskQR = 21522    -- 0x5412

local sFmtReady, sFmtData, sFmtSeq

command fmt_init
   local tRows, r, n, nRows, i
   put \
"0,21522;1,20773;2,24188;3,23371;4,17913;5,16590;6,20375;7,19104;8,30660;9,29427;10,32170;11,30877;12,26159;13,25368;14,27713;15,26998;16,5769;17,5054;18,7399;19,6608;20,1890;21,597;22,3340;23,2107;24,13663;25,12392;26,16177;27,14854;28,9396;29,8579;30,11994;31,11245" \
      into tRows
   -- index by count, NOT `repeat for each`, so we can switch itemDelimiter
   -- safely between the outer ";" split and the inner "," split.
   set the itemDelimiter to ";"
   put the number of items of tRows into nRows
   put 0 into n
   repeat with i = 1 to nRows
      set the itemDelimiter to ";"
      put (item i of tRows) into r
      set the itemDelimiter to comma
      put (item 1 of r) into sFmtData[n]
      put (item 2 of r) into sFmtSeq[n]
      add 1 to n
   end repeat
   put true into sFmtReady
end fmt_init

command fmt_ensure
   if sFmtReady is not true then fmt_init
end fmt_ensure

-- population count (number of 1 bits); used for Hamming distance via XOR
function fmt_popcount n
   local c
   put 0 into c
   put qr_u32(n) into n
   repeat while n > 0
      add (n bitAnd 1) to c
      put (n div 2) into n
   end repeat
   return c
end fmt_popcount

-- public: decode using the two on-symbol copies. Both 15-bit reads are
-- compared (nearest-match across BOTH) against the masked lookup column, as
-- ZXing's doDecodeFormatInformation does. Returns {ecLevel,dataMask} or empty.
function fmt_decode pFormatInfo1, pFormatInfo2
   local bestDifference, bestData, i, targetInfo, d1, d2
   fmt_ensure
   put 32 into bestDifference
   put -1 into bestData
   repeat with i = 0 to 31
      put sFmtSeq[i] into targetInfo
      -- exact match on either copy wins immediately
      if (pFormatInfo1 = targetInfo) or (pFormatInfo2 = targetInfo) then
         return fmt_unpack(sFmtData[i])
      end if
      -- otherwise track the closest over BOTH copies
      put fmt_popcount(qr_u32(pFormatInfo1 bitXor targetInfo)) into d1
      if d1 < bestDifference then
         put sFmtData[i] into bestData
         put d1 into bestDifference
      end if
      if pFormatInfo1 <> pFormatInfo2 then
         put fmt_popcount(qr_u32(pFormatInfo2 bitXor targetInfo)) into d2
         if d2 < bestDifference then
            put sFmtData[i] into bestData
            put d2 into bestDifference
         end if
      end if
   end repeat
   if bestDifference <= 3 then
      return fmt_unpack(bestData)
   end if
   return empty
end fmt_decode

-- split a 5-bit data value into {ecLevel ordinal, dataMask}
function fmt_unpack pDataBits
   local tRes
   put ecl_forBits(qr_uShr(pDataBits, 3) bitAnd 3) into tRes["ecLevel"]
   put (pDataBits bitAnd 7) into tRes["dataMask"]
   return tRes
end fmt_unpack

-- ===================== module: version =================
-- =====================================================================
-- version.lc - QR Version/EC-block tables (v1-40). Spec section 8.5 (largest table).
-- Port of ZXing Qrcode\Decoder\Version. Requires: qrCompat.lc, errorCorrectionLevel.lc.
--
-- The table below was GENERATED from the ZXing data and is re-verified by a
-- COMMITTED oracle, tools/verify_tables.py (run in CI): every row is diffed
-- field by field against ZXing's Version.java data, every version x level
-- total matches the ISO/IEC 18004 codeword totals derived from first
-- principles, and the 34 version-info words regenerate from BCH gen 0x1F25.
-- (2026-09: rows 39 and 40 carried wrong alignment-centre lists - eight
-- entries, two of them beyond the symbol - so v39/v40 symbols threw
-- "BitMatrix: region must fit inside matrix"; found by a synthetic-fixture
-- corpus generated with an independent encoder and fixed from ZXing's table.)
-- Each row (delimited by "~"):  ver ~ alignCenters ~ Lblocks ~ Mblocks ~ Qblocks ~ Hblocks
-- alignCenters: comma list (empty for v1).
-- a "blocks" field is "ecw/count,data[/count,data]"  (ecw = EC codewords/block).
--
-- Stored form after init (per version v, 1-based here only as a key):
--   sVer[v]["dimension"]   = 17 + 4v
--   sVer[v]["align"]       = comma list of centres
--   sVer[v]["ec"][ord]     = "ecw;count,data;count,data..."  (ord 0..3 = L,M,Q,H)
-- ECBlocks are indexed by EC ORDINAL (L,M,Q,H) per ErrorCorrectionLevel (spec section 8.5).
--
-- VERSION_DECODE_INFO: the 34 raw 18-bit version-info patterns for v7-40.
-- =====================================================================

local sVerReady, sVer, sVDI

command ver_init
   local tTable, tRow, v, tItems, tEC, ord, tBlk
   put ver_tableData() into tTable
   set the lineDelimiter to lf
   repeat for each line tRow in tTable
      if tRow is empty then next repeat
      set the itemDelimiter to "~"
      put (item 1 of tRow) into v
      put (17 + (4 * v)) into sVer[v]["dimension"]
      put (item 2 of tRow) into sVer[v]["align"]
      repeat with ord = 0 to 3
         put (item (3 + ord) of tRow) into tBlk      -- e.g. "18/2,15/2,16"
         put ver_parseBlocks(tBlk) into sVer[v]["ec"][ord]
      end repeat
   end repeat
   -- version-info decode patterns (v7..40), index 0 => v7
   put \
"31892,34236,39577,42195,48118,51042,55367,58893,63784,68472,70749,76311,79154,84390,87683,92361,96236,102084,102881,110507,110734,117786,119615,126325,127568,133589,136944,141498,145311,150283,152622,158308,161089,167017" \
      into sVDI
   put true into sVerReady
end ver_init

command ver_ensure
   if sVerReady is not true then ver_init
end ver_ensure

-- population count (local copy so version.lc has no cross-module dependency)
function ver_popcount n
   local c
   put 0 into c
   put qr_u32(n) into n
   repeat while n > 0
      add (n bitAnd 1) to c
      put (n div 2) into n
   end repeat
   return c
end ver_popcount

-- parse "ecw/count,data[/count,data]" -> "ecw;count,data;count,data"
function ver_parseBlocks pBlk
   local tOut, i, tCount
   set the itemDelimiter to "/"
   put the number of items of pBlk into tCount
   put (item 1 of pBlk) into tOut          -- first field is ecw
   repeat with i = 2 to tCount
      put ";" & (item i of pBlk) after tOut    -- ";count,data"
   end repeat
   return tOut
end ver_parseBlocks

-- ZXing Version.getVersionForNumber throws for anything outside 1..40; the
-- table lookups below would otherwise hand back empty fields that flow into
-- arithmetic far from the cause.
command ver_checkNumber pVersion
   if (pVersion is not an integer) or (pVersion < 1) or (pVersion > 40) then
      throw "Format: version " & pVersion & " out of range 1..40"
   end if
end ver_checkNumber

function ver_getDimensionForVersion pVersion
   ver_checkNumber pVersion
   ver_ensure
   return sVer[pVersion]["dimension"]
end ver_getDimensionForVersion

function ver_getAlignmentCenters pVersion
   ver_checkNumber pVersion
   ver_ensure
   return sVer[pVersion]["align"]      -- comma list (may be empty)
end ver_getAlignmentCenters

-- EC codewords per block, for version + EC ordinal
function ver_getEcCodewordsPerBlock pVersion, pEcOrdinal
   local tEC
   ver_checkNumber pVersion
   ver_ensure
   put sVer[pVersion]["ec"][pEcOrdinal] into tEC
   set the itemDelimiter to ";"
   return (item 1 of tEC)
end ver_getEcCodewordsPerBlock

-- returns the block layout as lines "count,dataCodewords" for version+ordinal
function ver_getEcBlocks pVersion, pEcOrdinal
   local tEC, tOut, i
   ver_checkNumber pVersion
   ver_ensure
   put sVer[pVersion]["ec"][pEcOrdinal] into tEC
   set the itemDelimiter to ";"
   put empty into tOut
   repeat with i = 2 to (the number of items of tEC)
      put (item i of tEC) & lf after tOut
   end repeat
   return tOut          -- e.g. "2,15" & lf & "2,16"
end ver_getEcBlocks

-- total number of data codewords across all blocks (version+ordinal)
function ver_getTotalDataCodewords pVersion, pEcOrdinal
   local tBlocks, tLn, tSum, cnt, dat
   put ver_getEcBlocks(pVersion, pEcOrdinal) into tBlocks
   put 0 into tSum
   set the lineDelimiter to lf
   repeat for each line tLn in tBlocks
      if tLn is empty then next repeat
      set the itemDelimiter to comma
      put (item 1 of tLn) into cnt
      put (item 2 of tLn) into dat
      add (cnt * dat) to tSum
   end repeat
   return tSum
end ver_getTotalDataCodewords

-- total codewords (data + EC) in a symbol of this version; the same for every
-- EC level, so the L layout (ordinal 0) is summed. ZXing Version.getTotalCodewords.
function ver_getTotalCodewords pVersion
   local tBlocks, tLn, tSum, cnt, dat, tEcw
   put ver_getEcCodewordsPerBlock(pVersion, 0) into tEcw
   put ver_getEcBlocks(pVersion, 0) into tBlocks
   put 0 into tSum
   set the lineDelimiter to lf
   repeat for each line tLn in tBlocks
      if tLn is empty then next repeat
      set the itemDelimiter to comma
      put (item 1 of tLn) into cnt
      put (item 2 of tLn) into dat
      add (cnt * (dat + tEcw)) to tSum
   end repeat
   return tSum
end ver_getTotalCodewords

-- version implied by a sampled dimension: (dimension - 17) / 4; a dimension
-- outside 21..177 is a Format error, as in ZXing (getVersionForNumber throws).
function ver_getProvisionalVersionForDimension pDimension
   local tVer
   if ((pDimension mod 4) <> 1) then throw "Format: dimension not %4==1"
   put ((pDimension - 17) div 4) into tVer
   ver_checkNumber tVer
   return tVer
end ver_getProvisionalVersionForDimension

-- decode the 18-bit version information (Hamming-nearest within <=3 bits)
-- returns version number (7..40) or empty if none close enough.
function ver_decodeVersionInformation pVersionBits
   local bestDifference, bestVersion, i, targetVersion, bitsDifference
   ver_ensure
   put 32 into bestDifference
   put 0 into bestVersion
   set the itemDelimiter to comma
   repeat with i = 1 to (the number of items of sVDI)
      put (item i of sVDI) into targetVersion
      if targetVersion = pVersionBits then
         return (i + 6)               -- index 1 => v7
      end if
      put ver_popcount(qr_u32(pVersionBits bitXor targetVersion)) into bitsDifference
      if bitsDifference < bestDifference then
         put (i + 6) into bestVersion
         put bitsDifference into bestDifference
      end if
   end repeat
   if bestDifference <= 3 then
      return bestVersion
   end if
   return empty
end ver_decodeVersionInformation

-- The generated + verified table (see header). One version per line.
function ver_tableData
   local t
   put "1~~7/1,19~10/1,16~13/1,13~17/1,9" & lf after t
   put "2~6,18~10/1,34~16/1,28~22/1,22~28/1,16" & lf after t
   put "3~6,22~15/1,55~26/1,44~18/2,17~22/2,13" & lf after t
   put "4~6,26~20/1,80~18/2,32~26/2,24~16/4,9" & lf after t
   put "5~6,30~26/1,108~24/2,43~18/2,15/2,16~22/2,11/2,12" & lf after t
   put "6~6,34~18/2,68~16/4,27~24/4,19~28/4,15" & lf after t
   put "7~6,22,38~20/2,78~18/4,31~18/2,14/4,15~26/4,13/1,14" & lf after t
   put "8~6,24,42~24/2,97~22/2,38/2,39~22/4,18/2,19~26/4,14/2,15" & lf after t
   put "9~6,26,46~30/2,116~22/3,36/2,37~20/4,16/4,17~24/4,12/4,13" & lf after t
   put "10~6,28,50~18/2,68/2,69~26/4,43/1,44~24/6,19/2,20~28/6,15/2,16" & lf after t
   put "11~6,30,54~20/4,81~30/1,50/4,51~28/4,22/4,23~24/3,12/8,13" & lf after t
   put "12~6,32,58~24/2,92/2,93~22/6,36/2,37~26/4,20/6,21~28/7,14/4,15" & lf after t
   put "13~6,34,62~26/4,107~22/8,37/1,38~24/8,20/4,21~22/12,11/4,12" & lf after t
   put "14~6,26,46,66~30/3,115/1,116~24/4,40/5,41~20/11,16/5,17~24/11,12/5,13" & lf after t
   put "15~6,26,48,70~22/5,87/1,88~24/5,41/5,42~30/5,24/7,25~24/11,12/7,13" & lf after t
   put "16~6,26,50,74~24/5,98/1,99~28/7,45/3,46~24/15,19/2,20~30/3,15/13,16" & lf after t
   put "17~6,30,54,78~28/1,107/5,108~28/10,46/1,47~28/1,22/15,23~28/2,14/17,15" & lf after t
   put "18~6,30,56,82~30/5,120/1,121~26/9,43/4,44~28/17,22/1,23~28/2,14/19,15" & lf after t
   put "19~6,30,58,86~28/3,113/4,114~26/3,44/11,45~26/17,21/4,22~26/9,13/16,14" & lf after t
   put "20~6,34,62,90~28/3,107/5,108~26/3,41/13,42~30/15,24/5,25~28/15,15/10,16" & lf after t
   put "21~6,28,50,72,94~28/4,116/4,117~26/17,42~28/17,22/6,23~30/19,16/6,17" & lf after t
   put "22~6,26,50,74,98~28/2,111/7,112~28/17,46~30/7,24/16,25~24/34,13" & lf after t
   put "23~6,30,54,78,102~30/4,121/5,122~28/4,47/14,48~30/11,24/14,25~30/16,15/14,16" & lf after t
   put "24~6,28,54,80,106~30/6,117/4,118~28/6,45/14,46~30/11,24/16,25~30/30,16/2,17" & lf after t
   put "25~6,32,58,84,110~26/8,106/4,107~28/8,47/13,48~30/7,24/22,25~30/22,15/13,16" & lf after t
   put "26~6,30,58,86,114~28/10,114/2,115~28/19,46/4,47~28/28,22/6,23~30/33,16/4,17" & lf after t
   put "27~6,34,62,90,118~30/8,122/4,123~28/22,45/3,46~30/8,23/26,24~30/12,15/28,16" & lf after t
   put "28~6,26,50,74,98,122~30/3,117/10,118~28/3,45/23,46~30/4,24/31,25~30/11,15/31,16" & lf after t
   put "29~6,30,54,78,102,126~30/7,116/7,117~28/21,45/7,46~30/1,23/37,24~30/19,15/26,16" & lf after t
   put "30~6,26,52,78,104,130~30/5,115/10,116~28/19,47/10,48~30/15,24/25,25~30/23,15/25,16" & lf after t
   put "31~6,30,56,82,108,134~30/13,115/3,116~28/2,46/29,47~30/42,24/1,25~30/23,15/28,16" & lf after t
   put "32~6,34,60,86,112,138~30/17,115~28/10,46/23,47~30/10,24/35,25~30/19,15/35,16" & lf after t
   put "33~6,30,58,86,114,142~30/17,115/1,116~28/14,46/21,47~30/29,24/19,25~30/11,15/46,16" & lf after t
   put "34~6,34,62,90,118,146~30/13,115/6,116~28/14,46/23,47~30/44,24/7,25~30/59,16/1,17" & lf after t
   put "35~6,30,54,78,102,126,150~30/12,121/7,122~28/12,47/26,48~30/39,24/14,25~30/22,15/41,16" & lf after t
   put "36~6,24,50,76,102,128,154~30/6,121/14,122~28/6,47/34,48~30/46,24/10,25~30/2,15/64,16" & lf after t
   put "37~6,28,54,80,106,132,158~30/17,122/4,123~28/29,46/14,47~30/49,24/10,25~30/24,15/46,16" & lf after t
   put "38~6,32,58,84,110,136,162~30/4,122/18,123~28/13,46/32,47~30/48,24/14,25~30/42,15/32,16" & lf after t
   put "39~6,26,54,82,110,138,166~30/20,117/4,118~28/40,47/7,48~30/43,24/22,25~30/10,15/67,16" & lf after t
   put "40~6,30,58,86,114,142,170~30/19,118/6,119~28/18,47/31,48~30/34,24/34,25~30/20,15/61,16" & lf after t
   return t
end ver_tableData

-- ===================== module: characterSetECI =========
-- =====================================================================
-- characterSetECI.lc - ECI numeric value -> charset name. Spec section 8.6.
-- Port of (the used subset of) ZXing Common\CharacterSetECI.
-- Requires: nothing.
--
-- Only the values likely to appear are mapped; the byte decoder
-- (decodedBitStreamParser) only natively handles ASCII / ISO-8859-1 / UTF-8
-- (spec section 8.7), so other charsets resolve to a name that decoder treats as a
-- best-effort fallback.
-- =====================================================================

function eci_charsetName pValue
   switch pValue
      case 0
      case 2
         return "Cp437"
      case 1
      case 3
         return "ISO-8859-1"
      case 4
         return "ISO-8859-2"
      case 5
         return "ISO-8859-3"
      case 6
         return "ISO-8859-4"
      case 7
         return "ISO-8859-5"
      case 8
         return "ISO-8859-6"
      case 9
         return "ISO-8859-7"
      case 10
         return "ISO-8859-8"
      case 11
         return "ISO-8859-9"
      case 12
         return "ISO-8859-10"
      case 13
         return "ISO-8859-11"
      case 15
         return "ISO-8859-13"
      case 16
         return "ISO-8859-14"
      case 17
         return "ISO-8859-15"
      case 18
         return "ISO-8859-16"
      case 20
         return "Shift_JIS"
      case 21
         return "Cp1250"
      case 22
         return "Cp1251"
      case 23
         return "Cp1252"
      case 24
         return "Cp1256"
      case 25
         return "UTF-16BE"
      case 26
         return "UTF-8"
      case 27
      case 170
         return "US-ASCII"
      case 28
         return "Big5"
      case 29
         return "GB2312"
      case 30
         return "EUC-KR"
   end switch
   return empty                  -- unknown ECI: the caller throws Format (ZXing/PHP)
end eci_charsetName

-- ===================== module: dataBlock ===============
-- =====================================================================
-- dataBlock.lc - de-interleave codewords into Reed-Solomon blocks. Spec section 8.5.
-- Port of ZXing Qrcode\Decoder\DataBlock. Requires: qrCompat.lc, version.lc,
-- errorCorrectionLevel.lc.
--
-- db_getDataBlocks(rawCodewords, version, ecOrdinal) -> an array of blocks,
-- 0-based:  blocks[b]["numData"] = data-codeword count for block b
--           blocks[b]["cw"][i]   = codeword i (data then EC), 0-based
-- The blocks are returned in the order ZXing produces (shorter blocks first as
-- laid out by the version table, all instances expanded).
--
-- ZXing's two-pass fill (spec: "critical and easy to get wrong"):
--   pass 1 - distribute DATA codewords round-robin across all blocks, filling
--            the common (shorter) length first, then the one extra data
--            codeword that the longer blocks each carry.
--   pass 2 - distribute EC codewords round-robin across all blocks, where the
--            longer blocks' EC region starts one slot later.
-- =====================================================================

-- returns an array: ["n"] = number of blocks, [b] = block array (0-based)
function db_getDataBlocks pRaw, pVersion, pEcOrdinal
   local tEcwPerBlock, tBlockSpec, tLn, cnt, dat
   local tBlocks, tNum, b, i, j
   local tMaxData, tShorterNumData, tLongerStart, tRawIndex, tMaxLen, tIdx, tTotalLen

   put ver_getEcCodewordsPerBlock(pVersion, pEcOrdinal) into tEcwPerBlock
   put ver_getEcBlocks(pVersion, pEcOrdinal) into tBlockSpec   -- lines "count,data"

   -- expand the spec into per-instance blocks (shorter blocks come first in
   -- the version table, which is the order ZXing wants).
   put 0 into tNum
   set the lineDelimiter to lf
   repeat for each line tLn in tBlockSpec
      if tLn is empty then next repeat
      set the itemDelimiter to comma
      put (item 1 of tLn) into cnt
      put (item 2 of tLn) into dat
      repeat with b = 1 to cnt
         put dat into tBlocks[tNum]["numData"]
         put (dat + tEcwPerBlock) into tBlocks[tNum]["len"]
         add 1 to tNum
      end repeat
   end repeat

   -- ZXing/PHP refuse a raw stream whose length is not the version's total:
   -- without this, a short read would feed empty values into Reed-Solomon and
   -- fail far from the cause.
   put 0 into tTotalLen
   repeat with b = 0 to (tNum - 1)
      add tBlocks[b]["len"] to tTotalLen
   end repeat
   if (the number of elements of pRaw) <> tTotalLen then
      throw "Format: codeword count " & (the number of elements of pRaw) & " <> " & tTotalLen
   end if

   -- largest data length; "shorter" blocks have tMaxData-1 ... but per ZXing the
   -- shorter length is the FIRST block's numData; longer blocks carry +1.
   put tBlocks[0]["numData"] into tShorterNumData
   put 0 into tMaxData
   repeat with b = 0 to (tNum - 1)
      if tBlocks[b]["numData"] > tMaxData then put tBlocks[b]["numData"] into tMaxData
   end repeat
   -- index of the first "longer" block (numData == tMaxData)
   put tNum into tLongerStart
   repeat with b = 0 to (tNum - 1)
      if tBlocks[b]["numData"] = tMaxData then
         put b into tLongerStart
         exit repeat
      end if
   end repeat

   -- PASS 1: data codewords. Fill the common shorter-length columns for all
   -- blocks, then the one extra data codeword for each longer block.
   put 0 into tRawIndex
   repeat with i = 0 to (tShorterNumData - 1)
      repeat with j = 0 to (tNum - 1)
         put pRaw[tRawIndex] into tBlocks[j]["cw"][i]
         add 1 to tRawIndex
      end repeat
   end repeat
   repeat with j = tLongerStart to (tNum - 1)
      put pRaw[tRawIndex] into tBlocks[j]["cw"][tShorterNumData]
      add 1 to tRawIndex
   end repeat

   -- PASS 2: EC codewords. They run from column tShorterNumData (shorter blocks)
   -- / tShorterNumData+1 (longer blocks) up to each block's full length.
   put tBlocks[(tNum - 1)]["len"] into tMaxLen
   repeat with i = tShorterNumData to (tMaxLen - 1)
      repeat with j = 0 to (tNum - 1)
         if j < tLongerStart then
            put i into tIdx
         else
            put (i + 1) into tIdx
         end if
         if tIdx < tBlocks[j]["len"] then
            put pRaw[tRawIndex] into tBlocks[j]["cw"][tIdx]
            add 1 to tRawIndex
         end if
      end repeat
   end repeat

   put tNum into tBlocks["n"]
   return tBlocks
end db_getDataBlocks

-- ===================== module: decodedBitStreamParser ==
-- =====================================================================
-- decodedBitStreamParser.lc - bits -> text per encoding mode. Spec section 8.5.
-- Port of ZXing Qrcode\Decoder\DecodedBitStreamParser.
-- Requires: qrCompat.lc, bitSource.lc, mode.lc, characterSetECI.lc.
--
-- dbsp_decode(bytes, version, ecOrdinal) -> array result:
--   ["text"]     decoded text
--   ["bytes"]    raw decoded byte string (concatenation of BYTE segments)
--   ["error"]    set + result empty on a Format error
--   ["charset"]  the charset the BYTE segments were decoded with ("UTF-8",
--                "ISO-8859-1", "UTF-16", or the ECI's name), when any BYTE segment
--   ["fnc1"]     "first" / "second" when an FNC1 mode indicator was present
--   ["symbologyModifier"]  ZXing's 1..6 code (FNC1 kind x ECI presence)
--   ["structuredAppendSeq"], ["structuredAppendParity"]  when present (raw
--                8-bit values; seq = index*16 + (total-1) per ISO/IEC 18004)
--
-- CHARSET SELECTION (ZXing DecodedBitStreamParser.decodeByteSegment): a BYTE
-- segment is decoded with the charset named by the current ECI; with NO ECI
-- the bytes are GUESSED exactly as ZXing's StringUtils.guessCharset does on a
-- platform without Shift_JIS: UTF-16 by BOM, UTF-8 when the bytes are valid
-- UTF-8 and carry a BOM or at least one multi-byte character, else ISO-8859-1.
-- (Until 2026-09 the port always used ISO-8859-1 without an ECI, so every
-- UTF-8 payload from a phone-generated code - accents, emoji - came back as
-- mojibake; found by the synthetic corpus and confirmed against ZXing.)
--
-- PORTABILITY: the byte decoders are hand-rolled (no textDecode): ISO-8859-1
-- is byte = codepoint; UTF-8 and UTF-16 are small explicit decoders. Note that
-- textDecode(...,"UTF-8") does NOT throw on malformed input on OXT (it
-- substitutes U+FFFD), so it could never have served as a validity test.
--
-- DESIGN NOTE (important): the bit source is a SCRIPT-LOCAL (sSrc) shared by
-- all handlers in this file, NOT a passed parameter. This guarantees that each
-- mode helper's bit-position advances persist across the whole message. An
-- earlier by-value-parameter version "passed" single-segment tests only by
-- luck (the bits after the mode nibble read as TERMINATOR); a multi-segment
-- input such as ECI+BYTE exposed the misalignment. Script-locals + command-by-
-- reference are both already proven on the target engine, so this is the
-- highest-confidence design. (Decode is sequential per request - not reentrant,
-- which is fine for server use.)
--
-- Modes fully supported: NUMERIC, ALPHANUMERIC, BYTE (ISO-8859-1 / UTF-8 /
--   UTF-16, plus any ECI naming one of those), ECI, TERMINATOR, FNC1 (first and
--   second position; in an alphanumeric segment "%%" is a literal "%" and a
--   lone "%" is the GS separator), STRUCTURED_APPEND (sequence + parity).
-- KANJI / HANZI raise the documented section 8.7 limitation (no Shift-JIS /
--   GB2312 tables in this build). A BYTE segment under an ECI naming a charset
--   this build cannot decode (Shift_JIS, GB2312, Big5, Cp125x, ...) keeps the
--   raw bytes in ["bytes"], maps them byte-for-codepoint into ["text"] and
--   reports the charset in ["charset"] so a caller can tell. An UNKNOWN ECI
--   value is a Format error, as in ZXing and the PHP port.
-- =====================================================================

constant kAlphanumChars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
constant kDigits = "0123456789"
constant kGroupSeparator = 29    -- ASCII GS: the FNC1 field separator

local sSrc      -- the shared BitSource for the current decode

-- read n bits from the shared source; returns the value
function dbsp_read pNumBits
   bitSource_readBits sSrc, pNumBits
   return the result
end dbsp_read

-- main entry. pBytes is a 0-based dense array of codeword bytes.
function dbsp_decode pBytes, pVersion, pEcOrdinal
   local tResult, tRaw, tText, tMode, tBits, tCharset, tSeg, tByteRes, e, tErr
   local tFc1, tFnc1Kind, tHasEci, tUsedCharset, tSaSeq, tSaParity, tHasSa
   put bitSource_new(pBytes) into sSrc
   put empty into tText
   put empty into tRaw
   put empty into tCharset        -- empty = no ECI yet: guess per BYTE segment
   put false into tFc1
   put empty into tFnc1Kind
   put false into tHasEci
   put empty into tUsedCharset
   put false into tHasSa
   put empty into tErr

   try
      repeat
         -- if fewer than 4 bits remain, we're done (no terminator required)
         if bitSource_available(sSrc) < 4 then
            exit repeat
         end if
         put dbsp_read(4) into tBits
         put mode_forBits(tBits) into tMode

         switch tMode
            case "TERMINATOR"
               exit repeat
            case "NUMERIC"
               put dbsp_decodeNumeric(pVersion) into tSeg
               put tSeg after tText
               break
            case "ALPHANUMERIC"
               put dbsp_decodeAlphanumeric(pVersion, tFc1) into tSeg
               put tSeg after tText
               break
            case "BYTE"
               put dbsp_decodeByte(pVersion, tCharset) into tByteRes
               put tByteRes["text"] after tText
               put tByteRes["bytes"] after tRaw
               put tByteRes["charset"] into tUsedCharset
               break
            case "ECI"
               put dbsp_parseEci() into tCharset
               put true into tHasEci
               break
            case "FNC1_FIRST_POSITION"
               -- ZXing: symbology detection only; FNC1 alters alphanumeric "%"
               put true into tFc1
               put "first" into tFnc1Kind
               break
            case "FNC1_SECOND_POSITION"
               put true into tFc1
               put "second" into tFnc1Kind
               break
            case "STRUCTURED_APPEND"
               -- ZXing: 8-bit symbol sequence indicator + 8-bit parity
               if bitSource_available(sSrc) < 16 then
                  throw "Format: structured append header truncated"
               end if
               put dbsp_read(8) into tSaSeq
               put dbsp_read(8) into tSaParity
               put true into tHasSa
               break
            case "KANJI"
            case "HANZI"
               throw "Format: Kanji/Hanzi not supported in this build (spec 8.7)"
            default
               throw "Format: unhandled mode " & tMode
         end switch
      end repeat
   catch e
      put e into tErr
   end try
   if tErr is not empty then
      -- keep the tagged contract: an untagged throw (a BitSource exhaustion,
      -- for instance) is a Format error in ZXing's terms
      if not ((tErr begins with "Format") or (tErr begins with "NotFound") or (tErr begins with "Checksum")) then
         put "Format: " & tErr into tErr
      end if
      put empty into tResult
      put tErr into tResult["error"]
      return tResult
   end if

   put tText into tResult["text"]
   put tRaw into tResult["bytes"]
   put empty into tResult["error"]
   if tUsedCharset is not empty then put tUsedCharset into tResult["charset"]
   if tFnc1Kind is not empty then put tFnc1Kind into tResult["fnc1"]
   if tHasSa then
      put tSaSeq into tResult["structuredAppendSeq"]
      put tSaParity into tResult["structuredAppendParity"]
   end if
   -- ZXing's symbology modifier: 1 plain, 3 FNC1 first, 5 FNC1 second; +1 with an ECI
   if tFnc1Kind is "first" then
      put 3 into tResult["symbologyModifier"]
   else if tFnc1Kind is "second" then
      put 5 into tResult["symbologyModifier"]
   else
      put 1 into tResult["symbologyModifier"]
   end if
   if tHasEci then add 1 to tResult["symbologyModifier"]
   return tResult
end dbsp_decode

-- NUMERIC: groups of 3 digits (10 bits), then 2 (7) or 1 (4). Returns text.
function dbsp_decodeNumeric pVersion
   local tCount, tOut, threeDigits, twoDigits, oneDigit
   put dbsp_read(mode_charCountBits("NUMERIC", pVersion)) into tCount
   put empty into tOut
   repeat while tCount >= 3
      put dbsp_read(10) into threeDigits
      if threeDigits >= 1000 then throw "Format: numeric group > 999"
      put char ((threeDigits div 100) + 1) of kDigits after tOut
      put char (((threeDigits div 10) mod 10) + 1) of kDigits after tOut
      put char ((threeDigits mod 10) + 1) of kDigits after tOut
      subtract 3 from tCount
   end repeat
   if tCount = 2 then
      put dbsp_read(7) into twoDigits
      if twoDigits >= 100 then throw "Format: numeric pair > 99"
      put char ((twoDigits div 10) + 1) of kDigits after tOut
      put char ((twoDigits mod 10) + 1) of kDigits after tOut
   else if tCount = 1 then
      put dbsp_read(4) into oneDigit
      if oneDigit >= 10 then throw "Format: numeric single > 9"
      put char (oneDigit + 1) of kDigits after tOut
   end if
   return tOut
end dbsp_decodeNumeric

-- one alphanumeric character by index; ZXing toAlphaNumericChar throws for >= 45
-- (an 11-bit pair value 2025..2047 or a 6-bit tail 45..63 is corrupt data)
function dbsp_alnumChar pIdx
   if pIdx >= 45 then throw "Format: alphanumeric index " & pIdx & " out of range"
   return char (pIdx + 1) of kAlphanumChars
end dbsp_alnumChar

-- ALPHANUMERIC: pairs (11 bits -> v/45, v%45), trailing single (6 bits).
-- In FNC1 mode (pFc1) ZXing rewrites the segment: "%%" -> "%", lone "%" -> GS.
function dbsp_decodeAlphanumeric pVersion, pFc1
   local tCount, tOut, v, tRes, i, n, c
   put dbsp_read(mode_charCountBits("ALPHANUMERIC", pVersion)) into tCount
   put empty into tOut
   repeat while tCount >= 2
      put dbsp_read(11) into v
      put dbsp_alnumChar(v div 45) after tOut
      put dbsp_alnumChar(v mod 45) after tOut
      subtract 2 from tCount
   end repeat
   if tCount = 1 then
      put dbsp_read(6) into v
      put dbsp_alnumChar(v) after tOut
   end if
   if pFc1 is not true then return tOut
   put empty into tRes
   put the number of chars of tOut into n
   put 1 into i
   repeat while i <= n
      put char i of tOut into c
      if c = "%" then
         if (i < n) and (char (i + 1) of tOut = "%") then
            put "%" after tRes
            add 2 to i
         else
            put numToCodepoint(kGroupSeparator) after tRes
            add 1 to i
         end if
      else
         put c after tRes
         add 1 to i
      end if
   end repeat
   return tRes
end dbsp_decodeAlphanumeric

-- BYTE: `count` bytes; decode via the ECI charset, or guess when there is
-- none. Returns {text, bytes, charset}.
function dbsp_decodeByte pVersion, pCharset
   local tCount, i, b, tBytes, tRes, cs
   put dbsp_read(mode_charCountBits("BYTE", pVersion)) into tCount
   if bitSource_available(sSrc) < (8 * tCount) then
      throw "Format: byte segment of " & tCount & " bytes exceeds the data"
   end if
   put empty into tBytes
   repeat with i = 1 to tCount
      put dbsp_read(8) into b
      put numToByte(b) after tBytes
   end repeat
   if pCharset is empty then
      put dbsp_guessCharset(tBytes) into cs
   else
      put pCharset into cs
   end if
   put tBytes into tRes["bytes"]
   put cs into tRes["charset"]
   put dbsp_decodeBytes(tBytes, cs) into tRes["text"]
   return tRes
end dbsp_decodeByte

-- turn a raw byte string into text using the charsets this build can decode.
-- ISO-8859-1 / ASCII / anything else: direct byte->codepoint (lossless, and the
-- raw bytes are also in ["bytes"]).
function dbsp_decodeBytes pBytes, pCharset
   local cs
   put toUpper(pCharset) into cs
   if (cs = "UTF-8") or (cs = "UTF8") then
      return dbsp_utf8ToText(pBytes)
   end if
   if (cs = "UTF-16") or (cs = "UTF-16BE") or (cs = "UTF16") then
      return dbsp_utf16ToText(pBytes, false)
   end if
   if cs = "UTF-16LE" then
      return dbsp_utf16ToText(pBytes, true)
   end if
   return dbsp_latin1ToText(pBytes)
end dbsp_decodeBytes

-- ZXing StringUtils.guessCharset for a platform without Shift_JIS (ZXing
-- itself sets canBeShiftJIS = false when that charset is unavailable):
--   * UTF-16 when the bytes start with a UTF-16 byte-order mark;
--   * UTF-8 when the bytes are structurally valid UTF-8 (lead/continuation
--     bytes, no truncated sequence) AND carry a UTF-8 BOM or at least one
--     multi-byte character;
--   * otherwise ISO-8859-1 when no byte lies in the undefined 0x80..0x9F range;
--   * otherwise UTF-8 if it was valid, else ISO-8859-1 (the lossless choice
--     where ZXing would use the platform default).
function dbsp_guessCharset pBytes
   local n, i, v, tCanUtf8, tCanIso, tLeft, tMulti, tBom, b1, b2
   put the number of bytes of pBytes into n
   if n > 2 then
      put byteToNum(byte 1 of pBytes) into b1
      put byteToNum(byte 2 of pBytes) into b2
      if ((b1 = 254) and (b2 = 255)) or ((b1 = 255) and (b2 = 254)) then return "UTF-16"
   end if
   put false into tBom
   if n > 3 then
      if (byteToNum(byte 1 of pBytes) = 239) and (byteToNum(byte 2 of pBytes) = 187)             and (byteToNum(byte 3 of pBytes) = 191) then
         put true into tBom
      end if
   end if
   put true into tCanUtf8
   put true into tCanIso
   put 0 into tLeft
   put 0 into tMulti
   put 1 into i
   repeat while (i <= n) and (tCanUtf8 or tCanIso)
      put byteToNum(byte i of pBytes) into v
      if tCanUtf8 then
         if tLeft > 0 then
            if (v bitAnd 128) = 0 then
               put false into tCanUtf8
            else
               subtract 1 from tLeft
            end if
         else if (v bitAnd 128) <> 0 then
            if (v bitAnd 64) = 0 then
               put false into tCanUtf8            -- a stray continuation byte
            else
               add 1 to tLeft
               if (v bitAnd 32) <> 0 then
                  add 1 to tLeft
                  if (v bitAnd 16) <> 0 then
                     add 1 to tLeft
                     if (v bitAnd 8) <> 0 then put false into tCanUtf8
                  end if
               end if
               add 1 to tMulti
            end if
         end if
      end if
      if tCanIso then
         if (v > 127) and (v < 160) then put false into tCanIso
      end if
      add 1 to i
   end repeat
   if tLeft > 0 then put false into tCanUtf8      -- truncated final sequence
   if tCanUtf8 and (tBom or (tMulti > 0)) then return "UTF-8"
   if tCanIso then return "ISO-8859-1"
   if tCanUtf8 then return "UTF-8"
   return "ISO-8859-1"
end dbsp_guessCharset

-- ISO-8859-1: every byte maps directly to the codepoint of the same value
-- (Unicode's first 256 codepoints ARE Latin-1). numToCodepoint is a core string
-- function, available in a script-only stack whatever the text-encoding state.
function dbsp_latin1ToText pBytes
   local tTxt, i, n
   put the number of bytes of pBytes into n
   put empty into tTxt
   repeat with i = 1 to n
      put numToCodepoint(byteToNum(byte i of pBytes)) after tTxt
   end repeat
   return tTxt
end dbsp_latin1ToText

-- Minimal UTF-8 decoder (1-4 byte sequences, RFC 3629 ranges) -> text.
-- Malformed bytes degrade to their Latin-1 interpretation one byte at a time
-- rather than throwing, so a slightly-off payload still yields readable text.
-- Overlong forms (E0 80..9F, F0 80..8F), UTF-16 surrogates (ED A0..BF) and
-- code points above U+10FFFF (F4 90..BF) are malformed and treated the same.
function dbsp_utf8ToText pBytes
   local tTxt, i, n, b1, b2, b3, b4, cp, tOk
   put the number of bytes of pBytes into n
   put empty into tTxt
   put 1 into i
   repeat while i <= n
      put byteToNum(byte i of pBytes) into b1
      put false into tOk
      if b1 < 128 then
         put numToCodepoint(b1) after tTxt
         add 1 to i
         next repeat
      end if
      if (b1 >= 194) and (b1 <= 223) and (i + 1 <= n) then
         put byteToNum(byte (i + 1) of pBytes) into b2
         if (b2 >= 128) and (b2 <= 191) then
            put (((b1 - 192) * 64) + (b2 - 128)) into cp
            put numToCodepoint(cp) after tTxt
            add 2 to i
            put true into tOk
         end if
      else if (b1 >= 224) and (b1 <= 239) and (i + 2 <= n) then
         put byteToNum(byte (i + 1) of pBytes) into b2
         put byteToNum(byte (i + 2) of pBytes) into b3
         if (b2 >= 128) and (b2 <= 191) and (b3 >= 128) and (b3 <= 191) then
            put true into tOk
            if (b1 = 224) and (b2 < 160) then put false into tOk    -- overlong
            if (b1 = 237) and (b2 > 159) then put false into tOk    -- surrogate
         end if
         if tOk then
            put (((b1 - 224) * 4096) + ((b2 - 128) * 64) + (b3 - 128)) into cp
            put numToCodepoint(cp) after tTxt
            add 3 to i
         end if
      else if (b1 >= 240) and (b1 <= 244) and (i + 3 <= n) then
         put byteToNum(byte (i + 1) of pBytes) into b2
         put byteToNum(byte (i + 2) of pBytes) into b3
         put byteToNum(byte (i + 3) of pBytes) into b4
         if (b2 >= 128) and (b2 <= 191) and (b3 >= 128) and (b3 <= 191)                and (b4 >= 128) and (b4 <= 191) then
            put true into tOk
            if (b1 = 240) and (b2 < 144) then put false into tOk    -- overlong
            if (b1 = 244) and (b2 > 143) then put false into tOk    -- > U+10FFFF
         end if
         if tOk then
            put (((b1 - 240) * 262144) + ((b2 - 128) * 4096)                + ((b3 - 128) * 64) + (b4 - 128)) into cp
            put numToCodepoint(cp) after tTxt
            add 4 to i
         end if
      end if
      if not tOk then
         -- continuation byte out of place, truncated or malformed sequence: Latin-1 it
         put numToCodepoint(b1) after tTxt
         add 1 to i
      end if
   end repeat
   return tTxt
end dbsp_utf8ToText

-- Minimal UTF-16 decoder with surrogate pairs. A byte-order mark decides the
-- byte order (and is dropped); without one, big-endian unless pLittleEndian.
-- A lone surrogate or an odd trailing byte becomes U+FFFD, as Java would emit.
function dbsp_utf16ToText pBytes, pLittleEndian
   local tTxt, i, n, b1, b2, cu, cu2, tLE
   put the number of bytes of pBytes into n
   put (pLittleEndian is true) into tLE
   put 1 into i
   if n >= 2 then
      put byteToNum(byte 1 of pBytes) into b1
      put byteToNum(byte 2 of pBytes) into b2
      if (b1 = 254) and (b2 = 255) then
         put false into tLE
         put 3 into i
      else if (b1 = 255) and (b2 = 254) then
         put true into tLE
         put 3 into i
      end if
   end if
   put empty into tTxt
   repeat while (i + 1) <= n
      put byteToNum(byte i of pBytes) into b1
      put byteToNum(byte (i + 1) of pBytes) into b2
      if tLE then
         put ((b2 * 256) + b1) into cu
      else
         put ((b1 * 256) + b2) into cu
      end if
      add 2 to i
      if (cu >= 55296) and (cu <= 56319) then          -- high surrogate D800..DBFF
         put 65533 into cu2
         if (i + 1) <= n then
            put byteToNum(byte i of pBytes) into b1
            put byteToNum(byte (i + 1) of pBytes) into b2
            if tLE then
               put ((b2 * 256) + b1) into cu2
            else
               put ((b1 * 256) + b2) into cu2
            end if
         end if
         if (cu2 >= 56320) and (cu2 <= 57343) then     -- low surrogate DC00..DFFF
            put (65536 + ((cu - 55296) * 1024) + (cu2 - 56320)) into cu
            add 2 to i
         else
            put 65533 into cu
         end if
      else if (cu >= 56320) and (cu <= 57343) then
         put 65533 into cu                               -- lone low surrogate
      end if
      put numToCodepoint(cu) after tTxt
   end repeat
   if i <= n then put numToCodepoint(65533) after tTxt   -- odd trailing byte
   return tTxt
end dbsp_utf16ToText

-- ECI: parse the 1/2/3-byte ECI designator and map to a charset name. An
-- unknown value is a Format error (ZXing CharacterSetECI.getCharacterSetECIByValue).
function dbsp_parseEci
   local firstByte, eciValue, tSecond, tThird, tName
   put dbsp_read(8) into firstByte
   if (firstByte bitAnd 128) = 0 then
      put (firstByte bitAnd 127) into eciValue
   else if (firstByte bitAnd 192) = 128 then
      put dbsp_read(8) into tSecond
      put (((firstByte bitAnd 63) * 256) bitOr tSecond) into eciValue
   else if (firstByte bitAnd 224) = 192 then
      put dbsp_read(16) into tThird
      put (((firstByte bitAnd 31) * 65536) bitOr tThird) into eciValue
   else
      throw "Format: bad ECI designator"
   end if
   put eci_charsetName(eciValue) into tName
   if tName is empty then throw "Format: unknown ECI value " & eciValue
   return tName
end dbsp_parseEci

-- ===================== module: bitMatrixParser =========
-- =====================================================================
-- bitMatrixParser.lc - read format/version/codewords from a sampled matrix.
-- Port of ZXing Qrcode\Decoder\BitMatrixParser. Spec section 8.5.
-- Requires: qrCompat.lc, bitMatrix.lc, version.lc, formatInformation.lc,
--           errorCorrectionLevel.lc.
--
-- A parser instance is an array:
--   p["bits"]       the sampled square BitMatrix (true = black/1)
--   p["dimension"]  width == height (== 17 + 4*version)
--   p["mirror"]     boolean; when true, get(x,y) is read transposed
--   p["fmt"]        cached {ecLevel,dataMask} once read
--   p["version"]    cached version number once read
--
-- Reading conventions match ZXing: bit (i,j) with i = row (y), j = column (x).
-- =====================================================================

function bmp_new pBits
   local p, tDim
   put bitMatrix_getHeight(pBits) into tDim
   if (tDim < 21) or (tDim > 177) or ((tDim bitAnd 3) <> 1) then
      throw "Format: dimension " & tDim & " is not 4k+1 in 21..177"
   end if
   put pBits into p["bits"]
   put tDim into p["dimension"]
   put false into p["mirror"]
   return p
end bmp_new

-- module accessor honouring the mirror flag (transpose when mirrored)
function bmp_get pParser, x, y
   if pParser["mirror"] then
      return bitMatrix_get(pParser["bits"], y, x)
   end if
   return bitMatrix_get(pParser["bits"], x, y)
end bmp_get

command bmp_setMirror @pParser, pMirror
   put pMirror into pParser["mirror"]
end bmp_setMirror

-- copy a bit from (fromX,fromY) ... helper for readCodewords masking removed;
-- the actual data-mask is applied later by the decoder via dataMask_unmask.

-- read the 15-bit format information (two copies) -> {ecLevel,dataMask}.
function bmp_readFormatInformation pParser
   local tDim, fmtInfo1, fmtInfo2, i, j, tRes
   put pParser["dimension"] into tDim

   -- copy 1: top-left.  bits along row 8 (cols 0..5, then 7,8) and
   -- col 8 (rows 7,5,4,3,2,1,0)  -- ZXing order builds MSB-first.
   put 0 into fmtInfo1
   repeat with i = 0 to 5
      put bmp_copyBit(pParser, i, 8, fmtInfo1) into fmtInfo1
   end repeat
   put bmp_copyBit(pParser, 7, 8, fmtInfo1) into fmtInfo1
   put bmp_copyBit(pParser, 8, 8, fmtInfo1) into fmtInfo1
   put bmp_copyBit(pParser, 8, 7, fmtInfo1) into fmtInfo1
   repeat with j = 5 down to 0
      put bmp_copyBit(pParser, 8, j, fmtInfo1) into fmtInfo1
   end repeat

   -- copy 2: split around the other two finders.
   put 0 into fmtInfo2
   repeat with i = tDim - 1 down to tDim - 7
      put bmp_copyBit(pParser, 8, i, fmtInfo2) into fmtInfo2
   end repeat
   repeat with j = tDim - 8 to tDim - 1
      put bmp_copyBit(pParser, j, 8, fmtInfo2) into fmtInfo2
   end repeat

   put fmt_decode(fmtInfo1, fmtInfo2) into tRes
   if tRes is empty then throw "Format: could not decode format information"
   return tRes
end bmp_readFormatInformation

-- shift one module bit into an accumulator: acc = (acc<<1) | bit(x,y)
function bmp_copyBit pParser, x, y, pAcc
   local b
   if bmp_get(pParser, x, y) then
      put 1 into b
   else
      put 0 into b
   end if
   return ((pAcc * 2) bitOr b)
end bmp_copyBit

-- version: derive from dimension for v1-6; read the two version blocks for v7+.
function bmp_readVersion pParser
   local tDim, provVer, versionBits, i, j, tVer
   put pParser["dimension"] into tDim
   put ((tDim - 17) div 4) into provVer
   if provVer <= 6 then
      return provVer
   end if
   -- v7+: read the two 18-bit version-info blocks. ZXing reads the TOP-RIGHT
   -- block first (x = dim-9..dim-11, y = 5..0), then the bottom-left copy, and
   -- accepts a decoded version only if its dimension is the sampled dimension -
   -- a damaged block that decodes (within 3 bits) to ANOTHER version would
   -- otherwise drive the unmask/function-pattern/codeword steps with the wrong
   -- geometry (ZXing BitMatrixParser.readVersion).
   put 0 into versionBits
   repeat with j = 5 down to 0
      repeat with i = tDim - 9 down to tDim - 11
         put bmp_copyBit(pParser, i, j, versionBits) into versionBits
      end repeat
   end repeat
   put ver_decodeVersionInformation(versionBits) into tVer
   if (tVer is not empty) and (ver_getDimensionForVersion(tVer) = tDim) then return tVer
   -- second copy (bottom-left: x = 5..0, y = dim-9..dim-11)
   put 0 into versionBits
   repeat with i = 5 down to 0
      repeat with j = tDim - 9 down to tDim - 11
         put bmp_copyBit(pParser, i, j, versionBits) into versionBits
      end repeat
   end repeat
   put ver_decodeVersionInformation(versionBits) into tVer
   if (tVer is not empty) and (ver_getDimensionForVersion(tVer) = tDim) then return tVer
   throw "Format: could not read version"
end bmp_readVersion

-- build the function-pattern mask for a version: a BitMatrix where true = a
-- module that is NOT data (finders, separators, timing, alignment, format,
-- version, dark module). Codeword reading skips these.
function bmp_buildFunctionPattern pVersion
   local tDim, fp, i, tCenters, tAlignC, tAlignR, n, r, c
   put ver_getDimensionForVersion(pVersion) into tDim
   put bitMatrix_new(tDim) into fp

   -- top-left, top-right, bottom-left finder + separator (8x8 reserved)
   bitMatrix_setRegion fp, 0, 0, 9, 9
   bitMatrix_setRegion fp, tDim - 8, 0, 8, 9
   bitMatrix_setRegion fp, 0, tDim - 8, 9, 8

   -- timing patterns (row 6 and col 6), interior span
   bitMatrix_setRegion fp, 9, 6, tDim - 17, 1
   bitMatrix_setRegion fp, 6, 9, 1, tDim - 17

   -- alignment patterns (v2+): 5x5 at each centre pair, except those that
   -- overlap the finders.
   put ver_getAlignmentCenters(pVersion) into tCenters
   if tCenters is not empty then
      set the itemDelimiter to comma
      put the number of items of tCenters into n
      repeat with r = 1 to n
         repeat with c = 1 to n
            put (item r of tCenters) into tAlignR
            put (item c of tCenters) into tAlignC
            -- skip the three that coincide with finder patterns
            if ((tAlignC = 6) and (tAlignR = 6)) then next repeat
            if ((tAlignC = 6) and (tAlignR = (item n of tCenters))) then next repeat
            if ((tAlignC = (item n of tCenters)) and (tAlignR = 6)) then next repeat
            bitMatrix_setRegion fp, tAlignC - 2, tAlignR - 2, 5, 5
         end repeat
      end repeat
   end if

   -- version info blocks (v7+)
   if pVersion >= 7 then
      bitMatrix_setRegion fp, tDim - 11, 0, 3, 6
      bitMatrix_setRegion fp, 0, tDim - 11, 6, 3
   end if

   return fp
end bmp_buildFunctionPattern

-- read all data codewords in the standard zig-zag, skipping function modules.
-- Returns a dense 0-based array of byte values. (The data mask is NOT applied
-- here; the decoder applies it to the matrix first, matching ZXing's flow when
-- it uses readCodewords after unmasking - see decoder.lc.)
function bmp_readCodewords pParser, pVersion
   local fp, tDim, tRes, idx, bitsRead, currentByte
   local col, row, readingUp, c, i
   put bmp_buildFunctionPattern(pVersion) into fp
   put pParser["dimension"] into tDim
   put 0 into idx                 -- codeword index
   put 0 into bitsRead
   put 0 into currentByte
   put true into readingUp
   put (tDim - 1) into col
   repeat while col > 0
      if col = 6 then subtract 1 from col      -- skip the timing column
      repeat with i = 0 to (tDim - 1)
         if readingUp then
            put (tDim - 1 - i) into row
         else
            put i into row
         end if
         repeat with c = 0 to 1
            if not bitMatrix_get(fp, (col - c), row) then
               add 1 to bitsRead
               put (currentByte * 2) into currentByte
               if bmp_get(pParser, (col - c), row) then
                  add 1 to currentByte
               end if
               if bitsRead = 8 then
                  put currentByte into tRes[idx]
                  add 1 to idx
                  put 0 into bitsRead
                  put 0 into currentByte
               end if
            end if
         end repeat
      end repeat
      put not readingUp into readingUp
      subtract 2 from col
   end repeat
   -- ZXing/PHP: the zig-zag must yield exactly the version's codeword total
   if idx <> ver_getTotalCodewords(pVersion) then
      throw "Format: read " & idx & " codewords, expected " & ver_getTotalCodewords(pVersion)
   end if
   return tRes
end bmp_readCodewords

-- ===================== module: decoder =================
-- =====================================================================
-- decoder.lc - orchestrate matrix parse -> RS -> bitstream. Spec section 8.5.
-- Port of ZXing Qrcode\Decoder\Decoder. Requires: qrCompat.lc, bitMatrix.lc,
--   bitMatrixParser.lc, version.lc, formatInformation.lc, dataMask.lc,
--   dataBlock.lc, reedSolomonDecoder.lc, decodedBitStreamParser.lc,
--   errorCorrectionLevel.lc.
--
-- dec_decode(bits) -> result array from decodedBitStreamParser:
--   ["text"], ["bytes"], ["error"], plus ["ecLevel"], ["version"], ["mask"],
--   and ["mirrored"] = true when the symbol only decoded transposed.
-- On any NotFound/Format/Checksum the result has ["error"] set and empty text.
--
-- Flow (dec_tryParser):
--   1. read format info -> ecLevel, dataMask
--   2. read version
--   3. un-mask a COPY of the matrix with the chosen data mask
--   4. read raw codewords (zig-zag, skipping function modules)
--   5. de-interleave into RS blocks; correct each block; concatenate data
--   6. DecodedBitStreamParser.decode
-- The mirrored-symbol retry wraps this (ZXing Decoder.decode): on failure the
-- format information and version are re-read TRANSPOSED; the matrix is then
-- physically transposed (bitMatrix_transposed) before un-masking and reading
-- the codewords, because the data mask is defined in the symbol's own frame.
-- (Until 2026-09 the port un-masked the untransposed copy and then read it
-- transposed, so every mirrored symbol failed Reed-Solomon; found by the
-- synthetic-fixture corpus and confirmed against ZXing.)
--
-- ERROR TAGS: the public contract is "NotFound: / Format: / Checksum:". A
-- Reed-Solomon failure ("RS: ...") becomes "Checksum: RS: ..." here (ZXing maps
-- ReedSolomonException to ChecksumException); any untagged internal error is
-- reported as "Format: ...".
-- =====================================================================

function dec_decode pBits
   local parser, tRes, tFirst
   put bmp_new(pBits) into parser
   -- first attempt
   put dec_tryParser(parser) into tRes
   if tRes["error"] is empty then
      return tRes
   end if
   put tRes into tFirst
   -- mirror retry: re-read everything transposed
   bmp_setMirror parser, true
   put dec_tryParser(parser) into tRes
   if tRes["error"] is empty then
      put true into tRes["mirrored"]
      return tRes
   end if
   return tFirst          -- ZXing reports the ORIGINAL reading's error
end dec_decode

-- one decode attempt; returns the bitstream result (with error set on failure).
function dec_tryParser pParser
   local tFmt, tEcLevel, tMask, tVersion, tBits, tCodewords, tCwErr
   local tBlocks, tNum, b, tCorrected, i, tData, tDataIdx, tSaved, tSavedMirror
   local tResult, tErr, e, e2, tEcw

   put empty into tErr
   try
      -- format information and version are read through bmp_get, which honours
      -- the parser's mirror flag (ZXing reads both "preemptively" when mirrored)
      put bmp_readFormatInformation(pParser) into tFmt
      put tFmt["ecLevel"] into tEcLevel
      put tFmt["dataMask"] into tMask
      put bmp_readVersion(pParser) into tVersion

      -- Work on a COPY of the matrix so the parser's own matrix stays intact for
      -- the retry. A mirrored reading transposes the copy FIRST (ZXing
      -- BitMatrixParser.mirror), then un-masks and reads codewords in that frame.
      put pParser["bits"] into tBits
      if pParser["mirror"] is true then
         put bitMatrix_transposed(tBits) into tBits
      end if
      dataMask_unmask tBits, pParser["dimension"], tMask
      put pParser["bits"] into tSaved
      put pParser["mirror"] into tSavedMirror
      put tBits into pParser["bits"]
      put false into pParser["mirror"]           -- the copy is already in the right frame
      put empty into tCwErr
      try
         put bmp_readCodewords(pParser, tVersion) into tCodewords
      catch e2
         put e2 into tCwErr
      end try
      put tSaved into pParser["bits"]            -- restore on every path
      put tSavedMirror into pParser["mirror"]
      if tCwErr is not empty then throw tCwErr

      -- de-interleave + per-block Reed-Solomon correction
      put db_getDataBlocks(tCodewords, tVersion, tEcLevel) into tBlocks
      put tBlocks["n"] into tNum
      put ver_getEcCodewordsPerBlock(tVersion, tEcLevel) into tEcw
      put 0 into tDataIdx             -- concatenated corrected data codewords
      repeat with b = 0 to (tNum - 1)
         put dec_correctBlock(tBlocks[b], tEcw) into tCorrected
         repeat with i = 0 to (tBlocks[b]["numData"] - 1)
            put tCorrected[i] into tData[tDataIdx]
            add 1 to tDataIdx
         end repeat
      end repeat

      -- bits -> text
      put dbsp_decode(tData, tVersion, tEcLevel) into tResult
      if tResult["error"] is not empty then
         return tResult
      end if
      put ecl_name(tEcLevel) into tResult["ecLevel"]
      put tVersion into tResult["version"]
      put tMask into tResult["mask"]
      return tResult
   catch e
      put e into tErr
   end try
   -- the tagged contract: an internal invariant ("BitMatrix: ...") surfacing
   -- here is a Format error in ZXing's terms
   if not ((tErr begins with "NotFound") or (tErr begins with "Format") or (tErr begins with "Checksum")) then
      put "Format: " & tErr into tErr
   end if
   put empty into tResult
   put tErr into tResult["error"]
   return tResult
end dec_tryParser

-- correct one block's codewords with Reed-Solomon; returns the corrected
-- data codewords (0-based, length numData). An uncorrectable block is a
-- Checksum error (ZXing Decoder.correctErrors wraps ReedSolomonException).
function dec_correctBlock pBlock, pEcwPerBlock
   local tLen, tCw, i, tOut, e, tErr
   put pBlock["len"] into tLen
   -- build a dense 0-based array of all codewords (data + ec) for rs_decode
   repeat with i = 0 to (tLen - 1)
      put pBlock["cw"][i] into tCw[i]
   end repeat
   put empty into tErr
   try
      rs_decode tCw, pEcwPerBlock          -- corrects in place; throws "RS: ..." on failure
   catch e
      put e into tErr
   end try
   if tErr is not empty then throw "Checksum: " & tErr    -- after the try (engine notes 3.2)
   repeat with i = 0 to (pBlock["numData"] - 1)
      put tCw[i] into tOut[i]
   end repeat
   return tOut
end dec_correctBlock

-- ===================== module: mathUtils ===============
-- =====================================================================
-- mathUtils.lc - rounding + distance helpers. Spec section 8.4.
-- Port of ZXing Common\Detector\MathUtils. Requires: nothing (builtins only).
--
-- PHP authority:
--   round(d)        = (int)(d + (d < 0 ? -0.5 : 0.5))   -- x.5 rounds away from 0
--   distance(...)   = sqrt(dx*dx + dy*dy)
-- (int) in PHP truncates toward zero; xTalk trunc() does the same, so
-- mu_round matches bit-for-bit for the non-negative values used on the QR path.
-- =====================================================================

-- nearest integer; x.5 rounds away from zero (matches MathUtils::round)
function mu_round pRoundArg
   if pRoundArg < 0 then
      return trunc(pRoundArg - 0.5)
   end if
   return trunc(pRoundArg + 0.5)
end mu_round

-- Euclidean distance between (pAX,pAY) and (pBX,pBY)
function mu_distance pAX, pAY, pBX, pBY
   local tDX, tDY
   put (pAX - pBX) into tDX
   put (pAY - pBY) into tDY
   return sqrt((tDX * tDX) + (tDY * tDY))
end mu_distance

-- ===================== module: resultPoint =============
-- =====================================================================
-- resultPoint.lc - 2-D point + the orderBestPatterns ordering. Spec section 8.4.
-- Port of ZXing ResultPoint. Requires: mathUtils.lc.
--
-- A point (Pattern A) is an array: pPt["x"], pPt["y"]. FinderPattern and
-- AlignmentPattern are "subclasses": same x/y plus ["ms"] (estimatedModuleSize)
-- and (finder) ["ct"] (count). Ordering only needs x/y.
--
-- orderBestPatterns takes a 0-based array of three points {0,1,2} and returns
-- a new 0-based array [A,B,C] such that AB<AC and BC<AC and the angle between
-- BC and BA is < 180 deg (ZXing's TL/TR/BL convention; downstream depends on it).
-- =====================================================================

function rp_new pPtX, pPtY
   local tPt
   put pPtX into tPt["x"]
   put pPtY into tPt["y"]
   return tPt
end rp_new

-- distance between two points (delegates to MathUtils)
function rp_distance pP1, pP2
   return mu_distance(pP1["x"], pP1["y"], pP2["x"], pP2["y"])
end rp_distance

-- z component of the cross product of vectors BC and BA
function rp_crossProductZ pPtA, pPtB, pPtC
   local tBX, tBY
   put pPtB["x"] into tBX
   put pPtB["y"] into tBY
   return (((pPtC["x"] - tBX) * (pPtA["y"] - tBY)) - ((pPtC["y"] - tBY) * (pPtA["x"] - tBX)))
end rp_crossProductZ

function rp_orderBestPatterns pPatterns
   local tZeroOne, tOneTwo, tZeroTwo, tPtA, tPtB, tPtC, tTemp, tOut
   put rp_distance(pPatterns[0], pPatterns[1]) into tZeroOne
   put rp_distance(pPatterns[1], pPatterns[2]) into tOneTwo
   put rp_distance(pPatterns[0], pPatterns[2]) into tZeroTwo
   -- the point closest to the other two is B; A and C are first guesses
   if (tOneTwo >= tZeroOne) and (tOneTwo >= tZeroTwo) then
      put pPatterns[0] into tPtB
      put pPatterns[1] into tPtA
      put pPatterns[2] into tPtC
   else if (tZeroTwo >= tOneTwo) and (tZeroTwo >= tZeroOne) then
      put pPatterns[1] into tPtB
      put pPatterns[0] into tPtA
      put pPatterns[2] into tPtC
   else
      put pPatterns[2] into tPtB
      put pPatterns[0] into tPtA
      put pPatterns[1] into tPtC
   end if
   -- if BC x BA has negative z, A and C are flipped; swap them
   if rp_crossProductZ(tPtA, tPtB, tPtC) < 0 then
      put tPtA into tTemp
      put tPtC into tPtA
      put tTemp into tPtC
   end if
   put tPtA into tOut[0]
   put tPtB into tOut[1]
   put tPtC into tOut[2]
   return tOut
end rp_orderBestPatterns

-- ===================== module: perspectiveTransform ====
-- =====================================================================
-- perspectiveTransform.lc - 3x3 projective transform. Spec section 8.4.
-- Port of ZXing Common\PerspectiveTransform. Requires: nothing (pure float).
--
-- A transform (Pattern A) is an array of nine coefficients:
--   tT["a11"] tT["a21"] tT["a31"]
--   tT["a12"] tT["a22"] tT["a32"]
--   tT["a13"] tT["a23"] tT["a33"]
-- matching ZXing's field layout. transformPoints maps (x,y) ->
--   denom = a13*x + a23*y + a33
--   x' = (a11*x + a21*y + a31)/denom ;  y' = (a12*x + a22*y + a32)/denom
--
-- All float math -- no integer-semantics traps (spec section 6 does not apply here).
-- =====================================================================

function pt_squareToQuadrilateral pX0, pY0, pX1, pY1, pX2, pY2, pX3, pY3
   local tDx3, tDy3, tDx1, tDx2, tDy1, tDy2, tDenom, tA13, tA23, tXform
   put (pX0 - pX1 + pX2 - pX3) into tDx3
   put (pY0 - pY1 + pY2 - pY3) into tDy3
   if (tDx3 = 0) and (tDy3 = 0) then
      -- affine
      put (pX1 - pX0) into tXform["a11"]
      put (pX2 - pX1) into tXform["a21"]
      put pX0 into tXform["a31"]
      put (pY1 - pY0) into tXform["a12"]
      put (pY2 - pY1) into tXform["a22"]
      put pY0 into tXform["a32"]
      put 0 into tXform["a13"]
      put 0 into tXform["a23"]
      put 1 into tXform["a33"]
      return tXform
   end if
   put (pX1 - pX2) into tDx1
   put (pX3 - pX2) into tDx2
   put (pY1 - pY2) into tDy1
   put (pY3 - pY2) into tDy2
   put ((tDx1 * tDy2) - (tDx2 * tDy1)) into tDenom
   put (((tDx3 * tDy2) - (tDx2 * tDy3)) / tDenom) into tA13
   put (((tDx1 * tDy3) - (tDx3 * tDy1)) / tDenom) into tA23
   put (pX1 - pX0 + (tA13 * pX1)) into tXform["a11"]
   put (pX3 - pX0 + (tA23 * pX3)) into tXform["a21"]
   put pX0 into tXform["a31"]
   put (pY1 - pY0 + (tA13 * pY1)) into tXform["a12"]
   put (pY3 - pY0 + (tA23 * pY3)) into tXform["a22"]
   put pY0 into tXform["a32"]
   put tA13 into tXform["a13"]
   put tA23 into tXform["a23"]
   put 1 into tXform["a33"]
   return tXform
end pt_squareToQuadrilateral

-- adjoint (= transpose of the cofactor matrix); serves as the inverse here
function pt_buildAdjoint pXform
   local tPtA
   put ((pXform["a22"] * pXform["a33"]) - (pXform["a23"] * pXform["a32"])) into tPtA["a11"]
   put ((pXform["a23"] * pXform["a31"]) - (pXform["a21"] * pXform["a33"])) into tPtA["a21"]
   put ((pXform["a21"] * pXform["a32"]) - (pXform["a22"] * pXform["a31"])) into tPtA["a31"]
   put ((pXform["a13"] * pXform["a32"]) - (pXform["a12"] * pXform["a33"])) into tPtA["a12"]
   put ((pXform["a11"] * pXform["a33"]) - (pXform["a13"] * pXform["a31"])) into tPtA["a22"]
   put ((pXform["a12"] * pXform["a31"]) - (pXform["a11"] * pXform["a32"])) into tPtA["a32"]
   put ((pXform["a12"] * pXform["a23"]) - (pXform["a13"] * pXform["a22"])) into tPtA["a13"]
   put ((pXform["a13"] * pXform["a21"]) - (pXform["a11"] * pXform["a23"])) into tPtA["a23"]
   put ((pXform["a11"] * pXform["a22"]) - (pXform["a12"] * pXform["a21"])) into tPtA["a33"]
   return tPtA
end pt_buildAdjoint

function pt_quadrilateralToSquare pX0, pY0, pX1, pY1, pX2, pY2, pX3, pY3
   return pt_buildAdjoint(pt_squareToQuadrilateral(pX0, pY0, pX1, pY1, pX2, pY2, pX3, pY3))
end pt_quadrilateralToSquare

-- matrix product (this = pA, other = pB) matching ZXing's times()
function pt_times pPtA, pPtB
   local tXform
   put ((pPtA["a11"] * pPtB["a11"]) + (pPtA["a21"] * pPtB["a12"]) + (pPtA["a31"] * pPtB["a13"])) into tXform["a11"]
   put ((pPtA["a11"] * pPtB["a21"]) + (pPtA["a21"] * pPtB["a22"]) + (pPtA["a31"] * pPtB["a23"])) into tXform["a21"]
   put ((pPtA["a11"] * pPtB["a31"]) + (pPtA["a21"] * pPtB["a32"]) + (pPtA["a31"] * pPtB["a33"])) into tXform["a31"]
   put ((pPtA["a12"] * pPtB["a11"]) + (pPtA["a22"] * pPtB["a12"]) + (pPtA["a32"] * pPtB["a13"])) into tXform["a12"]
   put ((pPtA["a12"] * pPtB["a21"]) + (pPtA["a22"] * pPtB["a22"]) + (pPtA["a32"] * pPtB["a23"])) into tXform["a22"]
   put ((pPtA["a12"] * pPtB["a31"]) + (pPtA["a22"] * pPtB["a32"]) + (pPtA["a32"] * pPtB["a33"])) into tXform["a32"]
   put ((pPtA["a13"] * pPtB["a11"]) + (pPtA["a23"] * pPtB["a12"]) + (pPtA["a33"] * pPtB["a13"])) into tXform["a13"]
   put ((pPtA["a13"] * pPtB["a21"]) + (pPtA["a23"] * pPtB["a22"]) + (pPtA["a33"] * pPtB["a23"])) into tXform["a23"]
   put ((pPtA["a13"] * pPtB["a31"]) + (pPtA["a23"] * pPtB["a32"]) + (pPtA["a33"] * pPtB["a33"])) into tXform["a33"]
   return tXform
end pt_times

function pt_quadrilateralToQuadrilateral pX0, pY0, pX1, pY1, pX2, pY2, pX3, pY3, pX0p, pY0p, pX1p, pY1p, pX2p, pY2p, pX3p, pY3p
   local tQToS, tSToQ
   put pt_quadrilateralToSquare(pX0, pY0, pX1, pY1, pX2, pY2, pX3, pY3) into tQToS
   put pt_squareToQuadrilateral(pX0p, pY0p, pX1p, pY1p, pX2p, pY2p, pX3p, pY3p) into tSToQ
   return pt_times(tSToQ, tQToS)
end pt_quadrilateralToQuadrilateral

-- transform a 0-based flat point array {x0,y0,x1,y1,...} in place (command, @).
-- denom == 0 leaves the point unchanged (matches the PHP guard).
command pt_transformPoints @pPoints, pXform
   local tNumPts, k, i, tValX, tValY, tDenom
   local tA11, tA21, tA31, tA12, tA22, tA32, tA13, tA23, tA33
   -- points come in (x,y) pairs; xTalk repeat has no "step", so iterate the
   -- pair index k and derive the flat offset i = 2*k.
   put ((the number of elements of pPoints) div 2) into tNumPts
   put pXform["a11"] into tA11
   put pXform["a21"] into tA21
   put pXform["a31"] into tA31
   put pXform["a12"] into tA12
   put pXform["a22"] into tA22
   put pXform["a32"] into tA32
   put pXform["a13"] into tA13
   put pXform["a23"] into tA23
   put pXform["a33"] into tA33
   repeat with k = 0 to (tNumPts - 1)
      put (k * 2) into i
      put pPoints[i] into tValX
      put pPoints[i + 1] into tValY
      put ((tA13 * tValX) + (tA23 * tValY) + tA33) into tDenom
      if tDenom <> 0 then
         put (((tA11 * tValX) + (tA21 * tValY) + tA31) / tDenom) into pPoints[i]
         put (((tA12 * tValX) + (tA22 * tValY) + tA32) / tDenom) into pPoints[i + 1]
      end if
   end repeat
end pt_transformPoints

-- ===================== module: gridSampler =============
-- =====================================================================
-- gridSampler.lc - sample a module grid through a transform. Spec section 8.4.
-- Port of ZXing Common\GridSampler + DefaultGridSampler.
-- Requires: qrCompat.lc, bitMatrix.lc, perspectiveTransform.lc.
--
-- gs_sampleGrid(image, dimX, dimY, transform) -> BitMatrix:
--   for each output row y, build the sample points (x+0.5, y+0.5) for every
--   column, run them through the transform, clamp endpoints to the image edge
--   (checkAndNudgePoints), then read image.get at each sampled pixel.
--
-- A row whose END points land more than one pixel outside the image throws
-- NotFound (checkAndNudgePoints, as in ZXing/PHP); an interior sample that
-- strays just outside reads as white, which is what PHP's BitMatrix::get and
-- Java's zero padding bits do (the port threw NotFound there until 2026-09).
-- =====================================================================

local sGSPow2, sGSPow2Ready      -- sGSPow2[b] = 2^b, b = 0..31; built once

command gs_ensurePow2
   local b, v
   if sGSPow2Ready is true then exit gs_ensurePow2
   put 1 into v
   repeat with b = 0 to 31
      put v into sGSPow2[b]
      put (v * 2) into v
   end repeat
   put true into sGSPow2Ready
end gs_ensurePow2

-- clamp barely-off endpoints back onto the image; throw if truly outside.
-- Mutates pPoints in place (command, @). Mirrors checkAndNudgePoints exactly:
-- nudge from the start until a point is OK, then nudge from the end likewise.
command gs_checkAndNudgePoints @pPoints, pWidth, pHeight
   local tCountN, tNudged, tOffset, tValX, tValY
   put (the number of elements of pPoints) into tCountN

   put true into tNudged
   put 0 into tOffset
   repeat while (tOffset < tCountN) and tNudged
      put trunc(pPoints[tOffset]) into tValX
      put trunc(pPoints[tOffset + 1]) into tValY
      if (tValX < -1) or (tValX > pWidth) or (tValY < -1) or (tValY > pHeight) then
         throw "NotFound: endpoint (" & tValX & "," & tValY & ") outside image (" & pWidth & "," & pHeight & ")"
      end if
      put false into tNudged
      if tValX = -1 then
         put 0 into pPoints[tOffset]
         put true into tNudged
      else if tValX = pWidth then
         put (pWidth - 1) into pPoints[tOffset]
         put true into tNudged
      end if
      if tValY = -1 then
         put 0 into pPoints[tOffset + 1]
         put true into tNudged
      else if tValY = pHeight then
         put (pHeight - 1) into pPoints[tOffset + 1]
         put true into tNudged
      end if
      add 2 to tOffset
   end repeat

   put true into tNudged
   put (tCountN - 2) into tOffset
   repeat while (tOffset >= 0) and tNudged
      put trunc(pPoints[tOffset]) into tValX
      put trunc(pPoints[tOffset + 1]) into tValY
      if (tValX < -1) or (tValX > pWidth) or (tValY < -1) or (tValY > pHeight) then
         throw "NotFound: endpoint (" & tValX & "," & tValY & ") outside image (" & pWidth & "," & pHeight & ")"
      end if
      put false into tNudged
      if tValX = -1 then
         put 0 into pPoints[tOffset]
         put true into tNudged
      else if tValX = pWidth then
         put (pWidth - 1) into pPoints[tOffset]
         put true into tNudged
      end if
      if tValY = -1 then
         put 0 into pPoints[tOffset + 1]
         put true into tNudged
      else if tValY = pHeight then
         put (pHeight - 1) into pPoints[tOffset + 1]
         put true into tNudged
      end if
      subtract 2 from tOffset
   end repeat
end gs_checkAndNudgePoints

function gs_sampleGrid pImage, pDimX, pDimY, pTransform
   local tBits, tPoints, y, c, x, tIValue, tImgW, tImgH, tPX, tPY
   local tWords, tOutRowSize, tImgBits, tImgRowSize, tOff
   if (pDimX <= 0) or (pDimY <= 0) then
      throw "NotFound: grid dimensions <= 0"
   end if
   put bitMatrix_new(pDimX, pDimY) into tBits
   put bitMatrix_getWidth(pImage) into tImgW
   put bitMatrix_getHeight(pImage) into tImgH
   -- HOT PATH (2026-09): one image read and one output write per module, on
   -- the matrices' word arrays directly (the same bits bitMatrix_get/set
   -- would read and set; proven bit-identical under the headless model)
   gs_ensurePow2
   put tBits["bits"] into tWords
   put tBits["rowSize"] into tOutRowSize
   put pImage["bits"] into tImgBits
   put pImage["rowSize"] into tImgRowSize
   -- xTalk repeat has no "step"; iterate the column c and use x = 2*c as the
   -- flat (x,y) offset into the points array.
   repeat with y = 0 to (pDimY - 1)
      put (y + 0.5) into tIValue
      repeat with c = 0 to (pDimX - 1)
         put (c * 2) into x
         put (c + 0.5) into tPoints[x]
         put tIValue into tPoints[x + 1]
      end repeat
      pt_transformPoints tPoints, pTransform
      gs_checkAndNudgePoints tPoints, tImgW, tImgH
      repeat with c = 0 to (pDimX - 1)
         put (c * 2) into x
         put trunc(tPoints[x]) into tPX
         put trunc(tPoints[x + 1]) into tPY
         -- a sample just outside the image reads WHITE: PHP's BitMatrix::get
         -- answers false for any out-of-range coordinate and Java reads a zero
         -- padding bit for x just past the width; only the row ENDPOINTS are
         -- policed, by gs_checkAndNudgePoints above
         if (tPX >= 0) and (tPY >= 0) and (tPX < tImgW) and (tPY < tImgH) then
            if ((tImgBits[(tPY * tImgRowSize) + (tPX div 32)] div sGSPow2[tPX bitAnd 31]) bitAnd 1) = 1 then
               put ((y * tOutRowSize) + (c div 32)) into tOff
               put (tWords[tOff] bitOr sGSPow2[c bitAnd 31]) into tWords[tOff]
            end if
         end if
      end repeat
   end repeat
   put tWords into tBits["bits"]
   return tBits
end gs_sampleGrid

-- ===================== module: finderPatternFinder =====
-- =====================================================================
-- finderPatternFinder.lc - locate the 3 corner finder patterns. Spec section 8.4.
-- Port of ZXing Qrcode\Detector\FinderPatternFinder (the most intricate module).
-- Requires: qrCompat.lc, bitMatrix.lc, mathUtils.lc, resultPoint.lc.
--
-- Finder state (Pattern A) is an array pF:
--   pF["bits"]   the binarized BitMatrix to search (true = black)
--   pF["np"]     number of possible centres found so far
--   pF["pat"][k] a finder pattern {["x"],["y"],["ms"]=est module size,["ct"]=count}
--   pF["skip"]   hasSkipped flag
-- Entry point fpf_find(image, hints) -> {["bl"],["tl"],["tr"]} (3 ordered points).
--
-- XTALK NOTES:
--  * NaN is represented by `empty`; crossCheck* return a number or empty, and
--    callers test `is empty` / `is not empty`. A real centre is never empty.
--  * The PHP inner-loop `continue` is replaced by restructured if/else (no skip
--    of the clear-state code) and a tEndRow flag + `exit repeat` for the row
--    skip -- both behaviourally identical, no reliance on loop-counter mutation.
--  * Out-of-range bitMatrix_get reads return false harmlessly, so the guarded
--    `(i >= 0) and bitMatrix_get(...)` conditions are safe whether or not the
--    engine short-circuits `and`.
--  * CENTER_QUORUM=2, MIN_SKIP=3, MAX_MODULES=97 and
--    MAX_FINDER_PATTERN_CANDIDATES=25 are inlined as literals.
--  * Since 2026-09 the candidate SELECTION follows current ZXing Java (the
--    2020+ isosceles-right-triangle scoring; every candidate diagonal-checked;
--    MAX_MODULES 97; row skip 2 after a confirmed centre) rather than the
--    2013-era PHP port. Detection outcomes are compared against ZXing itself
--    on a synthetic corpus (tools/run_synthetic.py).
-- =====================================================================

-- HOT PATH (2026-09): the row scan reads the matrix's 32-bit words directly
-- (one word per 32 pixels, one table lookup per pixel) instead of calling
-- bitMatrix_get per pixel, and skips whole words when nothing can change the
-- run state: an all-white word while already counting a white run adds 32 to
-- that run, an all-black word while counting a black run likewise. Every state
-- transition still happens on the exact pixel it did before (proven
-- bit-identical under the headless model: same candidates, same centres).
local sFPPow2, sFPPow2Ready      -- sFPPow2[b] = 2^b, b = 0..31; built once

command fpf_ensurePow2
   local b, v
   if sFPPow2Ready is true then exit fpf_ensurePow2
   put 1 into v
   repeat with b = 0 to 31
      put v into sFPPow2[b]
      put (v * 2) into v
   end repeat
   put true into sFPPow2Ready
end fpf_ensurePow2

-- is key pKey present in the hints array pHints? Uses only proven constructs:
-- "the keys of" yields a CR-list of keys; "among the lines of" tests membership.
-- A non-array pHints yields an empty key list, so this safely returns false.
function fpf_hintPresent pHints, pKey
   return (pKey is among the lines of the keys of pHints)
end fpf_hintPresent

-- 1:1:3:1:1 proportion test on a 5-element run count (spec section 8.4)
function fpf_foundPatternCross pSC, pMaxVariance
   local tTotal, i, tCount, tModuleSize, tMV
   put 0 into tTotal
   repeat with i = 0 to 4
      put pSC[i] into tCount
      if tCount = 0 then return false
      add tCount to tTotal
   end repeat
   if tTotal < 7 then return false
   put (tTotal / 7) into tModuleSize
   put (tModuleSize * pMaxVariance) into tMV
   return ((abs(tModuleSize - pSC[0]) < tMV) and \
           (abs(tModuleSize - pSC[1]) < tMV) and \
           (abs((3 * tModuleSize) - pSC[2]) < (3 * tMV)) and \
           (abs(tModuleSize - pSC[3]) < tMV) and \
           (abs(tModuleSize - pSC[4]) < tMV))
end fpf_foundPatternCross

-- the 1:1:3:1:1 test with the looser tolerance the diagonal check uses
-- (ZXing foundPatternDiagonal: maxVariance = moduleSize / 1.333)
function fpf_foundPatternDiagonal pSC
   local tTotal, i, tCount, tModuleSize, tMV
   put 0 into tTotal
   repeat with i = 0 to 4
      put pSC[i] into tCount
      if tCount = 0 then return false
      add tCount to tTotal
   end repeat
   if tTotal < 7 then return false
   put (tTotal / 7) into tModuleSize
   put (tModuleSize / 1.333) into tMV
   return ((abs(tModuleSize - pSC[0]) < tMV) and \
           (abs(tModuleSize - pSC[1]) < tMV) and \
           (abs((3 * tModuleSize) - pSC[2]) < (3 * tMV)) and \
           (abs(tModuleSize - pSC[3]) < tMV) and \
           (abs(tModuleSize - pSC[4]) < tMV))
end fpf_foundPatternDiagonal

-- centre of a run given the end position (spec section 8.4)
function fpf_centerFromEnd pSC, pEnd
   return ((pEnd - pSC[4] - pSC[3]) - (pSC[2] / 2))
end fpf_centerFromEnd

-- shift the run counts back by two (the "no winner" recovery)
command fpf_shiftCounts2 @pSC
   put pSC[2] into pSC[0]
   put pSC[3] into pSC[1]
   put pSC[4] into pSC[2]
   put 1 into pSC[3]
   put 0 into pSC[4]
end fpf_shiftCounts2

-- vertical cross-check; returns the vertical centre or empty (NaN)
function fpf_crossCheckVertical pImg, pStartI, pCenterJ, pMaxCount, pOrigTotal
   local tMaxI, tSC, i, tTotal
   put bitMatrix_getHeight(pImg) into tMaxI
   put 0 into tSC[0]
   put 0 into tSC[1]
   put 0 into tSC[2]
   put 0 into tSC[3]
   put 0 into tSC[4]
   put pStartI into i
   repeat while (i >= 0) and bitMatrix_get(pImg, pCenterJ, i)
      add 1 to tSC[2]
      subtract 1 from i
   end repeat
   if i < 0 then return empty
   repeat while (i >= 0) and (not bitMatrix_get(pImg, pCenterJ, i)) and (tSC[1] <= pMaxCount)
      add 1 to tSC[1]
      subtract 1 from i
   end repeat
   if (i < 0) or (tSC[1] > pMaxCount) then return empty
   repeat while (i >= 0) and bitMatrix_get(pImg, pCenterJ, i) and (tSC[0] <= pMaxCount)
      add 1 to tSC[0]
      subtract 1 from i
   end repeat
   if tSC[0] > pMaxCount then return empty
   put (pStartI + 1) into i
   repeat while (i < tMaxI) and bitMatrix_get(pImg, pCenterJ, i)
      add 1 to tSC[2]
      add 1 to i
   end repeat
   if i = tMaxI then return empty
   repeat while (i < tMaxI) and (not bitMatrix_get(pImg, pCenterJ, i)) and (tSC[3] < pMaxCount)
      add 1 to tSC[3]
      add 1 to i
   end repeat
   if (i = tMaxI) or (tSC[3] >= pMaxCount) then return empty
   repeat while (i < tMaxI) and bitMatrix_get(pImg, pCenterJ, i) and (tSC[4] < pMaxCount)
      add 1 to tSC[4]
      add 1 to i
   end repeat
   if tSC[4] >= pMaxCount then return empty
   put (tSC[0] + tSC[1] + tSC[2] + tSC[3] + tSC[4]) into tTotal
   if (5 * abs(tTotal - pOrigTotal)) >= (2 * pOrigTotal) then return empty
   if fpf_foundPatternCross(tSC, 0.5) then
      return fpf_centerFromEnd(tSC, i)
   end if
   return empty
end fpf_crossCheckVertical

-- horizontal cross-check; returns the horizontal centre or empty (NaN)
function fpf_crossCheckHorizontal pImg, pStartJ, pCenterI, pMaxCount, pOrigTotal
   local tMaxJ, tSC, j, tTotal
   put bitMatrix_getWidth(pImg) into tMaxJ
   put 0 into tSC[0]
   put 0 into tSC[1]
   put 0 into tSC[2]
   put 0 into tSC[3]
   put 0 into tSC[4]
   put pStartJ into j
   repeat while (j >= 0) and bitMatrix_get(pImg, j, pCenterI)
      add 1 to tSC[2]
      subtract 1 from j
   end repeat
   if j < 0 then return empty
   repeat while (j >= 0) and (not bitMatrix_get(pImg, j, pCenterI)) and (tSC[1] <= pMaxCount)
      add 1 to tSC[1]
      subtract 1 from j
   end repeat
   if (j < 0) or (tSC[1] > pMaxCount) then return empty
   repeat while (j >= 0) and bitMatrix_get(pImg, j, pCenterI) and (tSC[0] <= pMaxCount)
      add 1 to tSC[0]
      subtract 1 from j
   end repeat
   if tSC[0] > pMaxCount then return empty
   put (pStartJ + 1) into j
   repeat while (j < tMaxJ) and bitMatrix_get(pImg, j, pCenterI)
      add 1 to tSC[2]
      add 1 to j
   end repeat
   if j = tMaxJ then return empty
   repeat while (j < tMaxJ) and (not bitMatrix_get(pImg, j, pCenterI)) and (tSC[3] < pMaxCount)
      add 1 to tSC[3]
      add 1 to j
   end repeat
   if (j = tMaxJ) or (tSC[3] >= pMaxCount) then return empty
   repeat while (j < tMaxJ) and bitMatrix_get(pImg, j, pCenterI) and (tSC[4] < pMaxCount)
      add 1 to tSC[4]
      add 1 to j
   end repeat
   if tSC[4] >= pMaxCount then return empty
   put (tSC[0] + tSC[1] + tSC[2] + tSC[3] + tSC[4]) into tTotal
   if (5 * abs(tTotal - pOrigTotal)) >= pOrigTotal then return empty
   if fpf_foundPatternCross(tSC, 0.5) then
      return fpf_centerFromEnd(tSC, j)
   end if
   return empty
end fpf_crossCheckHorizontal

-- diagonal cross-check (ZXing FinderPatternFinder.crossCheckDiagonal, 3.4+):
-- walk up-left and down-right from the centre counting the 1:1:3:1:1 run, and
-- test it with the looser diagonal tolerance. Run for EVERY candidate (the
-- older code did it only in PURE_BARCODE mode); a read outside the matrix is
-- false, so the coordinate guards below match Java's exactly.
function fpf_crossCheckDiagonal pImg, pCenterI, pCenterJ
   local tSC, i, tMaxI, tMaxJ
   put 0 into tSC[0]
   put 0 into tSC[1]
   put 0 into tSC[2]
   put 0 into tSC[3]
   put 0 into tSC[4]
   put 0 into i
   repeat while (pCenterI >= i) and (pCenterJ >= i) and bitMatrix_get(pImg, (pCenterJ - i), (pCenterI - i))
      add 1 to tSC[2]
      add 1 to i
   end repeat
   if tSC[2] = 0 then return false
   repeat while (pCenterI >= i) and (pCenterJ >= i) and (not bitMatrix_get(pImg, (pCenterJ - i), (pCenterI - i)))
      add 1 to tSC[1]
      add 1 to i
   end repeat
   if tSC[1] = 0 then return false
   repeat while (pCenterI >= i) and (pCenterJ >= i) and bitMatrix_get(pImg, (pCenterJ - i), (pCenterI - i))
      add 1 to tSC[0]
      add 1 to i
   end repeat
   if tSC[0] = 0 then return false
   put bitMatrix_getHeight(pImg) into tMaxI
   put bitMatrix_getWidth(pImg) into tMaxJ
   put 1 into i
   repeat while ((pCenterI + i) < tMaxI) and ((pCenterJ + i) < tMaxJ) and bitMatrix_get(pImg, (pCenterJ + i), (pCenterI + i))
      add 1 to tSC[2]
      add 1 to i
   end repeat
   repeat while ((pCenterI + i) < tMaxI) and ((pCenterJ + i) < tMaxJ) and (not bitMatrix_get(pImg, (pCenterJ + i), (pCenterI + i)))
      add 1 to tSC[3]
      add 1 to i
   end repeat
   if tSC[3] = 0 then return false
   repeat while ((pCenterI + i) < tMaxI) and ((pCenterJ + i) < tMaxJ) and bitMatrix_get(pImg, (pCenterJ + i), (pCenterI + i))
      add 1 to tSC[4]
      add 1 to i
   end repeat
   if tSC[4] = 0 then return false
   return fpf_foundPatternDiagonal(tSC)
end fpf_crossCheckDiagonal

-- a horizontal candidate: cross-check, then accumulate/merge into pF["pat"].
-- rConfirmed (output) = true iff a finder candidate was confirmed this call.
command fpf_handlePossibleCenter @pFinder, pSC, pRowI, pEndCol, @rConfirmed
   local tTotal, tCenterJ, tCenterI, tEst, tFound, tIdx
   local tOldX, tOldY, tOldMs, tOldCt, tMSDiff, tCC
   put false into rConfirmed
   put (pSC[0] + pSC[1] + pSC[2] + pSC[3] + pSC[4]) into tTotal
   put fpf_centerFromEnd(pSC, pEndCol) into tCenterJ
   put fpf_crossCheckVertical(pFinder["bits"], pRowI, trunc(tCenterJ), pSC[2], tTotal) into tCenterI
   if tCenterI is empty then exit fpf_handlePossibleCenter
   put fpf_crossCheckHorizontal(pFinder["bits"], trunc(tCenterJ), trunc(tCenterI), pSC[2], tTotal) into tCenterJ
   if tCenterJ is empty then exit fpf_handlePossibleCenter
   -- ZXing: re-cross-check along the diagonal for every candidate
   if not fpf_crossCheckDiagonal(pFinder["bits"], trunc(tCenterI), trunc(tCenterJ)) then
      exit fpf_handlePossibleCenter
   end if
   put (tTotal / 7) into tEst
   put false into tFound
   repeat with tIdx = 0 to (pFinder["np"] - 1)
      put pFinder["pat"][tIdx]["x"] into tOldX
      put pFinder["pat"][tIdx]["y"] into tOldY
      put pFinder["pat"][tIdx]["ms"] into tOldMs
      put pFinder["pat"][tIdx]["ct"] into tOldCt
      if (abs(tCenterI - tOldY) <= tEst) and (abs(tCenterJ - tOldX) <= tEst) then
         put abs(tEst - tOldMs) into tMSDiff
         if (tMSDiff <= 1) or (tMSDiff <= tOldMs) then
            put (tOldCt + 1) into tCC
            put (((tOldCt * tOldX) + tCenterJ) / tCC) into pFinder["pat"][tIdx]["x"]
            put (((tOldCt * tOldY) + tCenterI) / tCC) into pFinder["pat"][tIdx]["y"]
            put (((tOldCt * tOldMs) + tEst) / tCC) into pFinder["pat"][tIdx]["ms"]
            put tCC into pFinder["pat"][tIdx]["ct"]
            put true into tFound
            exit repeat
         end if
      end if
   end repeat
   if not tFound then
      put tCenterJ into pFinder["pat"][pFinder["np"]]["x"]
      put tCenterI into pFinder["pat"][pFinder["np"]]["y"]
      put tEst into pFinder["pat"][pFinder["np"]]["ms"]
      put 1 into pFinder["pat"][pFinder["np"]]["ct"]
      add 1 to pFinder["np"]
   end if
   put true into rConfirmed
end fpf_handlePossibleCenter

-- >=3 centres each confirmed >=2 times, with similar module sizes?
function fpf_haveMultiplyConfirmedCenters pFinder, pAllowedDev
   local tConfirmed, tTotalMS, tMax, k, tAvg, tTotalDev
   put 0 into tConfirmed
   put 0 into tTotalMS
   put pFinder["np"] into tMax
   repeat with k = 0 to (tMax - 1)
      if pFinder["pat"][k]["ct"] >= 2 then
         add 1 to tConfirmed
         add pFinder["pat"][k]["ms"] to tTotalMS
      end if
   end repeat
   if tConfirmed < 3 then return false
   put (tTotalMS / tMax) into tAvg
   put 0 into tTotalDev
   repeat with k = 0 to (tMax - 1)
      add abs(pFinder["pat"][k]["ms"] - tAvg) to tTotalDev
   end repeat
   return (tTotalDev <= (pAllowedDev * tTotalMS))
end fpf_haveMultiplyConfirmedCenters

-- rows we may skip once two centres are confirmed; sets pF["skip"] when it does.
command fpf_findRowSkip @pFinder, @rSkip
   local tMax, k, tFirstX, tFirstY, tHaveFirst
   put pFinder["np"] into tMax
   if tMax <= 1 then
      put 0 into rSkip
      exit fpf_findRowSkip
   end if
   put false into tHaveFirst
   repeat with k = 0 to (tMax - 1)
      if pFinder["pat"][k]["ct"] >= 2 then
         if not tHaveFirst then
            put pFinder["pat"][k]["x"] into tFirstX
            put pFinder["pat"][k]["y"] into tFirstY
            put true into tHaveFirst
         else
            put true into pFinder["skip"]
            put trunc((abs(tFirstX - pFinder["pat"][k]["x"]) - abs(tFirstY - pFinder["pat"][k]["y"])) / 2) into rSkip
            exit fpf_findRowSkip
         end if
      end if
   end repeat
   put 0 into rSkip
end fpf_findRowSkip

-- stable insertion sort by FurthestFromAverageComparator (largest |dev| first)
-- PHP comparator: dA=|c2-avg|, dB=|c1-avg|; -1 if dA<dB. usort places a before b
-- stable insertion sort of a 0-based list by estimated module size, ascending
-- (ZXing EstimatedModuleComparator; Java's Collections.sort is stable too)
command fpf_sortByModuleSize @pList, pCountN
   local i, j, tKey
   repeat with i = 1 to (pCountN - 1)
      put pList[i] into tKey
      put (i - 1) into j
      repeat while j >= 0
         if pList[j]["ms"] > tKey["ms"] then
            put pList[j] into pList[j + 1]
            subtract 1 from j
         else
            exit repeat
         end if
      end repeat
      put tKey into pList[j + 1]
   end repeat
end fpf_sortByModuleSize

function fpf_squaredDistance pA, pB
   local dx, dy
   put (pA["x"] - pB["x"]) into dx
   put (pA["y"] - pB["y"]) into dy
   return ((dx * dx) + (dy * dy))
end fpf_squaredDistance

-- pick the best 3 finder candidates (ZXing FinderPatternFinder.selectBestPatterns,
-- the 2020+ algorithm): once three centres are confirmed - or the list is
-- large - drop the unconfirmed ones; sort by module size; then score every
-- triple of similar module size (within 1.4x) by how far its squared side
-- lengths a <= b <= c are from an isosceles right triangle, |c-2b| + |c-2a|,
-- and keep the least distorted. Throws NotFound if no such triple exists.
-- (The pre-2020 heuristic the PHP port carries - drop module-size outliers,
-- then sort by confirmation count - discarded the three TRUE finders of a
-- clean v30 symbol as outliers next to four accidental 1:1:3:1:1 runs in its
-- data region; found by the synthetic corpus, decoded fine by current ZXing.)
function fpf_selectBestPatterns pFinder
   local tCountN, k, tList, tN, tConfirmed, tKeepAll, i, j, tOut
   local tMinMs, tMaxMs, a, b, c, tTemp, d, tBestD, tBestI, tBestJ, tBestK, tSq0
   put pFinder["np"] into tCountN
   if tCountN < 3 then
      throw "NotFound: could not find 3 finder patterns (" & tCountN & " found)"
   end if
   put 0 into tConfirmed
   repeat with k = 0 to (tCountN - 1)
      if pFinder["pat"][k]["ct"] >= 2 then add 1 to tConfirmed
   end repeat
   put ((tConfirmed < 3) and (tCountN <= 25)) into tKeepAll
   put 0 into tN
   repeat with k = 0 to (tCountN - 1)
      if tKeepAll or (pFinder["pat"][k]["ct"] >= 2) then
         put pFinder["pat"][k] into tList[tN]
         add 1 to tN
      end if
   end repeat
   fpf_sortByModuleSize tList, tN
   put -1 into tBestI
   put 0 into tBestD
   repeat with i = 0 to (tN - 3)
      put tList[i]["ms"] into tMinMs
      repeat with j = (i + 1) to (tN - 2)
         put fpf_squaredDistance(tList[i], tList[j]) into tSq0
         repeat with k = (j + 1) to (tN - 1)
            put tList[k]["ms"] into tMaxMs
            if tMaxMs > (tMinMs * 1.4) then next repeat      -- module size not similar
            put tSq0 into a
            put fpf_squaredDistance(tList[j], tList[k]) into b
            put fpf_squaredDistance(tList[i], tList[k]) into c
            -- sort a <= b <= c
            if a > b then
               put a into tTemp
               put b into a
               put tTemp into b
            end if
            if b > c then
               put b into tTemp
               put c into b
               put tTemp into c
            end if
            if a > b then
               put a into tTemp
               put b into a
               put tTemp into b
            end if
            put (abs(c - (2 * b)) + abs(c - (2 * a))) into d
            if (tBestI < 0) or (d < tBestD) then
               put d into tBestD
               put i into tBestI
               put j into tBestJ
               put k into tBestK
            end if
         end repeat
      end repeat
   end repeat
   if tBestI < 0 then
      throw "NotFound: no three finder patterns form a right isosceles triangle (" & tN & " candidates)"
   end if
   put tList[tBestI] into tOut[0]
   put tList[tBestJ] into tOut[1]
   put tList[tBestK] into tOut[2]
   return tOut
end fpf_selectBestPatterns

-- main entry: scan the image, returns {["bl"],["tl"],["tr"]} (ordered points)
function fpf_find pImg, pHints
   local tTryHarder, tNrSkip, tAllowedDev, tMaxVar
   local tMaxI, tMaxJ, tISkip, tDone, i, j, tSC, tCurState, tEndRow
   local tConfirmed, tRowSkip, tInfo, tPats, tFinder
   local tBits, tRowSize, tRowBase, tWi, tWord, tJ0, tB
   -- hints: read each key directly. A missing key (or a non-array pHints)
   -- yields empty in xTalk, so we just test the read value -- no need for
   -- "is an array" / "is among the keys of" (both unexercised on this engine).
   -- fpf_hintPresent() centralises the "present?" test using only proven constructs.
   put qr_hintFlag(pHints, "TRY_HARDER") into tTryHarder
   if fpf_hintPresent(pHints, "NR_ALLOW_SKIP_ROWS") then
      put pHints["NR_ALLOW_SKIP_ROWS"] into tNrSkip
   else if tTryHarder then
      put 0 into tNrSkip
   else
      put empty into tNrSkip
   end if
   if fpf_hintPresent(pHints, "ALLOWED_DEVIATION") then
      put pHints["ALLOWED_DEVIATION"] into tAllowedDev
   else
      put 0.05 into tAllowedDev
   end if
   if fpf_hintPresent(pHints, "MAX_VARIANCE") then
      put pHints["MAX_VARIANCE"] into tMaxVar
   else
      put 0.5 into tMaxVar
   end if
   put bitMatrix_getHeight(pImg) into tMaxI
   put bitMatrix_getWidth(pImg) into tMaxJ
   -- iSkip = (3*maxI) / (4*MAX_MODULES). MAX_MODULES=97 (ZXing: "support up to
   -- version 20"), so 4*97=388 (inlined as a literal: the engine dislikes a
   -- literal*literal product as a div operand).
   put ((3 * tMaxI) div 388) into tISkip
   if (tISkip < 3) or tTryHarder then put 3 into tISkip
   put false into tDone

   put pImg into tFinder["bits"]
   put 0 into tFinder["np"]
   put false into tFinder["skip"]
   fpf_ensurePow2
   put pImg["bits"] into tBits            -- read-only: the words of the matrix
   put pImg["rowSize"] into tRowSize

   put (tISkip - 1) into i
   repeat while (i < tMaxI) and (not tDone)
      put 0 into tSC[0]
      put 0 into tSC[1]
      put 0 into tSC[2]
      put 0 into tSC[3]
      put 0 into tSC[4]
      put 0 into tCurState
      put false into tEndRow
      put (i * tRowSize) into tRowBase
      repeat with tWi = 0 to (tRowSize - 1)
         put tBits[tRowBase + tWi] into tWord
         put (tWi * 32) into tJ0
         -- black runs are the even states, white runs the odd ones: a word that
         -- is all one colour, met while already counting that colour, cannot
         -- change the state - it only lengthens the current run
         if (tWord = 0) and ((tCurState bitAnd 1) = 1) then
            add min(32, (tMaxJ - tJ0)) to tSC[tCurState]
            next repeat
         end if
         if (tWord = 4294967295) and ((tCurState bitAnd 1) = 0) then
            add 32 to tSC[tCurState]
            next repeat
         end if
         repeat with tB = 0 to 31
            put (tJ0 + tB) into j
            if j >= tMaxJ then exit repeat
            if (tWord bitAnd sFPPow2[tB]) <> 0 then
               -- black pixel
               if (tCurState bitAnd 1) = 1 then add 1 to tCurState
               add 1 to tSC[tCurState]
            else
               -- white pixel
               if (tCurState bitAnd 1) = 0 then
                  if tCurState = 4 then
                     if fpf_foundPatternCross(tSC, tMaxVar) then
                        fpf_handlePossibleCenter tFinder, tSC, i, j, tConfirmed
                        if tConfirmed then
                           put 2 into tISkip                 -- ZXing: iSkip = 2
                           if tFinder["skip"] then
                              put fpf_haveMultiplyConfirmedCenters(tFinder, tAllowedDev) into tDone
                           else
                              if tNrSkip is empty then
                                 fpf_findRowSkip tFinder, tRowSkip
                              else
                                 put tNrSkip into tRowSkip
                              end if
                              if tRowSkip > tSC[2] then
                                 add (tRowSkip - tSC[2] - tISkip) to i
                                 put true into tEndRow
                              end if
                           end if
                           put 0 into tCurState
                           put 0 into tSC[0]
                           put 0 into tSC[1]
                           put 0 into tSC[2]
                           put 0 into tSC[3]
                           put 0 into tSC[4]
                           if tEndRow then
                              exit repeat            -- leaves the bit loop; the word loop checks tEndRow
                           end if
                        else
                           fpf_shiftCounts2 tSC
                           put 3 into tCurState
                        end if
                     else
                        fpf_shiftCounts2 tSC
                        put 3 into tCurState
                     end if
                  else
                     add 1 to tCurState
                     add 1 to tSC[tCurState]
                  end if
               else
                  add 1 to tSC[tCurState]
               end if
            end if
            end repeat
         if tEndRow then exit repeat
      end repeat
      if tEndRow then
         -- the row was abandoned after a confirmed centre (row skip): the
         -- end-of-row check did not run before 2026-09 either
         add tISkip to i
         next repeat
      end if
      if fpf_foundPatternCross(tSC, tMaxVar) then
         fpf_handlePossibleCenter tFinder, tSC, i, tMaxJ, tConfirmed
         if tConfirmed then
            put tSC[0] into tISkip
            if tFinder["skip"] then
               put fpf_haveMultiplyConfirmedCenters(tFinder, tAllowedDev) into tDone
            end if
         end if
      end if
      add tISkip to i
   end repeat

   put fpf_selectBestPatterns(tFinder) into tPats
   put rp_orderBestPatterns(tPats) into tPats
   put tPats[0] into tInfo["bl"]
   put tPats[1] into tInfo["tl"]
   put tPats[2] into tInfo["tr"]
   return tInfo
end fpf_find

-- ===================== module: alignmentPatternFinder ==
-- =====================================================================
-- alignmentPatternFinder.lc - locate the bottom-right alignment pattern (v2+).
-- Port of ZXing Qrcode\Detector\AlignmentPatternFinder. Spec section 8.4.
-- Requires: qrCompat.lc, bitMatrix.lc.
--
-- Stateless apart from a small accumulator: apf_find searches a sub-region for
-- the 1:1:1 black/white/black alignment cross. The image is passed by value
-- (copy-on-write, read-only) and the accumulator (possible centres) by @, so
-- the large image is never duplicated when a centre is recorded.
--
-- An alignment pattern point is {["x"],["y"],["ms"]}. NaN -> empty (as in the
-- finder). apf_find returns the point, or throws NotFound.
-- =====================================================================

-- 1:1:1 proportion test against the expected module size
function apf_foundPatternCross pModuleSize, pSC
   local tMaxVariance, i
   put (pModuleSize / 2) into tMaxVariance
   repeat with i = 0 to 2
      if abs(pModuleSize - pSC[i]) >= tMaxVariance then return false
   end repeat
   return true
end apf_foundPatternCross

function apf_centerFromEnd pSC, pEnd
   return ((pEnd - pSC[2]) - (pSC[1] / 2))
end apf_centerFromEnd

-- vertical cross-check; returns the vertical centre or empty (NaN)
function apf_crossCheckVertical pImg, pModuleSize, pStartI, pCenterJ, pMaxCount, pOrigTotal
   local tMaxI, tSC, i, tTotal
   put bitMatrix_getHeight(pImg) into tMaxI
   put 0 into tSC[0]
   put 0 into tSC[1]
   put 0 into tSC[2]
   put pStartI into i
   repeat while (i >= 0) and bitMatrix_get(pImg, pCenterJ, i) and (tSC[1] <= pMaxCount)
      add 1 to tSC[1]
      subtract 1 from i
   end repeat
   if (i < 0) or (tSC[1] > pMaxCount) then return empty
   repeat while (i >= 0) and (not bitMatrix_get(pImg, pCenterJ, i)) and (tSC[0] <= pMaxCount)
      add 1 to tSC[0]
      subtract 1 from i
   end repeat
   if tSC[0] > pMaxCount then return empty
   put (pStartI + 1) into i
   repeat while (i < tMaxI) and bitMatrix_get(pImg, pCenterJ, i) and (tSC[1] <= pMaxCount)
      add 1 to tSC[1]
      add 1 to i
   end repeat
   if (i = tMaxI) or (tSC[1] > pMaxCount) then return empty
   repeat while (i < tMaxI) and (not bitMatrix_get(pImg, pCenterJ, i)) and (tSC[2] <= pMaxCount)
      add 1 to tSC[2]
      add 1 to i
   end repeat
   if tSC[2] > pMaxCount then return empty
   put (tSC[0] + tSC[1] + tSC[2]) into tTotal
   if (5 * abs(tTotal - pOrigTotal)) >= (2 * pOrigTotal) then return empty
   if apf_foundPatternCross(pModuleSize, tSC) then
      return apf_centerFromEnd(tSC, i)
   end if
   return empty
end apf_crossCheckVertical

-- cross-check + merge. rResult = the confirmed (combined) point, or empty if
-- this was a first sighting (just recorded in the accumulator).
command apf_handlePossibleCenter pImg, pModuleSize, @pAcc, pSC, pRowI, pEndCol, @rResult
   local tTotal, tCenterJ, tCenterI, tEst, k, tMSDiff, tCombined
   put empty into rResult
   put (pSC[0] + pSC[1] + pSC[2]) into tTotal
   put apf_centerFromEnd(pSC, pEndCol) into tCenterJ
   put apf_crossCheckVertical(pImg, pModuleSize, pRowI, trunc(tCenterJ), (2 * pSC[1]), tTotal) into tCenterI
   if tCenterI is empty then exit apf_handlePossibleCenter
   put ((pSC[0] + pSC[1] + pSC[2]) / 3) into tEst
   repeat with k = 0 to (pAcc["np"] - 1)
      if (abs(tCenterI - pAcc["pat"][k]["y"]) <= tEst) and (abs(tCenterJ - pAcc["pat"][k]["x"]) <= tEst) then
         put abs(tEst - pAcc["pat"][k]["ms"]) into tMSDiff
         if (tMSDiff <= 1) or (tMSDiff <= pAcc["pat"][k]["ms"]) then
            put ((pAcc["pat"][k]["x"] + tCenterJ) / 2) into tCombined["x"]
            put ((pAcc["pat"][k]["y"] + tCenterI) / 2) into tCombined["y"]
            put ((pAcc["pat"][k]["ms"] + tEst) / 2) into tCombined["ms"]
            put tCombined into rResult
            exit apf_handlePossibleCenter
         end if
      end if
   end repeat
   put tCenterJ into pAcc["pat"][pAcc["np"]]["x"]
   put tCenterI into pAcc["pat"][pAcc["np"]]["y"]
   put tEst into pAcc["pat"][pAcc["np"]]["ms"]
   add 1 to pAcc["np"]
end apf_handlePossibleCenter

-- search the region for the alignment cross; returns a point or throws NotFound
function apf_find pImg, pStartX, pStartY, pWidth, pHeight, pModuleSize
   local tMaxJ, tMiddleI, iGen, i, j, tSC, tCurState, tAcc, tResult
   put (pStartX + pWidth) into tMaxJ
   -- row schedule: middle row first, then alternately below/above it. ZXing
   -- (Java) uses INTEGER division here; the PHP port's float middle skipped the
   -- true middle row for odd heights and visited one row below the region.
   put (pStartY + (pHeight div 2)) into tMiddleI
   put 0 into tAcc["np"]
   repeat with iGen = 0 to (pHeight - 1)
      if (iGen bitAnd 1) = 0 then
         put (tMiddleI + ((iGen + 1) div 2)) into i
      else
         put (tMiddleI - ((iGen + 1) div 2)) into i
      end if
      put 0 into tSC[0]
      put 0 into tSC[1]
      put 0 into tSC[2]
      put pStartX into j
      repeat while (j < tMaxJ) and (not bitMatrix_get(pImg, j, i))
         add 1 to j
      end repeat
      put 0 into tCurState
      repeat while j < tMaxJ
         if bitMatrix_get(pImg, j, i) then
            -- black pixel
            if tCurState = 1 then
               add 1 to tSC[tCurState]
            else
               if tCurState = 2 then
                  if apf_foundPatternCross(pModuleSize, tSC) then
                     apf_handlePossibleCenter pImg, pModuleSize, tAcc, tSC, i, j, tResult
                     if tResult is not empty then return tResult
                  end if
                  put tSC[2] into tSC[0]
                  put 1 into tSC[1]
                  put 0 into tSC[2]
                  put 1 into tCurState
               else
                  add 1 to tCurState
                  add 1 to tSC[tCurState]
               end if
            end if
         else
            -- white pixel
            if tCurState = 1 then add 1 to tCurState
            add 1 to tSC[tCurState]
         end if
         add 1 to j
      end repeat
      if apf_foundPatternCross(pModuleSize, tSC) then
         apf_handlePossibleCenter pImg, pModuleSize, tAcc, tSC, i, tMaxJ, tResult
         if tResult is not empty then return tResult
      end if
   end repeat
   if tAcc["np"] > 0 then
      return tAcc["pat"][0]
   end if
   throw "NotFound: bottom right alignment pattern not found"
end apf_find

-- ===================== module: detector ================
-- =====================================================================
-- detector.lc - top-level detect: finders -> module size -> transform -> sample.
-- Port of ZXing Qrcode\Detector\Detector. Spec section 8.4.
-- Requires: qrCompat.lc, bitMatrix.lc, mathUtils.lc, resultPoint.lc,
--           perspectiveTransform.lc, gridSampler.lc, finderPatternFinder.lc,
--           alignmentPatternFinder.lc, version.lc.
--
-- dt_detect(image, hints) -> {["bits"] sampled square BitMatrix,
--                             ["points"] result points, ["dimension"]}.
-- The image is passed by value everywhere (copy-on-write, read-only).
-- NaN -> empty (sizeOfBlackWhiteBlackRun). Throws NotFound on failure.
-- =====================================================================

-- trace a black-white-black run from (fromX,fromY) toward (toX,toY); returns
-- the distance to the run end, or empty (NaN) if no B-W-B found. Mild Bresenham.
function dt_sizeOfBlackWhiteBlackRun pImg, pFromX, pFromY, pToX, pToY
   local tSteep, tTemp, tDx, tDy, tErr, tXstep, tYstep, tState, tXLimit
   local x, y, tRealX, tRealY, tFromX, tFromY, tToX, tToY, tPtA, tPtB
   put pFromX into tFromX
   put pFromY into tFromY
   put pToX into tToX
   put pToY into tToY
   put (abs(tToY - tFromY) > abs(tToX - tFromX)) into tSteep
   if tSteep then
      put tFromX into tTemp
      put tFromY into tFromX
      put tTemp into tFromY
      put tToX into tTemp
      put tToY into tToX
      put tTemp into tToY
   end if
   put abs(tToX - tFromX) into tDx
   put abs(tToY - tFromY) into tDy
   put (0 - (tDx div 2)) into tErr        -- ZXing: int error = -dx / 2 (integer)
   if tFromX < tToX then
      put 1 into tXstep
   else
      put -1 into tXstep
   end if
   if tFromY < tToY then
      put 1 into tYstep
   else
      put -1 into tYstep
   end if
   put 0 into tState
   put (tToX + tXstep) into tXLimit
   put tFromX into x
   put tFromY into y
   repeat while x <> tXLimit
      if tSteep then
         put y into tRealX
         put x into tRealY
      else
         put x into tRealX
         put y into tRealY
      end if
      put (tState = 1) into tPtA
      put bitMatrix_get(pImg, tRealX, tRealY) into tPtB
      if tPtA = tPtB then
         if tState = 2 then
            return mu_distance(x, y, tFromX, tFromY)
         end if
         add 1 to tState
      end if
      add tDy to tErr
      if tErr > 0 then
         if y = tToY then exit repeat
         add tYstep to y
         subtract tDx from tErr
      end if
      add tXstep to x
   end repeat
   if tState = 2 then
      return mu_distance((tToX + tXstep), tToY, tFromX, tFromY)
   end if
   return empty
end dt_sizeOfBlackWhiteBlackRun

-- B-W-B run measured both ways from a finder centre, minus the double-counted
-- centre pixel. NaN propagates (matches PHP: result += run2; return result-1).
function dt_sizeOfBWBRunBothWays pImg, pFromX, pFromY, pToX, pToY
   local tResult, tScale, tOtherToX, tOtherToY, tImgW, tImgH, tResult2
   put bitMatrix_getWidth(pImg) into tImgW
   put bitMatrix_getHeight(pImg) into tImgH
   put dt_sizeOfBlackWhiteBlackRun(pImg, pFromX, pFromY, pToX, pToY) into tResult
   put 1 into tScale
   put (pFromX - (pToX - pFromX)) into tOtherToX
   if tOtherToX < 0 then
      put (pFromX / (pFromX - tOtherToX)) into tScale
      put 0 into tOtherToX
   else if tOtherToX >= tImgW then
      put (((tImgW - 1) - pFromX) / (tOtherToX - pFromX)) into tScale
      put (tImgW - 1) into tOtherToX
   end if
   put trunc(pFromY - ((pToY - pFromY) * tScale)) into tOtherToY
   put 1 into tScale
   if tOtherToY < 0 then
      put (pFromY / (pFromY - tOtherToY)) into tScale
      put 0 into tOtherToY
   else if tOtherToY >= tImgH then
      put (((tImgH - 1) - pFromY) / (tOtherToY - pFromY)) into tScale
      put (tImgH - 1) into tOtherToY
   end if
   put trunc(pFromX + ((tOtherToX - pFromX) * tScale)) into tOtherToX
   put dt_sizeOfBlackWhiteBlackRun(pImg, pFromX, pFromY, tOtherToX, tOtherToY) into tResult2
   if (tResult is empty) or (tResult2 is empty) then return empty
   return ((tResult + tResult2) - 1)
end dt_sizeOfBWBRunBothWays

function dt_calculateModuleSizeOneWay pImg, pPattern, pOther
   local tEst1, tEst2
   put dt_sizeOfBWBRunBothWays(pImg, trunc(pPattern["x"]), trunc(pPattern["y"]), trunc(pOther["x"]), trunc(pOther["y"])) into tEst1
   put dt_sizeOfBWBRunBothWays(pImg, trunc(pOther["x"]), trunc(pOther["y"]), trunc(pPattern["x"]), trunc(pPattern["y"])) into tEst2
   -- NaN is empty in this port and must never reach arithmetic: both runs
   -- empty -> empty (upstream: NaN propagates and ends in NotFound)
   if (tEst1 is empty) and (tEst2 is empty) then return empty
   if tEst1 is empty then return (tEst2 / 7)
   if tEst2 is empty then return (tEst1 / 7)
   return ((tEst1 + tEst2) / 14)
end dt_calculateModuleSizeOneWay

function dt_calculateModuleSize pImg, pTL, pTR, pBL
   local tA, tB
   put dt_calculateModuleSizeOneWay(pImg, pTL, pTR) into tA
   put dt_calculateModuleSizeOneWay(pImg, pTL, pBL) into tB
   if (tA is empty) or (tB is empty) then
      throw "NotFound: module size could not be measured (no black-white-black run)"
   end if
   return ((tA + tB) / 2)
end dt_calculateModuleSize

-- dimension (modules per side) from finder distances + module size; snap %4==1
function dt_computeDimension pTL, pTR, pBL, pModuleSize
   local tTltr, tTlbl, tDim, tMod
   put mu_round(rp_distance(pTL, pTR) / pModuleSize) into tTltr
   put mu_round(rp_distance(pTL, pBL) / pModuleSize) into tTlbl
   -- ZXing (Java) Detector.computeDimension: INTEGER division of the two
   -- rounded module counts, then snap to 4k+1 - and since ZXing 3.4 a residue
   -- of 3 is recovered with dimension -= 2 rather than thrown (the PHP port
   -- rounds a float and throws on 3; this port follows current ZXing here).
   put (((tTltr + tTlbl) div 2) + 7) into tDim
   put (tDim bitAnd 3) into tMod
   if tMod = 0 then
      add 1 to tDim
   else if tMod = 2 then
      subtract 1 from tDim
   else if tMod = 3 then
      subtract 2 from tDim
   end if
   return tDim
end dt_computeDimension

-- locate the alignment pattern in a guessed region (delegates to apf_find)
function dt_findAlignmentInRegion pImg, pOverallEstModuleSize, pEstAlignX, pEstAlignY, pAllowanceFactor
   local tAllowance, tLeftX, tRightX, tTopY, tBottomY, tImgW, tImgH
   put trunc(pAllowanceFactor * pOverallEstModuleSize) into tAllowance
   put bitMatrix_getWidth(pImg) into tImgW
   put bitMatrix_getHeight(pImg) into tImgH
   put max(0, (pEstAlignX - tAllowance)) into tLeftX
   put min((tImgW - 1), (pEstAlignX + tAllowance)) into tRightX
   if (tRightX - tLeftX) < (pOverallEstModuleSize * 3) then
      throw "NotFound: alignment area too small (x)"
   end if
   put max(0, (pEstAlignY - tAllowance)) into tTopY
   put min((tImgH - 1), (pEstAlignY + tAllowance)) into tBottomY
   if (tBottomY - tTopY) < (pOverallEstModuleSize * 3) then
      throw "NotFound: alignment area too small (y)"
   end if
   return apf_find(pImg, tLeftX, tTopY, (tRightX - tLeftX), (tBottomY - tTopY), pOverallEstModuleSize)
end dt_findAlignmentInRegion

-- build the sampling transform from the 3 (or 4) reference points
function dt_createTransform pTL, pTR, pBL, pAlign, pDimension
   local tDimMinus3, tBRX, tBRY, tSrcBRX, tSrcBRY
   put (pDimension - 3.5) into tDimMinus3
   if pAlign is not empty then
      put pAlign["x"] into tBRX
      put pAlign["y"] into tBRY
      put (tDimMinus3 - 3) into tSrcBRX
      put tSrcBRX into tSrcBRY
   else
      put ((pTR["x"] - pTL["x"]) + pBL["x"]) into tBRX
      put ((pTR["y"] - pTL["y"]) + pBL["y"]) into tBRY
      put tDimMinus3 into tSrcBRX
      put tDimMinus3 into tSrcBRY
   end if
   return pt_quadrilateralToQuadrilateral(3.5, 3.5, tDimMinus3, 3.5, tSrcBRX, tSrcBRY, 3.5, tDimMinus3, \
      pTL["x"], pTL["y"], pTR["x"], pTR["y"], tBRX, tBRY, pBL["x"], pBL["y"])
end dt_createTransform

-- top-level detect; returns {["bits"],["points"],["dimension"]} or throws
function dt_detect pImg, pHints
   local tInfo, tTL, tTR, tBL, tModuleSize, tDimension, tProvVer, tModulesBetween
   local tAlignCenters, tAlign, tBRX, tBRY, tCorr, tEstAX, tEstAY, ii, e, tAlignErr
   local tTransform, tBits, tPoints, tResult
   put fpf_find(pImg, pHints) into tInfo
   put tInfo["tl"] into tTL
   put tInfo["tr"] into tTR
   put tInfo["bl"] into tBL
   put dt_calculateModuleSize(pImg, tTL, tTR, tBL) into tModuleSize
   if tModuleSize < 1 then
      throw "NotFound: module size " & tModuleSize & " < 1.0"
   end if
   put dt_computeDimension(tTL, tTR, tBL, tModuleSize) into tDimension
   put ver_getProvisionalVersionForDimension(tDimension) into tProvVer
   put (ver_getDimensionForVersion(tProvVer) - 7) into tModulesBetween
   put empty into tAlign
   put ver_getAlignmentCenters(tProvVer) into tAlignCenters
   if tAlignCenters is not empty then
      put ((tTR["x"] - tTL["x"]) + tBL["x"]) into tBRX
      put ((tTR["y"] - tTL["y"]) + tBL["y"]) into tBRY
      put (1 - (3 / tModulesBetween)) into tCorr
      -- ZXing truncates the estimate: int estAlignmentX = (int) (...)
      put trunc(tTL["x"] + (tCorr * (tBRX - tTL["x"]))) into tEstAX
      put trunc(tTL["y"] + (tCorr * (tBRY - tTL["y"]))) into tEstAY
      put 4 into ii
      put empty into tAlignErr
      repeat while ii <= 16
         try
            put dt_findAlignmentInRegion(pImg, tModuleSize, tEstAX, tEstAY, ii) into tAlign
            exit repeat
         catch e
            put empty into tAlign
            put e into tAlignErr
         end try
         -- ZXing/PHP catch ONLY NotFound here; anything else is a real error and
         -- must not be swallowed into "no alignment pattern" (re-thrown after
         -- the try - a throw inside a catch is lost on OXT, engine notes 3.2)
         if (tAlignErr is not empty) and (not (tAlignErr begins with "NotFound")) then
            throw tAlignErr
         end if
         put (ii * 2) into ii
      end repeat
   end if
   put dt_createTransform(tTL, tTR, tBL, tAlign, tDimension) into tTransform
   put gs_sampleGrid(pImg, tDimension, tDimension, tTransform) into tBits
   put tBL into tPoints[0]
   put tTL into tPoints[1]
   put tTR into tPoints[2]
   if tAlign is not empty then
      put tAlign into tPoints[3]
   end if
   put tBits into tResult["bits"]
   put tPoints into tResult["points"]
   put tDimension into tResult["dimension"]
   return tResult
end dt_detect

-- ===================== module: qrCodeReader ============
-- =====================================================================
-- qrCodeReader.lc - wire detector -> decoder; PURE_BARCODE fast path. Spec section 9.
-- Port of ZXing Qrcode\QRCodeReader. Requires: bitMatrix.lc, binaryBitmap.lc,
--   detector.lc, decoder.lc.
--
-- qcr_decode(binaryBitmap, hints) -> decoder result array (from dec_decode):
--   ["text"], ["bytes"], ["error"], ["ecLevel"], ["version"], ["mask"],
--   plus ["points"] from the detector (swapped for a mirrored symbol, as
--   ZXing does) and ["inverted"] = true when the ALSO_INVERTED retry won.
--   Never throws: NotFound / Format / Checksum all arrive in ["error"].
-- =====================================================================

-- Decode one binarized bitmap. Callers run `binaryBitmap_ensureMatrix` on
-- THEIR bitmap variable first so the black matrix is binarized once and cached
-- where it persists (a function receives the bitmap by value - the proven shape
-- - so a cache filled here would live in a discarded copy; ensureMatrix below is
-- then a no-op). With the ALSO_INVERTED hint a failed decode is retried on the
-- inverted matrix (ZXing MultiFormatReader: image.getBlackMatrix().flip(), then
-- decode again) - a white-on-black symbol; such a result carries
-- ["inverted"] = true. Never throws: failures arrive in ["error"] (a detector
-- NotFound included).
function qcr_decode pBitmap, pHints
   local tResult, tInverted, tBits, e
   binaryBitmap_ensureMatrix pBitmap
   try
      put qcr_decodeMatrix(pBitmap["matrix"], pHints) into tResult
   catch e
      put empty into tResult
      put e into tResult["error"]
   end try
   if (tResult["error"] is not empty) and qr_hintFlag(pHints, "ALSO_INVERTED") then
      put pBitmap["matrix"] into tBits
      bitMatrix_flipAll tBits
      put tBits into pBitmap["matrix"]
      try
         put qcr_decodeMatrix(pBitmap["matrix"], pHints) into tInverted
      catch e
         put empty into tInverted
         put e into tInverted["error"]
      end try
      if tInverted["error"] is empty then
         put true into tInverted["inverted"]
         return tInverted
      end if
   end if
   return tResult
end qcr_decode

-- detect + decode one black matrix (ZXing QRCodeReader.decode). Throws NotFound
-- from the detector; Format/Checksum arrive in the result's ["error"].
function qcr_decodeMatrix pImage, pHints
   local tBits, tDetectorResult, tDecoderResult, tPoints, tSwap
   if qr_hintFlag(pHints, "PURE_BARCODE") then
      put qcr_extractPureBits(pImage) into tBits
      put dec_decode(tBits) into tDecoderResult
   else
      put dt_detect(pImage, pHints) into tDetectorResult
      put dec_decode(tDetectorResult["bits"]) into tDecoderResult
      put tDetectorResult["points"] into tPoints
      if tDecoderResult["mirrored"] is true then
         -- ZXing QRCodeDecoderMetaData.applyMirroredCorrection: a mirrored
         -- symbol's bottom-left and top-right swap; top-left and alignment stay
         put tPoints[0] into tSwap
         put tPoints[2] into tPoints[0]
         put tSwap into tPoints[2]
      end if
      put tPoints into tDecoderResult["points"]
   end if
   return tDecoderResult
end qcr_decodeMatrix

-- estimate module size by counting transitions along the top-left diagonal
function qcr_moduleSize pLeftTopBlack, pImage
   local tHeight, tWidth, x, y, tInBlack, tTransitions
   put bitMatrix_getHeight(pImage) into tHeight
   put bitMatrix_getWidth(pImage) into tWidth
   put pLeftTopBlack[0] into x
   put pLeftTopBlack[1] into y
   put true into tInBlack
   put 0 into tTransitions
   repeat while (x < tWidth) and (y < tHeight)
      if tInBlack <> bitMatrix_get(pImage, round(x), round(y)) then
         add 1 to tTransitions
         if tTransitions = 5 then exit repeat
         put (not tInBlack) into tInBlack
      end if
      add 1 to x
      add 1 to y
   end repeat
   if (x = tWidth) or (y = tHeight) then
      throw "NotFound: pure barcode module size not found"
   end if
   return ((x - pLeftTopBlack[0]) / 7)
end qcr_moduleSize

-- fast path for a clean, unrotated, bordered "pure" QR image
function qcr_extractPureBits pImage
   local tLeftTop, tRightBottom, tModuleSize, tTop, tBottom, tLeft, tRight
   local tMatrixWidth, tMatrixHeight, tNudge, tNudgedRight, tNudgedDown
   local tBits, y, x, tIOffset
   put bitMatrix_getTopLeftOnBit(pImage) into tLeftTop
   put bitMatrix_getBottomRightOnBit(pImage) into tRightBottom
   if (tLeftTop is empty) or (tRightBottom is empty) then
      throw "NotFound: top left or bottom right on bit not found"
   end if
   put qcr_moduleSize(tLeftTop, pImage) into tModuleSize
   put tLeftTop[1] into tTop
   put tRightBottom[1] into tBottom
   put tLeftTop[0] into tLeft
   put tRightBottom[0] into tRight
   if (tLeft >= tRight) or (tTop >= tBottom) then
      throw "NotFound: pure barcode sanity violated"
   end if
   if (tBottom - tTop) <> (tRight - tLeft) then
      -- bottom-right module wasn't black; assume square, use height as width
      put (tLeft + (tBottom - tTop)) into tRight
      -- ZXing (Java) guards the assumption; the PHP port would sample off-image
      if tRight >= bitMatrix_getWidth(pImage) then
         throw "NotFound: pure barcode square assumption runs off the image"
      end if
   end if
   put round(((tRight - tLeft) + 1) / tModuleSize) into tMatrixWidth
   put round(((tBottom - tTop) + 1) / tModuleSize) into tMatrixHeight
   if (tMatrixWidth <= 0) or (tMatrixHeight <= 0) then
      throw "NotFound: matrix dimensions <= 0"
   end if
   if tMatrixHeight <> tMatrixWidth then
      throw "NotFound: matrix not square"
   end if
   put trunc(tModuleSize / 2) into tNudge
   add tNudge to tTop
   add tNudge to tLeft
   put ((tLeft + trunc((tMatrixWidth - 1) * tModuleSize)) - tRight) into tNudgedRight
   if tNudgedRight > 0 then
      if tNudgedRight > tNudge then
         throw "NotFound: nudge too far right"
      end if
      subtract tNudgedRight from tLeft
   end if
   put ((tTop + trunc((tMatrixHeight - 1) * tModuleSize)) - tBottom) into tNudgedDown
   if tNudgedDown > 0 then
      if tNudgedDown > tNudge then
         throw "NotFound: nudge too far down"
      end if
      subtract tNudgedDown from tTop
   end if
   put bitMatrix_new(tMatrixWidth, tMatrixHeight) into tBits
   repeat with y = 0 to (tMatrixHeight - 1)
      put (tTop + trunc(y * tModuleSize)) into tIOffset
      repeat with x = 0 to (tMatrixWidth - 1)
         if bitMatrix_get(pImage, (tLeft + trunc(x * tModuleSize)), tIOffset) then
            bitMatrix_set tBits, x, y
         end if
      end repeat
   end repeat
   return tBits
end qcr_extractPureBits

-- ===================== module: qrReader ================
-- =====================================================================
-- qrReader.lc - public API: image bytes -> luminance -> binarize -> detect ->
-- decode. Spec section 9. Port of ZXing QrReader facade.
-- Requires: luminanceSource.lc, binaryBitmap.lc, qrCodeReader.lc (and the
--   whole decode stack they pull in).
--
-- Public surface:
--   qrDecodeFromData(imageBytes [,hints]) -> decoded text, or empty on failure
--   qrDecodeFromFile(path [,hints])       -> same, reading the file
--   qrDecodeResult(imageBytes [,hints])   -> rich result array with keys
--       text, bytes, points, ecLevel, version, mask, error
--   qrDecodeResultRobust(imageBytes [,hints [,maxDim]]) -> rich result array;
--       multi-strategy (hybrid+global x a resolution ladder) -- best for photos
--   qrLibraryVersion()                    -> the library version string
--
-- hints may be an xTalk array, or a comma list of "KEY" / "KEY=VALUE"
-- (e.g. "TRY_HARDER" or "NR_ALLOW_SKIP_ROWS=0"). A flag hint counts as SET when
-- present with any value other than false / 0 / empty / "no" / "off"
-- (qr_hintFlag), so "PURE_BARCODE", "PURE_BARCODE=1" and an array key holding
-- true all work. Failure contract: internal NotFound/Format/Checksum never
-- escape -- qrDecodeResult returns ["error"].
--
-- HOST HYGIENE: the two delimiter switches here are wrapped save/set/restore, so
-- the host app gets its itemDelimiter back whatever the engine's scoping of
-- that property (the xTalk Suite records it as global mutable state on OXT).
-- =====================================================================

-- the library version: a literal constant (constants must be literals), declared
-- here, above its only reader, in the module that ships the public API
constant kQrLibVersion = "0.2.0"

-- normalise hints to an array (pass-through if already one). We detect an
-- already-array argument via "the keys of" (empty for a non-array / empty
-- string), avoiding the "is an array" operator which is unexercised here.
function qr_parseHints pHints
   local tArr, i, tItem, tKey, tVal, tCount, tSavedDelim, tKeyLen
   if (the keys of pHints) is not empty then
      return pHints
   end if
   if pHints is empty then
      return tArr
   end if
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put the number of items of pHints into tCount
   repeat with i = 1 to tCount
      set the itemDelimiter to comma
      put (item i of pHints) into tItem
      if tItem is empty then next repeat
      if "=" is in tItem then
         -- split at the FIRST "=" only: "KEY=a=b" keeps the value "a=b"
         set the itemDelimiter to "="
         put (item 1 of tItem) into tKey
         put the number of chars of tKey into tKeyLen
         put char (tKeyLen + 2) to (the number of chars of tItem) of tItem into tVal
         put tVal into tArr[tKey]
      else
         put true into tArr[tItem]
      end if
   end repeat
   set the itemDelimiter to tSavedDelim
   return tArr
end qr_parseHints

-- is the flag hint pKey SET? Present, and not one of the "off" spellings.
-- (ZXing tests mere presence; PHP truthiness; the string form of a hint list
-- makes "KEY=0" / "KEY=no" natural, so those count as off.)
function qr_hintFlag pHints, pKey
   local v
   if not (pKey is among the lines of the keys of pHints) then return false
   put pHints[pKey] into v
   if v is empty then return false
   if v is false then return false
   if (v is "0") or (v is "no") or (v is "off") then return false
   return true
end qr_hintFlag

-- the library version (the literal kQrLibVersion in qrCompat.lc)
function qrLibraryVersion
   return kQrLibVersion
end qrLibraryVersion

-- rich result; never throws (NotFound/Format/Checksum surface via ["error"])
function qrDecodeResult pImageData, pHints
   local tHintsArr, tSource, tBitmap, tResult, e, tErr
   put qr_parseHints(pHints) into tHintsArr
   try
      put luminanceSource_newFromData(pImageData) into tSource
      put binaryBitmap_new(tSource) into tBitmap
      binaryBitmap_ensureMatrix tBitmap          -- binarize once, cached in OUR variable
      put qcr_decode(tBitmap, tHintsArr) into tResult
      return tResult
   catch e
      put e into tErr["error"]
      return tErr
   end try
end qrDecodeResult

-- ROBUST multi-strategy decode for real-world phone photos (glare, blur, slight
-- tilt, dense codes). The image is decoded to a raw pixel plane exactly ONCE
-- (the costly step), then a resolution LADDER of (downsample step, binarizer)
-- rungs is tried cheapest-first; the first that decodes wins. This is the path
-- the interactive scanner uses.
--
-- Why it helps where a single pass fails:
--   * Hybrid vs Global binarizer catch different failure modes -- hybrid's local
--     8x8 threshold handles uneven lighting/glare; the global histogram is a
--     better bet for low-contrast or evenly-lit frames where hybrid misfires.
--   * A higher-resolution retry recovers dense (v4+) codes whose thin modules
--     collapse under the aggressive nearest-neighbour downsample of the fast pass.
--
-- The ladder: the base cap pMaxDim (default 1200 px on the longer side) gives an
-- integer step; the finer rung is the ~1.33x cap's step when that is smaller,
-- else one step finer than the base (when the base step is above 1). Two caps
-- often map to the SAME step (any photo up to 1200 px is step 1 under both), so
-- the old fixed four-rung list repeated identical work on every failure; a rung
-- now runs only when it adds resolution, and the greyscale plane for a step is
-- built ONCE and shared by both binarizers (they only read it).
--
-- The result array carries ["strategy"] ("hybrid"/"global"), ["step"], ["procW"],
-- ["procH"] describing the attempt that produced it, and ["attempts"], a 0-based
-- list of every rung tried ({strategy, step, procW, procH, error}). On total
-- failure ["error"] is the FIRST rung's error (the most specific one: the hybrid
-- pass at the base scale) and ["attempts"] tells the rest.
-- NotFound/Format/Checksum never escape; failure surfaces via ["error"].
--
-- pMaxDim is the base (fast-pass) cap; omit for 1200. Hints pass straight
-- through (TRY_HARDER, ALSO_INVERTED, BINARY_MODE, NR_ALLOW_SKIP_ROWS, ...).
function qrDecodeResultRobust pImageData, pHints, pMaxDim
   local tHintsArr, tPlane, tBaseDim, tHiDim, tW, tH, tStepBase, tStepHi
   local tSteps, tNSteps, k, tStep, tSource, b, tBin, tBitmap, tResult
   local tFirst, tAttempts, tN, e, tErr
   put qr_parseHints(pHints) into tHintsArr

   if (pMaxDim is empty) or (pMaxDim <= 0) then
      put 1200 into tBaseDim
   else
      put pMaxDim into tBaseDim
   end if
   put trunc((tBaseDim * 4) / 3) into tHiDim     -- ~1.33x for the finer rung

   -- decode the image once; a decode failure here is terminal
   try
      put luminanceSource_decodeRawPlane(pImageData) into tPlane
   catch e
      put e into tErr["error"]
      return tErr
   end try
   put tPlane["width"] into tW
   put tPlane["height"] into tH

   -- plan the ladder in integer downsample steps (1 = full resolution)
   put luminanceSource_stepForDims(tW, tH, tBaseDim) into tStepBase
   put luminanceSource_stepForDims(tW, tH, tHiDim) into tStepHi
   put tStepBase into tSteps[0]
   put 1 into tNSteps
   if tStepHi < tStepBase then
      put tStepHi into tSteps[1]
      put 2 into tNSteps
   else if tStepBase > 1 then
      put (tStepBase - 1) into tSteps[1]
      put 2 into tNSteps
   end if

   put 0 into tN
   put empty into tFirst
   repeat with k = 0 to (tNSteps - 1)
      put tSteps[k] into tStep
      put luminanceSource_fromRawPlaneStep(tPlane, tStep) into tSource
      repeat with b = 0 to 1
         if b = 0 then
            put "hybrid" into tBin
         else
            put "global" into tBin
         end if
         put binaryBitmap_new(tSource, tBin) into tBitmap
         binaryBitmap_ensureMatrix tBitmap
         put qcr_decode(tBitmap, tHintsArr) into tResult      -- never throws
         put tBin into tResult["strategy"]
         put tStep into tResult["step"]
         put tSource["width"] into tResult["procW"]
         put tSource["height"] into tResult["procH"]
         put tBin into tAttempts[tN]["strategy"]
         put tStep into tAttempts[tN]["step"]
         put tSource["width"] into tAttempts[tN]["procW"]
         put tSource["height"] into tAttempts[tN]["procH"]
         put tResult["error"] into tAttempts[tN]["error"]
         add 1 to tN
         if tResult["error"] is empty then
            put tAttempts into tResult["attempts"]
            return tResult
         end if
         if tFirst is empty then put tResult into tFirst
      end repeat
   end repeat
   put tAttempts into tFirst["attempts"]
   return tFirst
end qrDecodeResultRobust

-- one-shot: decoded text on success, empty on any failure. With BINARY_MODE set
-- (hint), returns the raw decoded byte string verbatim (no charset decode) --
-- needed for binary payloads like the 256-byte ramp fixture (spec section 9).
function qrDecodeFromData pImageData, pHints
   local tRes, tHintsArr
   put qr_parseHints(pHints) into tHintsArr
   put qrDecodeResult(pImageData, tHintsArr) into tRes
   if tRes["error"] is not empty then
      return empty
   end if
   if qr_hintFlag(tHintsArr, "BINARY_MODE") then
      return tRes["bytes"]
   end if
   return tRes["text"]
end qrDecodeFromData

function qrDecodeFromFile pFilePath, pHints
   return qrDecodeFromData(url ("binfile:" & pFilePath), pHints)
end qrDecodeFromFile
-- <<< END EMBEDDED LIBRARIES <<<

-- ---- demo state ----------------------------------------------------------

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kQdUiVersion = "qr-kit2-3"
constant kQdWinW = 900
constant kQdWinH = 640
-- The sample keys, in the order the Samples tab shows them.
constant kQdSamples = "v1num,mirror,inverted,utf8,scale1,rot25,photo"
-- The preview box on the Decode tab (left, top, right, bottom): the loaded
-- image is scaled to fit inside it, aspect kept.
constant kQdPreviewBox = "48,170,228,350"
-- Every control this script names, DERIVED by tools/sync_demo_embeds.py
-- (--write regenerates it; --check refuses a stale list); the boot self-check
-- asserts each one exists, because a missing control is the "Chunk: error in
-- object expression" class and finding it at boot beats finding it on a click.
constant kQdScControls = "about:exp,about:h,about:hint,about:log,about:selfcheck,about:status,decode:alsoInverted,decode:binaryMode,decode:copy,decode:details,decode:hintCap,decode:imgInfo,decode:next,decode:open,decode:paste,decode:preview,decode:previewBox,decode:pureBarcode,decode:robust,decode:sec1,decode:sec1Line,decode:sec2,decode:sec2Line,decode:sec3,decode:sec3Line,decode:sec4,decode:sec4Line,decode:sec5,decode:sec5Line,decode:single,decode:status,decode:text,decode:tryHarder,pipe:cap,pipe:global,pipe:out,pipe:run,pipe:sec,pipe:secLine,samples:cap,samples:inverted,samples:mirror,samples:out,samples:photo,samples:rot25,samples:runAll,samples:scale1,samples:sec,samples:secLine,samples:utf8,samples:v1num,ui:panel,ui:tabAbout,ui:tabDecode,ui:tabPipe,ui:tabSamples,uiBand,uiFooter,uiStatus,uiTitle"

local sQdTab            -- active tab: decode | pipe | samples | about
local sQdImage          -- the image bytes last loaded (file, paste, drop or sample)
local sQdImageName      -- where they came from, for the status lines
local sQdTryHarder      -- the hint toggles (script-managed checkboxes)
local sQdAlsoInverted
local sQdPureBarcode
local sQdBinaryMode
local sQdPipeGlobal     -- Pipeline tab: use the global binarizer instead of hybrid
local sQdLastText       -- the last decoded text, for the Copy button
local sQdPass           -- Samples tab run counters
local sQdFail

-- ==== SUITE UI KIT v2 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg = "240,242,246"
constant kUiCard = "255,255,255"
constant kUiCardLine = "225,229,236"
constant kUiAccent = "44,90,160"
constant kUiAccentText = "255,255,255"
constant kUiAccentSub = "199,216,241"
constant kUiInk = "28,34,46"
constant kUiInkSoft = "95,104,118"
constant kUiMuted = "138,146,158"
constant kUiOk = "23,128,63"
constant kUiWarn = "150,110,40"
constant kUiBad = "176,58,46"
constant kUiFieldLine = "203,210,222"
constant kUiCodeBg = "244,246,250"
constant kUiCodeLine = "210,217,229"

-- The platform's own terminal face for codes, keys, tables and logs, so
-- the monospace surfaces look native instead of typewriter-Courier. A
-- missing face substitutes the engine default - a soft, safe failure.
function uiMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end uiMonoFont

-- The window chrome every adopter shares: stack size, page ground, the
-- title band, and the one status line under it (write it with uiStatus).
-- pBandH is optional (default 30); a taller band leaves room for an
-- adopter's tagline or status pill, placed by the adopter.
command uiChrome pTitle, pWidth, pHeight, pBandH
   local tFH
   if pBandH is empty then
      put 30 into pBandH
   end if
   set the width of this stack to pWidth
   set the height of this stack to pHeight
   set the backgroundColor of this card to kUiBg
   set the title of this stack to pTitle
   uiGfx "uiBand", "0,0," & pWidth & "," & pBandH
   set the style of graphic "uiBand" to "rectangle"
   set the filled of graphic "uiBand" to true
   set the backgroundColor of graphic "uiBand" to kUiAccent
   set the lineSize of graphic "uiBand" to 0
   uiLabel "uiTitle", "  " & pTitle, "0,0," & pWidth & "," & pBandH, 15
   set the foregroundColor of field "uiTitle" to kUiAccentText
   set the textStyle of field "uiTitle" to "bold"
   -- center the title on the band midline by MEASURED height (never guess
   -- font metrics - the family's OXT passes clipped hand-sized labels)
   put the formattedHeight of field "uiTitle" into tFH
   if tFH > 0 and tFH < pBandH then
      set the height of field "uiTitle" to tFH
      set the top of field "uiTitle" to ((pBandH - tFH) div 2)
   end if
   uiLabel "uiStatus", empty, "16," & (pBandH + 4) & "," & (pWidth - 16) & "," & (pBandH + 22), 11
end uiChrome

-- The status line, colored by what it reports: "ok", "warn", "bad", or
-- anything else for neutral/muted. Demos route probe results through this
-- so a stack that cannot run says so in red, at the top, immediately.
command uiStatus pText, pKind
   -- PIN THE STACK, THEN CHECK THE FIELD EXISTS. Both halves were missing and
   -- both are load-bearing on a TIMER-driven call.
   --
   -- An unqualified `field "uiStatus"` resolves against the DEFAULTSTACK, not
   -- against the stack whose script is running. Inside openStack those are the
   -- same thing, which is why every demo's startup status line always worked.
   -- A handler arriving from `send ... in` has no such guarantee: with a second
   -- stack in front, the write lands in the wrong stack or resolves to nothing.
   --
   -- THE PIN RESTS ON THE DOCUMENTED RESOLUTION RULE, NOT ON A THROW WE SAW.
   -- This comment used to cite enet-lan-chat's once-a-second dashboard throwing
   -- "Chunk: error in object expression" REPEATEDLY on 2026-08-18, and dht-chat
   -- hiding the same fault behind a guard. Neither half held up: that throw was
   -- the ARGUMENT at the call site (`the number of keys of sPeers`, which does
   -- not parse - OXT-ENGINE-NOTES 1.7) and never reached uiStatus at all, and
   -- the guard credited to the kit was dht-chat's own wxSetStatus wrapper - the
   -- master had no existence check until the same commit that added this pin.
   -- What a guarded call site WOULD do if the defaultStack diverged is fail
   -- silently, which is the argument for a gate rather than for more guards.
   -- See OXT-ENGINE-NOTES 5.3, now classed DOCUMENTED.
   --
   -- The pin is holde-em's idiom, engine-proven there, and its comment names
   -- this exact hazard. The existence check stays as well: a demo may call the
   -- status line before its chrome is built, and a cosmetic line must never
   -- take down a poll chain.
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      exit uiStatus
   end if
   put pText into field "uiStatus"
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kUiOk
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kUiWarn
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kUiBad
   else
      set the foregroundColor of field "uiStatus" to kUiInkSoft
   end if
end uiStatus

-- A static caption at a FIXED rect (idempotent, borderless, transparent).
-- Use uiWrap instead when the text may wrap or the exact height matters.
command uiLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the threeD of field pName to false
   set the textSize of field pName to pSize
   set the foregroundColor of field pName to kUiInk
   put pText into field pName
end uiLabel

-- A caption FIT to its measured text height (top pinned). The fit does
-- double duty: it prevents clipping (hand-sized rects clipped text on a
-- real Windows pass), and it makes `the height of field` equal the TEXT
-- height, which midline centering relies on. GUARD: only resize on a sane
-- measurement - a 0/blank formattedHeight (possible before the window is
-- fully realized) would collapse the label. Empty labels are skipped
-- (they receive their text later).
command uiWrap pName, pText, pRect, pSize
   local tOldDelim, tTop, tFH
   uiLabel pName, pText, pRect, pSize
   if pText is not empty then
      put the itemDelimiter into tOldDelim
      set the itemDelimiter to comma
      put item 2 of pRect into tTop
      set the itemDelimiter to tOldDelim
      put the formattedHeight of field pName into tFH
      if tFH > 0 then
         set the height of field pName to tFH
         set the top of field pName to tTop
      end if
   end if
end uiWrap

-- A small, muted caption (hints, toggle descriptions, empty states).
command uiCap pName, pText, pRect
   uiWrap pName, pText, pRect, 10
   set the foregroundColor of field pName to kUiMuted
end uiCap

-- A numbered bold section header with a hairline divider placed below the
-- label's ACTUAL (fit-to-text) bottom, so it tracks the real header
-- height on any platform's line metrics.
command uiSection pName, pText, pRect
   local tOldDelim, tL, tR, tB
   uiWrap pName, pText, pRect, 13
   set the textStyle of field pName to "bold"
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 1 of pRect into tL
   put item 3 of pRect into tR
   set the itemDelimiter to tOldDelim
   put the bottom of field pName into tB
   uiGfx (pName & "Line"), (tL & comma & (tB + 1) & comma & tR & comma & (tB + 2))
   set the style of graphic (pName & "Line") to "rectangle"
   set the filled of graphic (pName & "Line") to true
   set the backgroundColor of graphic (pName & "Line") to kUiCardLine
   set the lineSize of graphic (pName & "Line") to 0
end uiSection

-- A one-line entry field, mono and flat ("modern input" chrome instead of
-- the engine's sunken-3D default), because hex, addresses and paths are
-- what this suite's demos edit.
command uiInput pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to false
   set the traversalOn of field pName to true
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiFieldLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   -- 4-item margins form ONLY: OXT ignored the single-number form on a
   -- real engine pass
   set the margins of field pName to "6,6,6,6"
   set the textSize of field pName to 11
   set the textFont of field pName to uiMonoFont()
end uiInput

-- A read-only output/log area: mono, flat, scrolling, hairline-bordered.
command uiArea pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiCardLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   set the margins of field pName to "6,6,6,6"
   set the vScrollbar of field pName to true
   set the textSize of field pName to 10
   set the textFont of field pName to uiMonoFont()
end uiArea

-- A row-selectable table: uiArea plus list behavior and tab stops
-- ("230,340"-style comma lists). Pair it with a uiLabel header carrying
-- the same tabStops, set by the adopter.
command uiTable pName, pRect, pTabStops
   uiArea pName, pRect
   set the listBehavior of field pName to true
   if pTabStops is not empty then
      set the tabStops of field pName to pTabStops
   end if
end uiTable

command uiButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end uiButton

-- A script-managed checkbox: autoHilite OFF because the family drives
-- toggle state from script locals (a mode the environment cannot honour
-- must never stay silently armed - the quickshare pill lesson), so the
-- hilite is set explicitly by the adopter's state machine.
command uiCheckbox pName, pLabel, pRect
   uiButton pName, pLabel, pRect
   set the style of button pName to "checkbox"
   set the autoHilite of button pName to false
end uiCheckbox

-- Create-or-reuse a named graphic: the chrome layer (cards, pills,
-- dividers, drop targets). Created BEFORE the controls that sit on it, so
-- it stays behind them in z-order. roundRect + antialiased by default;
-- callers restyle.
command uiGfx pName, pRect
   if there is no graphic pName then
      create graphic
      set the name of the last graphic to pName
   end if
   set the rect of graphic pName to pRect
   set the style of graphic pName to "roundRect"
   set the antialiased of graphic pName to true
end uiGfx

-- A dashboard card: a rounded, hairline-bordered, softly shadowed panel
-- placed BEHIND a group of controls. It only groups visually; clicks on
-- it fall through to the adopter's `default: pass mouseUp`.
command uiPanel pName, pRect
   local tShadow, tErr
   uiGfx pName, pRect
   set the roundRadius of graphic pName to 14
   set the filled of graphic pName to true
   set the backgroundColor of graphic pName to kUiCard
   set the lineSize of graphic pName to 1
   -- a graphic strokes its outline in the foregroundColor; borderColor is
   -- set too so whichever the engine honours, the hairline lands
   set the foregroundColor of graphic pName to kUiCardLine
   set the borderColor of graphic pName to kUiCardLine
   -- soft drop shadow is an LC-9-era feature, so it is a PURE
   -- enhancement: an engine without it just skips it (the try) and the
   -- hairline still separates the card from the page
   try
      put "90,98,114" into tShadow["color"]
      put 30 into tShadow["opacity"]
      put 10 into tShadow["size"]
      put 0 into tShadow["spread"]
      put 2 into tShadow["distance"]
      put 90 into tShadow["angle"]
      set the dropShadow of graphic pName to tShadow
   catch tErr
   end try
end uiPanel

-- A status pill: rounded chip + centered label, colored by state kind -
-- "ok" green, "wait" amber, "bad" red, anything else the muted on-band
-- blue. The adopter repaints it from ONE place so its handlers cannot
-- disagree about the colors (the nocloud Tor-pill discipline).
command uiPill pName, pText, pRect, pKind
   local tOldDelim, tTop, tBot, tFH
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 2 of pRect into tTop
   put item 4 of pRect into tBot
   set the itemDelimiter to tOldDelim
   uiGfx (pName & "Bg"), pRect
   set the roundRadius of graphic (pName & "Bg") to (tBot - tTop)
   set the filled of graphic (pName & "Bg") to true
   set the lineSize of graphic (pName & "Bg") to 0
   if pKind is "ok" then
      set the backgroundColor of graphic (pName & "Bg") to "205,240,214"
   else if pKind is "wait" then
      set the backgroundColor of graphic (pName & "Bg") to "250,240,199"
   else if pKind is "bad" then
      set the backgroundColor of graphic (pName & "Bg") to "243,215,213"
   else
      set the backgroundColor of graphic (pName & "Bg") to "31,64,116"
   end if
   uiLabel pName, pText, pRect, 10
   set the textAlign of field pName to "center"
   if pKind is "ok" then
      set the foregroundColor of field pName to "22,101,52"
   else if pKind is "wait" then
      set the foregroundColor of field pName to "133,98,14"
   else if pKind is "bad" then
      set the foregroundColor of field pName to "135,44,38"
   else
      set the foregroundColor of field pName to kUiAccentSub
   end if
   -- center the label on the chip midline by measured height
   put the formattedHeight of field pName into tFH
   if tFH > 0 and tFH < (tBot - tTop) then
      set the height of field pName to tFH
      set the top of field pName to (tTop + ((tBot - tTop - tFH) div 2))
   end if
end uiPill

-- Click-to-copy feedback: flash the button's label to "Copied!" for
-- 1200 ms, then restore the real label (stashed in uRealLabel).
command uiCopyFlash pBtn
   if there is no button pBtn then
      exit uiCopyFlash
   end if
   if the uRealLabel of button pBtn is empty then
      set the uRealLabel of button pBtn to the label of button pBtn
   end if
   set the label of button pBtn to "Copied!"
   send ("uiCopyFlashReset" && quote & pBtn & quote) to me in 1200 milliseconds
end uiCopyFlash

command uiCopyFlashReset pBtn
   -- Pinned for the same reason uiStatus is: this one arrives 1200ms later by
   -- `send`, so the defaultStack is whatever is current THEN, not the stack
   -- that flashed the button. Its existence guard means the failure is silent
   -- rather than loud - the label just never comes back, or comes back on
   -- another stack's button - which is why it needed finding rather than
   -- reporting itself.
   set the defaultStack to the short name of this stack
   if there is no button pBtn then
      exit uiCopyFlashReset
   end if
   if the uRealLabel of button pBtn is not empty then
      set the label of button pBtn to the uRealLabel of button pBtn
   end if
end uiCopyFlashReset

-- The honesty/custody footer every demo carries: what the stack is, what
-- it is not, and its engine-evidence state.
command uiFooter pText, pRect
   uiWrap "uiFooter", pText, pRect, 11
   set the textStyle of field "uiFooter" to "italic"
   set the foregroundColor of field "uiFooter" to kUiMuted
end uiFooter
-- ---- contextual menus -------------------------------------------------------
--
-- A RIGHT-CLICK MENU, as one hidden popup button per menu.
--
-- The engine's contextual menu is a BUTTON whose style is "menu" and whose
-- menuMode is "popup": its text is the item list, one per line, `popup`
-- shows it at a point, and choosing an item sends `menuPick` with the item's
-- LABEL. The button needs no script - with no handler of its own the message
-- walks the hierarchy and arrives at the card and then the stack, which is
-- where an adopter's router already lives.
--
-- OPT-IN, AND THAT IS DELIBERATE. This block is carried byte-identical by
-- every demo in the suite, so a kit that BUILT a menu would change eighteen
-- stacks to serve one. Nothing here runs unless an adopter calls
-- uiContextMenu, and a demo that never does is unchanged in behaviour.
--
-- NONE OF THIS HAS RUN ON AN ENGINE. `popup`, `menuMode` and `menuPick` are
-- documented LiveCode and OpenXTalk is a fork of it, but this suite has never
-- exercised a menu and the headless runners model no mouse button at all - so
-- an adopter's right-click handler belongs in a `try`, and losing the menu
-- must never cost the ordinary click. uiPopupMenu answers whether it worked
-- rather than throwing, so the caller can decide.

command uiContextMenu pName, pItems
   -- One hidden popup button, created once and refilled on every call so a
   -- menu can change with the screen it belongs to. The rect is small and
   -- inside the window because a stack's controls are measured by
   -- tools/check-stack-size.py whether they are visible or not.
   if there is no button pName then
      -- THE KIT'S OWN IDIOM, and not `create button pName`. Every other
      -- builder in this block creates the control unnamed and then names the
      -- last one, which is the spelling the family's headless runners model
      -- and the one every adopter has already been through an engine with.
      create button
      set the name of the last button to pName
   end if
   set the style of button pName to "menu"
   set the menuMode of button pName to "popup"
   set the text of button pName to pItems
   set the rect of button pName to "2,2,18,18"
   set the visible of button pName to false
end uiContextMenu

function uiPopupMenu pName
   -- WHICH menu, recorded before it opens. menuPick carries the item's label
   -- and nothing else, so an adopter with two menus would otherwise have to
   -- keep every label in the stack globally unique - a constraint that is
   -- invisible until the day two screens both want "Copy".
   --
   -- Answers true or false rather than throwing: on an engine without popup
   -- menus the right thing is for the click to do nothing, not for the
   -- adopter's mouseDown to die.
   local tError
   if there is no button pName then
      return false
   end if
   set the uUiMenu of this stack to pName
   try
      popup button pName at the clickLoc
   catch tError
      set the uUiMenu of this stack to empty
      return false
   end try
   return true
end uiPopupMenu

function uiMenuSource
   -- The name of the menu the last menuPick came from.
   return the uUiMenu of this stack
end uiMenuSource

-- ==== SUITE UI KIT v2 END ====

-- ==== DEMO SELF-CHECK v1 BEGIN (verbatim copy; master: tools/demo-selfcheck.livecodescript; gate: tools/check-demo-selfcheck-drift.py) ====
-- The sentinel is a CONSTANT so the probe compares against one spelling; a
-- literal repeated at the write and the read is a check that can pass while
-- disagreeing with itself.
constant kScProbe = "self-check: delayed write reached the status line"
local sScLines          -- the whole block, kept so a Copy button has something
local sScPassed, sScFailed, sScSkipped
local sScLogField       -- the adopting demo's own log field, set by scBegin

command scBegin pLogField
   put pLogField into sScLogField
   put empty into sScLines
   put 0 into sScPassed
   put 0 into sScFailed
   put 0 into sScSkipped
   scLine "== boot self-check (nothing is hosted, connected, or bound) =="
end scBegin

-- Each line is LOGGED as it is made, not accumulated and flushed at the end.
-- The first draft did both - a flush after the synchronous half and another
-- after the probe - which printed every synchronous line twice.
command scLine pText
   put pText & return after sScLines
   -- pin the stack: scFinish reaches here from a `send ... in` tick, and the
   -- field is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sScLogField is empty or there is no field sScLogField then
      exit scLine
   end if
   put pText & return after field sScLogField
   set the vscroll of field sScLogField to the formattedHeight of field sScLogField
end scLine

command scAssert pName, pOk
   if pOk then
      add 1 to sScPassed
      scLine "PASS  " & pName
   else
      add 1 to sScFailed
      scLine "FAIL  " & pName
   end if
end scAssert

-- SKIP, never FAIL, for an absent extension: a missing member is an
-- environment, and only a present-and-broken member is a defect.
command scSkip pName, pReason
   add 1 to sScSkipped
   scLine "SKIP  " & pName & " (" & pReason & ")"
end scSkip

-- An empty value prints as nothing, which reads as a missing check rather than
-- an answer of empty; every observed value in a self-check goes through here.
-- This is the playLoudness lesson (OXT-ENGINE-NOTES 5.4) as a helper: a check
-- that reports only its own name costs a whole engine pass to diagnose.
function scShow pValue
   if pValue is empty then
      return "empty"
   end if
   return pValue
end scShow

-- Returns the comma-list of control names in pList that do not exist, or empty.
-- The adopter passes EVERY control name its own script references, derived from
-- the source rather than hand-picked: a missing control is not cosmetic, it is
-- the "Chunk: error in object expression" class, and finding it at boot beats
-- finding it when somebody clicks.
function scMissing pList
   local tName, tMissing, tC, tFound
   set the defaultStack to the short name of this stack
   repeat for each item tName in pList
      -- ALL FOUR CONTROL TYPES. The kit builds fields (uiLabel/uiWrap/uiCap/
      -- uiSection/uiInput/uiArea/uiTable), buttons (uiButton/uiCheckbox) AND
      -- GRAPHICS (uiGfx/uiPanel/uiPill). The first version of this asked only
      -- about fields and buttons, so every uiPill a demo builds - the Tor
      -- pills in both Quick Shares, for one - reported as a missing control on
      -- a stack where it exists.
      --
      -- AND IMAGES (2026-08-31), for the same reason one step further out. A
      -- demo may build a control the KIT does not: coinxt's wallet paints a
      -- QR into an image, which is the only way a BMP this family builds
      -- becomes something a phone can read. Registered and built, it reported
      -- as missing - found by coinxt/tools/check-wallet-boot.py, which boots
      -- the stack headlessly, so this one cost no engine time. The lesson is
      -- the one this block already carries twice: the list of types a demo
      -- can build is not the list of types the KIT builds.
      --
      -- AND EVERY CARD (2026-08-29). Unqualified `there is a field X` answers
      -- for the CURRENT card only (engine notes 5.6) - OBSERVED when
      -- riptide's five-card boot reported all 63 off-card controls missing
      -- from a stack where every one existed. A single-card demo walks its
      -- one card here, exactly the old behaviour.
      put false into tFound
      repeat with tC = 1 to the number of cards of this stack
         if there is a field tName of card tC \
               or there is a button tName of card tC \
               or there is a graphic tName of card tC \
               or there is an image tName of card tC then
            put true into tFound
            exit repeat
         end if
      end repeat
      if not tFound then
         put tName & comma after tMissing
      end if
   end repeat
   if tMissing is empty then
      return empty
   end if
   return char 1 to -2 of tMissing
end scMissing

-- Call LAST in <pfx>ScRun. It arms the probe below; 400ms lands it before the
-- usual 800ms dashboard tick, so nothing races for the status line.
--
-- SAY THAT THE REPORT IS UNFINISHED, for the reason the suite harness carries a
-- RUN NOT FINISHED trailer: a report that simply stops reads exactly like a
-- report that ended, and the difference cost that harness a round trip on
-- 2026-08-19. One line is cheaper than the ambiguity.
command scArmProbe
   scLine "      ...one delayed-write check still to come; the count line " \
         & "below it is the end of the block"
   send "scTickProbe" to me in 400 milliseconds
end scArmProbe

-- THE ONE CHECK THAT NEEDS A TIMER.
--
-- OXT-ENGINE-NOTES 5.3 says an unqualified control reference inside a delayed
-- handler resolves against THE DEFAULTSTACK, not the stack whose script is
-- running - and that entry is classed DOCUMENTED, not OBSERVED, because this
-- tree has never actually watched the unpinned form fail. It also names the run
-- that would settle it: open a second stack in front and let a `send ... in`
-- handler write an unqualified field.
--
-- So this probe READS the defaultStack before pinning and PRINTS what it found.
-- On an ordinary run that line is context. On a run with another window in front
-- it is the measurement 5.3 is missing, taken for free and at no risk, because
-- the pin lands immediately afterwards and the write is verified.
command scTickProbe
   local tWas, tPrev, tPrevColor, tGot, tErr
   put the defaultStack into tWas
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      scSkip "a delayed handler writes the status line", "the chrome is not built"
      scFinish
      exit scTickProbe
   end if
   -- RESTORE THE COLOUR TOO, not just the text. uiStatus takes a KIND, and
   -- handing it back "ok" would repaint a "bad" line green - so a stack whose
   -- extension is missing would end this probe claiming to be fine.
   put field "uiStatus" into tPrev
   put the foregroundColor of field "uiStatus" into tPrevColor
   try
      uiStatus kScProbe, empty
      put field "uiStatus" into tGot
   catch tErr
      put "THREW:" && tErr into tGot
   end try
   uiStatus tPrev, empty
   set the foregroundColor of field "uiStatus" to tPrevColor
   scAssert "a delayed handler writes the status line " \
         & "(defaultStack on entry: " & scShow(tWas) & ")", (tGot is kScProbe)
   scFinish
end scTickProbe

command scFinish
   scLine "      " & sScPassed & " passed, " & sScFailed & " failed, " \
         & sScSkipped & " skipped - select this block and copy it into the " \
         & "OXT pass record"
   if sScFailed is 0 then
      scLine "      boot self-check GREEN (this is the single-machine claim; " \
            & "the live legs are the runbook's)"
      exit scFinish
   end if
   scLine "      boot self-check has FAILURES above - report them before " \
         & "running any live leg"
   -- ONLY ON FAILURE does this touch the status line, and the asymmetry is
   -- deliberate. Green, the demo's own "Ready ..." line is the more useful
   -- thing to be reading and the detail is in the log a few lines up. Red, the
   -- log may be on a tab nobody has clicked - so the one surface a person is
   -- certainly looking at has to say so. Fail loud, pass quiet.
   uiStatus "Boot self-check: " & sScFailed & " FAILED (see the log)", "bad"
end scFinish
-- ==== DEMO SELF-CHECK v1 END ====

-- ==========================================================================
-- Lifecycle.
-- ==========================================================================

on preOpenStack
   -- the toggles start defined: a script-local is EMPTY until written, and
   -- `if empty then` / `not empty` are errors, not false
   put true into sQdTryHarder
   put false into sQdAlsoInverted
   put false into sQdPureBarcode
   put false into sQdBinaryMode
   put false into sQdPipeGlobal
   qdBuildUI
   qdSyncToggles
   qdShowTab "decode"
end preOpenStack

on openStack
   -- the self-check runs LAST, after the build, because it reads the state
   -- the build establishes (the suite's carried-block contract)
   qdScRun
end openStack

on closeStack
   -- Nothing to release: the decoder keeps no handles. Its one side effect,
   -- the private invisible stack it decodes PNGs on, is its own cache and
   -- is documented in luminanceSource_decodeRawPlane.
end closeStack

-- Files dropped on the window load like the file picker (desktop engines).
on dragEnter
   set the acceptDrop to true
end dragEnter

on dragDrop
   local tFiles, tErr
   put empty into tFiles
   try
      put the dragData["files"] into tFiles
   catch tErr
      put empty into tFiles
   end try
   if tFiles is empty then
      uiStatus "Drop an image FILE on the window (PNG, GIF, BMP; JPEG depends on the engine build).", "warn"
      exit dragDrop
   end if
   qdLoadFile (line 1 of tFiles)
end dragDrop

-- ==========================================================================
-- Styled control helpers: thin wrappers over the kit builders that keep
-- only what the kit leaves to the adopter (per-call colour and weight, the
-- flat primary/idle button split the tab bar repaints). Names carry a
-- "prefix:role" tag: the prefix is the owning tab (or "ui" for chrome), so
-- qdShowTab can toggle a tab by visibility and mouseUp can route by role.
-- ==========================================================================

-- A caption at a FIXED rect (uiLabel, not the fit-to-text uiWrap), because
-- the status captions are rewritten with longer text after they are built
-- and a field fitted to its first line would clip the rest.
command qdLabel pName, pRect, pText, pColor, pSize, pStyle
   uiLabel pName, pText, pRect, pSize
   set the textStyle of field pName to pStyle
   set the foregroundColor of field pName to pColor
end qdLabel

-- The checkboxes show the script's state, not the other way round: a stack
-- saved with the controls built keeps their old hilites, so they are set
-- from the locals on every open.
command qdSyncToggles
   set the hilite of button "decode:tryHarder" to sQdTryHarder
   set the hilite of button "decode:alsoInverted" to sQdAlsoInverted
   set the hilite of button "decode:pureBarcode" to sQdPureBarcode
   set the hilite of button "decode:binaryMode" to sQdBinaryMode
   set the hilite of button "pipe:global" to sQdPipeGlobal
end qdSyncToggles

command qdButton pName, pRect, pLabel, pPrimary
   uiButton pName, pLabel, pRect
   set the showName of button pName to true
   set the textSize of button pName to 12
   set the textStyle of button pName to "bold"
   set the threeD of button pName to false
   set the borderWidth of button pName to 0
   set the opaque of button pName to true
   set the autoHilite of button pName to true
   qdPaintButton pName, pPrimary
end qdButton

command qdPaintButton pName, pPrimary
   if pPrimary then
      set the backgroundColor of button pName to kUiAccent
      set the foregroundColor of button pName to kUiAccentText
   else
      set the backgroundColor of button pName to kUiCardLine
      set the foregroundColor of button pName to kUiInk
   end if
end qdPaintButton

command qdCheckbox pName, pRect, pLabel, pOn
   uiCheckbox pName, pLabel, pRect
   set the textSize of button pName to 11
   set the hilite of button pName to pOn
end qdCheckbox

-- An image control at a fixed rect: the kit builds none, and this demo shows
-- the loaded picture in one (the same create-then-name idiom as the kit).
-- lockLoc is what makes a later `set the rect` SCALE the picture.
command qdImage pName, pRect
   if there is no image pName then
      create image
      set the name of the last image to pName
   end if
   set the lockLoc of image pName to true
   set the rect of image pName to pRect
end qdImage

-- A tab's own status line, coloured by kind ("ok", "bad", "warn", else muted).
command qdSetStatus pName, pText, pKind
   if there is no field pName then
      exit qdSetStatus
   end if
   put pText into field pName
   if pKind is "ok" then
      set the foregroundColor of field pName to kUiOk
   else if pKind is "bad" then
      set the foregroundColor of field pName to kUiBad
   else if pKind is "warn" then
      set the foregroundColor of field pName to kUiWarn
   else
      set the foregroundColor of field pName to kUiInkSoft
   end if
end qdSetStatus

-- ==========================================================================
-- UI construction.
-- ==========================================================================

command qdBuildUI
   local tErr, tVer
   -- Version-guarded rebuild: an "is there a field" guard cannot tell a
   -- current UI from a stale one saved by an earlier script, so a kit bump
   -- would silently keep the old controls forever.
   if the uQdUiVersion of this stack is kQdUiVersion and there is a field "ui:tabDecode" then
      exit qdBuildUI
   end if
   qdClearGeneratedUI
   lock screen
   -- the chrome is the kit's: stack size, ground, title band, status line
   -- (900x640 sits inside the family's 1200x640 budget)
   uiChrome "xtQRdecoder - a pure xTalk QR decoder", kQdWinW, kQdWinH
   -- probe the embedded library through the ONE status line, so a stack
   -- whose embed is damaged says so in red, at the top, immediately
   put empty into tVer
   try
      put qrLibraryVersion() into tVer
   catch tErr
      put empty into tVer
   end try
   if tVer is empty then
      uiStatus "The embedded xtQRdecoder library did not answer: re-run tools/sync_demo_embeds.py and paste again.", "bad"
   else
      uiStatus "Ready - xtQRdecoder " & tVer & ". Load an image, or pick a sample.", "ok"
   end if

   -- the tab bar (the demo's own mechanism; qdRestyleTabs repaints it)
   qdButton "ui:tabDecode", "24,60,164,88", "Decode", false
   qdButton "ui:tabPipe", "170,60,310,88", "Pipeline", false
   qdButton "ui:tabSamples", "316,60,456,88", "Samples", false
   qdButton "ui:tabAbout", "462,60,602,88", "About", false

   -- the content card and the honesty footer, both the kit's; the card is
   -- created BEFORE the tab content so it sits behind it in z-order
   uiPanel "ui:panel", "24,96,876,596"
   uiFooter \
         "xtQRdecoder decodes QR codes in pure xTalk (a ZXing port; Apache-2.0)." \
         & " Engine record: unit harness and golden photos green on an xTalk server at 0.1.0;" \
         & " this stack and the 0.2.0 decoder are verified statically and need an OXT pass.", \
         "24,602,876,638"

   qdBuildDecodeTab
   qdBuildPipeTab
   qdBuildSamplesTab
   qdBuildAboutTab
   set the uQdUiVersion of this stack to kQdUiVersion
   unlock screen
end qdBuildUI

-- The rebuild's clear pass: every generated control's short name carries a
-- ":" (the "prefix:role" scheme) while the kit's own chrome (uiTitle,
-- uiStatus, uiBand, uiFooter) has none, so the colon IS the ownership tag
-- and the kit controls survive to be restyled in place by uiChrome.
command qdClearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card contains ":" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card contains ":" then
         delete button tI of this card
      end if
   end repeat
   repeat with tI = the number of graphics of this card down to 1
      if the short name of graphic tI of this card contains ":" then
         delete graphic tI of this card
      end if
   end repeat
   repeat with tI = the number of images of this card down to 1
      if the short name of image tI of this card contains ":" then
         delete image tI of this card
      end if
   end repeat
   unlock screen
end qdClearGeneratedUI

command qdBuildDecodeTab
   -- left column: the image (with its preview), the hints, the two decode calls
   uiSection "decode:sec1", "1. Image", "48,108,430,128"
   qdButton "decode:open", "48,136,196,162", "Choose a file...", true
   qdButton "decode:paste", "202,136,318,162", "Paste image", false
   qdButton "decode:next", "324,136,430,162", "Next sample", false
   -- the preview: a white, hairlined box (created first, so it sits behind)
   -- and the image control the loaded picture is scaled into
   uiGfx "decode:previewBox", kQdPreviewBox
   set the roundRadius of graphic "decode:previewBox" to 8
   set the filled of graphic "decode:previewBox" to true
   set the backgroundColor of graphic "decode:previewBox" to kUiCard
   set the lineSize of graphic "decode:previewBox" to 1
   set the foregroundColor of graphic "decode:previewBox" to kUiCardLine
   set the borderColor of graphic "decode:previewBox" to kUiCardLine
   qdImage "decode:preview", kQdPreviewBox
   uiCap "decode:imgInfo", "No image loaded. Choose a file, paste one, drop one on this window, or click Next sample - the picture appears here.", "238,170,430,350"

   uiSection "decode:sec2", "2. Hints", "48,358,430,378"
   qdCheckbox "decode:tryHarder", "48,384,236,404", "TRY_HARDER", true
   qdCheckbox "decode:alsoInverted", "242,384,430,404", "ALSO_INVERTED", false
   qdCheckbox "decode:pureBarcode", "48,408,236,428", "PURE_BARCODE", false
   qdCheckbox "decode:binaryMode", "242,408,430,428", "BINARY_MODE", false
   uiCap "decode:hintCap", "TRY_HARDER for photographs; ALSO_INVERTED for white on black; PURE_BARCODE for a clean, axis-aligned image; BINARY_MODE shows the raw bytes as hex.", "48,432,430,460"

   uiSection "decode:sec3", "3. Decode", "48,466,430,486"
   qdButton "decode:robust", "48,492,236,520", "Decode (robust)", true
   qdButton "decode:single", "242,492,430,520", "Single pass", false
   qdLabel "decode:status", "48,526,430,590", "Load an image, then click Decode (robust): one image decode, then the binarizer and resolution ladder with the mirrored and inverted retries. Single pass is qrDecodeResult at full resolution.", kUiInkSoft, 11, "plain"

   -- right column: the text and every result key
   uiSection "decode:sec4", "Decoded text", "446,108,852,128"
   uiArea "decode:text", "446,136,852,246"
   qdButton "decode:copy", "740,252,852,278", "Copy text", false
   uiSection "decode:sec5", "Result keys", "446,288,852,308"
   uiArea "decode:details", "446,316,852,590"
end qdBuildDecodeTab

command qdBuildPipeTab
   uiSection "pipe:sec", "The pipeline, one stage at a time", "48,108,852,128"
   uiCap "pipe:cap", "Runs the loaded image through the library stage by stage - image decode, greyscale, binarize, detect, sample, decode - and prints what each produced: timings, the finder centres, the module count and the de-skewed grid as block art. The single pass that fails falls back to the robust call and says so.", "48,134,852,176"
   qdButton "pipe:run", "48,184,236,212", "Run the pipeline", true
   qdCheckbox "pipe:global", "248,188,600,208", "Use the global-histogram binarizer instead of hybrid", false
   uiArea "pipe:out", "48,220,852,590"
end qdBuildPipeTab

command qdBuildSamplesTab
   uiSection "samples:sec", "Seven images travel inside this stack", "48,108,852,128"
   uiCap "samples:cap", "Click one to load it into the Decode tab, or decode them all: every line is a PASS or FAIL against the text the image is known to carry, so the log is an engine record for this machine. The inverted symbol is also decoded WITHOUT its flag, where it must fail.", "48,134,852,176"
   qdButton "samples:v1num", "48,184,236,212", "v1 numeric", false
   qdButton "samples:mirror", "242,184,430,212", "Mirrored symbol", false
   qdButton "samples:inverted", "436,184,624,212", "Inverted (white on black)", false
   qdButton "samples:utf8", "630,184,852,212", "UTF-8 bytes", false
   qdButton "samples:scale1", "48,218,236,246", "1 px per module", false
   qdButton "samples:rot25", "242,218,430,246", "Rotated 25 degrees", false
   qdButton "samples:photo", "436,218,624,246", "A real photograph", false
   qdButton "samples:runAll", "630,218,852,246", "Decode all samples", true
   uiArea "samples:out", "48,254,852,590"
end qdBuildSamplesTab

command qdBuildAboutTab
   qdLabel "about:h", "48,108,852,134", "xtQRdecoder", kUiInk, 16, "bold"
   qdLabel "about:exp", "48,140,852,292", "A QR code reader in pure xTalk: no external, no cloud call, no widget. Versions 1-40, all four error-correction levels, numeric, alphanumeric and byte modes with ISO-8859-1 / UTF-8 / UTF-16 text, ECI, FNC1 and structured append; rotation and perspective tolerance from ZXing's detector; Reed-Solomon over GF(256). Four public functions: qrDecodeFromData and qrDecodeFromFile return the text (empty on failure); qrDecodeResult returns the full result array from one pass; qrDecodeResultRobust - the one to use on photographs - decodes the image once and walks a ladder of binarizers and resolutions, retrying mirrored and (with ALSO_INVERTED) inverted symbols. Nothing throws: failures arrive as NotFound:, Format: or Checksum: in the result's error key.", kUiInkSoft, 12, "plain"
   qdLabel "about:hint", "48,298,852,340", "New here? Open the Samples tab and click Decode all samples - seven PASS lines is the whole point. Then drop a photo of any QR code on the window and click Decode (robust).", kUiAccent, 12, "bold"
   qdButton "about:selfcheck", "48,350,330,378", "Run the boot self-check again", true
   uiArea "about:log", "48,386,852,562"
   qdLabel "about:status", "48,568,852,590", "The log above is the boot self-check: nothing is hosted, connected or bound.", kUiInkSoft, 11, "plain"
end qdBuildAboutTab

-- ==========================================================================
-- Tabs.
-- ==========================================================================

command qdShowTab pKey
   local tI, tN, tPre, tOldDelim
   put pKey into sQdTab
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to ":"
   repeat with tI = 1 to the number of controls of this card
      put the short name of control tI into tN
      put item 1 of tN into tPre
      if tPre is "decode" or tPre is "pipe" or tPre is "samples" or tPre is "about" then
         set the visible of control tI to (tPre is pKey)
      end if
   end repeat
   set the itemDelimiter to tOldDelim
   qdRestyleTabs
end qdShowTab

command qdRestyleTabs
   qdPaintButton "ui:tabDecode", (sQdTab is "decode")
   qdPaintButton "ui:tabPipe", (sQdTab is "pipe")
   qdPaintButton "ui:tabSamples", (sQdTab is "samples")
   qdPaintButton "ui:tabAbout", (sQdTab is "about")
end qdRestyleTabs

-- ==========================================================================
-- Click routing: a control's short name is "prefix:role"; dispatch by prefix.
-- ==========================================================================

on mouseUp
   local tName, tPrefix, tRole, tOldDelim
   put the short name of the target into tName
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to ":"
   put item 1 of tName into tPrefix
   put item 2 of tName into tRole
   set the itemDelimiter to tOldDelim
   if tPrefix is "ui" then
      qdHandleChrome tRole
   else if tPrefix is "decode" then
      qdHandleDecode tRole
   else if tPrefix is "pipe" then
      qdHandlePipe tRole
   else if tPrefix is "samples" then
      qdHandleSamples tRole
   else if tPrefix is "about" then
      qdHandleAbout tRole
   else
      pass mouseUp
   end if
end mouseUp

command qdHandleChrome pRole
   if pRole is "tabDecode" then
      qdShowTab "decode"
   else if pRole is "tabPipe" then
      qdShowTab "pipe"
   else if pRole is "tabSamples" then
      qdShowTab "samples"
   else if pRole is "tabAbout" then
      qdShowTab "about"
   end if
end qdHandleChrome

-- ==========================================================================
-- Decode tab.
-- ==========================================================================

command qdHandleDecode pRole
   if pRole is "open" then
      qdChooseFile
   else if pRole is "paste" then
      qdPasteImage
   else if pRole is "next" then
      qdNextSample
   else if pRole is "tryHarder" then
      put not sQdTryHarder into sQdTryHarder
      set the hilite of button "decode:tryHarder" to sQdTryHarder
   else if pRole is "alsoInverted" then
      put not sQdAlsoInverted into sQdAlsoInverted
      set the hilite of button "decode:alsoInverted" to sQdAlsoInverted
   else if pRole is "pureBarcode" then
      put not sQdPureBarcode into sQdPureBarcode
      set the hilite of button "decode:pureBarcode" to sQdPureBarcode
   else if pRole is "binaryMode" then
      put not sQdBinaryMode into sQdBinaryMode
      set the hilite of button "decode:binaryMode" to sQdBinaryMode
   else if pRole is "robust" then
      qdDecode true
   else if pRole is "single" then
      qdDecode false
   else if pRole is "copy" then
      qdCopyText
   end if
end qdHandleDecode

command qdChooseFile
   answer file "Choose a QR image" with type "Images|png,jpg,jpeg,gif,bmp"
   if it is empty then
      exit qdChooseFile
   end if
   qdLoadFile it
end qdChooseFile

command qdLoadFile pPath
   local tData, tOldDelim, tShort
   if there is not a file pPath then
      uiStatus "There is no file at " & pPath, "bad"
      exit qdLoadFile
   end if
   put url ("binfile:" & pPath) into tData
   if tData is empty then
      uiStatus "That file is empty or could not be read: " & pPath, "bad"
      exit qdLoadFile
   end if
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "/"
   put the last item of pPath into tShort
   set the itemDelimiter to tOldDelim
   qdSetImage tData, tShort
end qdLoadFile

-- The clipboard's image, when the engine offers one (PNG on most desktops).
command qdPasteImage
   local tData, tErr
   put empty into tData
   try
      put the clipboardData["image"] into tData
   catch tErr
      put empty into tData
   end try
   if tData is empty then
      uiStatus "No image on the clipboard. Copy a picture of a QR code first (a screenshot works).", "warn"
      exit qdPasteImage
   end if
   qdSetImage tData, "(pasted image)"
end qdPasteImage

-- Cycle through the embedded samples from the Decode tab.
command qdNextSample
   local tOldDelim, tN, tI, tKey, tNext
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put the number of items of kQdSamples into tN
   put item 1 of kQdSamples into tNext
   repeat with tI = 1 to tN
      put item tI of kQdSamples into tKey
      if sQdImageName is ("sample: " & tKey) and tI < tN then
         put item (tI + 1) of kQdSamples into tNext
         exit repeat
      end if
   end repeat
   set the itemDelimiter to tOldDelim
   qdLoadSample tNext
end qdNextSample

command qdLoadSample pKey
   local tData, tHints
   put qdSampleData(pKey) into tData
   if tData is empty then
      uiStatus "There is no sample called " & pKey, "bad"
      exit qdLoadSample
   end if
   qdSetImage tData, "sample: " & pKey
   -- THE TOGGLES FOLLOW THE SAMPLE. The inverted symbol decodes only under
   -- ALSO_INVERTED, and on this stack's first engine run (2026-09-05) that
   -- sample, loaded with the flag unticked, reported "No QR code decoded" -
   -- correct, and indistinguishable from a broken decoder to anyone who had
   -- not read the status line. So loading a sample sets the hints it needs
   -- and says so; the boxes are still yours to untick afterwards.
   put qdSampleHints(pKey) into tHints
   put true into sQdTryHarder
   put (tHints contains "ALSO_INVERTED") into sQdAlsoInverted
   put false into sQdPureBarcode
   qdSyncToggles
   qdSetStatus "decode:status", qdSampleLabel(pKey) & " - expected text: " & qdSampleText(pKey) \
         & ". Hints ticked for it: " & tHints & ". Untick ALSO_INVERTED on the inverted sample to watch it fail.", empty
end qdLoadSample

command qdSetImage pData, pName
   local tShown, tInfo
   put pData into sQdImage
   put pName into sQdImageName
   put empty into sQdLastText
   put empty into field "decode:text"
   put empty into field "decode:details"
   put qdShowPreview(pData) into tShown
   put "Loaded " & pName & " (" & (the number of bytes of pData) & " bytes)" into tInfo
   if tShown then
      put tInfo & ", " & (the formattedWidth of image "decode:preview") & " x " \
            & (the formattedHeight of image "decode:preview") & " px. Now click Decode (robust), or open the Pipeline tab." into tInfo
   else
      put tInfo & ". No preview: this engine build could not render the picture (JPEG support varies); the decoder may still read it. Click Decode (robust)." into tInfo
   end if
   uiCap "decode:imgInfo", tInfo, "238,170,430,350"
   uiStatus "Loaded " & pName & ".", "ok"
   qdSetStatus "decode:status", "Ready to decode " & pName & ".", empty
end qdSetImage

-- Scale the loaded picture into the preview box, aspect kept and centred.
-- Returns false when the engine could not render the bytes (the box is left
-- blank); the decoder does not depend on this control at all.
function qdShowPreview pData
   local tErr, tW, tH, tOldDelim, tBoxL, tBoxT, tBoxR, tBoxB, tBoxW, tBoxH
   local tScale, tFitW, tFitH, tL, tT
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 1 of kQdPreviewBox into tBoxL
   put item 2 of kQdPreviewBox into tBoxT
   put item 3 of kQdPreviewBox into tBoxR
   put item 4 of kQdPreviewBox into tBoxB
   set the itemDelimiter to tOldDelim
   put (tBoxR - tBoxL) into tBoxW
   put (tBoxB - tBoxT) into tBoxH
   put 0 into tW
   put 0 into tH
   try
      -- unlocked, the put resizes the control to the picture's own size,
      -- which is the size the fit below is computed from
      set the lockLoc of image "decode:preview" to false
      put pData into image "decode:preview"
      put the formattedWidth of image "decode:preview" into tW
      put the formattedHeight of image "decode:preview" into tH
   catch tErr
      put 0 into tW
      put 0 into tH
   end try
   set the lockLoc of image "decode:preview" to true
   if tW <= 0 or tH <= 0 then
      set the rect of image "decode:preview" to kQdPreviewBox
      return false
   end if
   put min(tBoxW / tW, tBoxH / tH) into tScale
   put max(1, round(tW * tScale)) into tFitW
   put max(1, round(tH * tScale)) into tFitH
   put (tBoxL + ((tBoxW - tFitW) div 2)) into tL
   put (tBoxT + ((tBoxH - tFitH) div 2)) into tT
   set the rect of image "decode:preview" to (tL & comma & tT & comma & (tL + tFitW) & comma & (tT + tFitH))
   return true
end qdShowPreview

-- The hint string the toggles spell, in the library's own comma form.
function qdHintString
   local tHints
   put empty into tHints
   if sQdTryHarder then
      put "TRY_HARDER," after tHints
   end if
   if sQdAlsoInverted then
      put "ALSO_INVERTED," after tHints
   end if
   if sQdPureBarcode then
      put "PURE_BARCODE," after tHints
   end if
   if sQdBinaryMode then
      put "BINARY_MODE," after tHints
   end if
   if tHints ends with comma then
      delete the last char of tHints
   end if
   return tHints
end qdHintString

command qdDecode pRobust
   local tHints, tRes, tT0, tMs
   if sQdImage is empty then
      qdSetStatus "decode:status", "Load an image first: a file, the clipboard, a drop on the window, or a sample.", "warn"
      uiStatus "Nothing to decode yet.", "warn"
      exit qdDecode
   end if
   put qdHintString() into tHints
   uiStatus "Decoding " & sQdImageName & " ...", empty
   put the milliseconds into tT0
   -- neither call throws: NotFound/Format/Checksum arrive in ["error"]
   if pRobust then
      put qrDecodeResultRobust(sQdImage, tHints) into tRes
   else
      put qrDecodeResult(sQdImage, tHints) into tRes
   end if
   put (the milliseconds - tT0) into tMs
   qdShowResult tRes, tMs, pRobust, tHints
end qdDecode

command qdShowResult pRes, pMs, pRobust, pHints
   local tOut, tCall, tI, tN, tA, tShown
   if pRobust then
      put "qrDecodeResultRobust" into tCall
   else
      put "qrDecodeResult" into tCall
   end if
   put empty into sQdLastText
   if pRes["error"] is not empty then
      put empty into field "decode:text"
      put tCall & "(image, " & quote & pHints & quote & ")" & return \
            & "error   : " & pRes["error"] & return & qdAttemptsText(pRes) into field "decode:details"
      qdSetStatus "decode:status", "No decode in " & pMs & " ms: " & pRes["error"] & qdFailureAdvice(pRes["error"]), "bad"
      uiStatus "No QR code decoded from " & sQdImageName & " (" & pMs & " ms)." & qdFailureAdvice(pRes["error"]), "bad"
      exit qdShowResult
   end if
   put pRes["text"] into sQdLastText
   if sQdBinaryMode then
      put qdBytesToHex(pRes["bytes"]) into tShown
   else
      put pRes["text"] into tShown
   end if
   put tShown into field "decode:text"
   put tCall & "(image, " & quote & pHints & quote & ")  in " & pMs & " ms" & return into tOut
   put "version : " & pRes["version"] & return after tOut
   put "ecLevel : " & pRes["ecLevel"] & return after tOut
   put "mask    : " & pRes["mask"] & return after tOut
   put "bytes   : " & (the number of bytes of pRes["bytes"]) & " raw payload bytes" & return after tOut
   if pRes["charset"] is not empty then
      put "charset : " & pRes["charset"] & return after tOut
   end if
   if pRes["fnc1"] is not empty then
      put "fnc1    : " & pRes["fnc1"] & " position" & return after tOut
   end if
   if pRes["symbologyModifier"] is not empty then
      put "symbologyModifier : " & pRes["symbologyModifier"] & return after tOut
   end if
   if pRes["structuredAppendSeq"] is not empty then
      put "structuredAppend  : sequence " & pRes["structuredAppendSeq"] & ", parity " & pRes["structuredAppendParity"] & return after tOut
   end if
   if pRes["mirrored"] is true then
      put "mirrored: true  (decoded on the transpose retry)" & return after tOut
   end if
   if pRes["inverted"] is true then
      put "inverted: true  (decoded on the ALSO_INVERTED retry)" & return after tOut
   end if
   if pRobust then
      put "strategy: " & pRes["strategy"] & " binarizer, step " & pRes["step"] & ", " & pRes["procW"] & "x" & pRes["procH"] & " px" & return after tOut
   end if
   put "points  : " & qdPointsText(pRes["points"]) & return after tOut
   put qdAttemptsText(pRes) after tOut
   put tOut into field "decode:details"
   qdSetStatus "decode:status", "Decoded in " & pMs & " ms: version " & pRes["version"] & "-" & pRes["ecLevel"] & ", " & (the number of chars of pRes["text"]) & " chars.", "ok"
   uiStatus "Decoded " & sQdImageName & " in " & pMs & " ms.", "ok"
end qdShowResult

-- What to try next after a failed decode, from the hints NOT ticked: a
-- NotFound with ALSO_INVERTED off may be a white-on-black symbol, and any
-- failure with TRY_HARDER off may be a photograph the sparse scan skipped.
function qdFailureAdvice pError
   local tAdvice
   put empty into tAdvice
   if (pError begins with "NotFound") and (not sQdAlsoInverted) then
      put " Tick ALSO_INVERTED if the symbol is white on black." after tAdvice
   end if
   if not sQdTryHarder then
      put " Tick TRY_HARDER for photographs." after tAdvice
   end if
   return tAdvice
end qdFailureAdvice

-- The result points as "(x, y)" pairs, one decimal place; index 3 is the
-- alignment pattern when the symbol has one.
function qdPointsText pPoints
   local tOut, tI
   put empty into tOut
   repeat with tI = 0 to 3
      if pPoints[tI] is not empty then
         if tOut is not empty then
            put "  " after tOut
         end if
         put "[" & tI & "] " & qdPt(pPoints[tI]) after tOut
      end if
   end repeat
   return tOut
end qdPointsText

function qdPt pPt
   return "(" & (round(pPt["x"] * 10) / 10) & ", " & (round(pPt["y"] * 10) / 10) & ")"
end qdPt

-- The robust call's ["attempts"] list: every rung it tried, in order.
function qdAttemptsText pRes
   local tOut, tI, tN, tA
   put empty into tOut
   put the number of elements of pRes["attempts"] into tN
   if tN = 0 then
      return empty
   end if
   put "attempts: " & tN & return into tOut
   repeat with tI = 0 to (tN - 1)
      put pRes["attempts"][tI] into tA
      put "   " & (tI + 1) & ". " & tA["strategy"] & " step " & tA["step"] & " (" & tA["procW"] & "x" & tA["procH"] & ")" after tOut
      if tA["error"] is empty then
         put "  decoded" & return after tOut
      else
         put "  " & tA["error"] & return after tOut
      end if
   end repeat
   return tOut
end qdAttemptsText

command qdCopyText
   if sQdLastText is empty then
      uiStatus "Nothing decoded yet.", "warn"
      exit qdCopyText
   end if
   set the clipboardData["text"] to sQdLastText
   uiCopyFlash "decode:copy"
end qdCopyText

function qdBytesToHex pBytes
   local tOut, tI, tN, tH
   put empty into tOut
   put the number of bytes of pBytes into tN
   repeat with tI = 1 to tN
      put baseConvert(byteToNum(byte tI of pBytes), 10, 16) into tH
      if the number of chars of tH < 2 then
         put "0" before tH
      end if
      put tH after tOut
      if tI mod 32 = 0 then
         put return after tOut
      else if tI mod 4 = 0 then
         put " " after tOut
      end if
   end repeat
   return tOut
end qdBytesToHex

-- "63616665" -> the bytes 63 61 66 65
function qdHexToBytes pHex
   local tOut, tI, tN, tHi, tLo, tDigits
   put "0123456789abcdef" into tDigits
   put toLower(pHex) into pHex
   put the number of chars of pHex into tN
   put empty into tOut
   put 1 into tI
   repeat while tI < tN
      put (offset(char tI of pHex, tDigits) - 1) into tHi
      put (offset(char (tI + 1) of pHex, tDigits) - 1) into tLo
      if tHi < 0 or tLo < 0 then
         return empty
      end if
      put numToByte((tHi * 16) + tLo) after tOut
      add 2 to tI
   end repeat
   return tOut
end qdHexToBytes

-- ==========================================================================
-- Pipeline tab: the library's stages, called one at a time. These are
-- INTERNAL handlers (luminanceSource_*, binaryBitmap_*, dt_detect,
-- dec_decode, bitMatrix_*), in scope only because the whole library lives
-- in this script; real use needs only the qrDecode* functions.
-- ==========================================================================

command qdHandlePipe pRole
   if pRole is "run" then
      qdRunPipeline
   else if pRole is "global" then
      put not sQdPipeGlobal into sQdPipeGlobal
      set the hilite of button "pipe:global" to sQdPipeGlobal
   end if
end qdHandlePipe

command qdRunPipeline
   local tOut, tMark, tMaxDim, tPlane, tStep, tSrc, tBin, tBmp, tBlack
   local tHints, tDet, tPts, tRes, tErr, tFailed
   if sQdImage is empty then
      put "Load an image on the Decode tab first (a file, the clipboard, a drop, or a sample)." into field "pipe:out"
      uiStatus "Nothing to run the pipeline on yet.", "warn"
      exit qdRunPipeline
   end if
   put 1200 into tMaxDim
   put "xtQRdecoder pipeline - " & sQdImageName & return into tOut
   put "==============================" & return after tOut
   put "STEP 0 - input:  " & (the number of bytes of sQdImage) & " bytes" & return & return after tOut
   put false into tFailed
   put empty into tErr
   try
      -- [1] the engine decodes the compressed image to a 4-byte/pixel plane
      put the milliseconds into tMark
      put luminanceSource_decodeRawPlane(sQdImage) into tPlane
      put "STEP 1 - image decode    (" & (the milliseconds - tMark) & " ms)" & return after tOut
      put "   source : " & tPlane["width"] & " x " & tPlane["height"] & " px" & return after tOut
      put "   raw    : " & (the number of bytes of tPlane["raw"]) & " bytes  (4 B/px, 0,R,G,B)" & return & return after tOut

      -- [2] greyscale + nearest-neighbour downsample
      put the milliseconds into tMark
      put luminanceSource_stepForDims(tPlane["width"], tPlane["height"], tMaxDim) into tStep
      put luminanceSource_fromRawPlane(tPlane, tMaxDim) into tSrc
      put "STEP 2 - greyscale       (" & (the milliseconds - tMark) & " ms)" & return after tOut
      put "   maxDim : " & tMaxDim & " px  ->  downsample step " & tStep & return after tOut
      put "   grid   : " & tSrc["width"] & " x " & tSrc["height"] & "  (luma 0-255, row-major)" & return & return after tOut

      -- [3] binarize
      put the milliseconds into tMark
      if sQdPipeGlobal then
         put "global" into tBin
      else
         put "hybrid" into tBin
      end if
      put binaryBitmap_new(tSrc, tBin) into tBmp
      put binaryBitmap_getBlackMatrix(tBmp) into tBlack
      put "STEP 3 - binarize " & tBin & "  (" & (the milliseconds - tMark) & " ms)" & return after tOut
      put "   matrix : " & bitMatrix_getWidth(tBlack) & " x " & bitMatrix_getHeight(tBlack) & "  (1 bit/px, true = black)" & return & return after tOut

      -- [4] finder patterns -> module size -> perspective transform -> sample
      put the milliseconds into tMark
      put true into tHints["TRY_HARDER"]
      put dt_detect(tBlack, tHints) into tDet
      put tDet["points"] into tPts
      put "STEP 4 - detect          (" & (the milliseconds - tMark) & " ms)" & return after tOut
      put "   grid   : " & tDet["dimension"] & " modules per side  (version " & ((tDet["dimension"] - 17) div 4) & ")" & return after tOut
      put "   finder : BL " & qdPt(tPts[0]) & "   TL " & qdPt(tPts[1]) & "   TR " & qdPt(tPts[2]) & return after tOut
      if tPts[3] is not empty then
         put "   align  : " & qdPt(tPts[3]) & return after tOut
      end if
      put return after tOut
      if tDet["dimension"] <= 41 then
         put "   the sampled grid (the de-skewed symbol itself):" & return after tOut
         put qdMatrixAscii(tDet["bits"]) & return after tOut
      else
         put "   (grid art skipped above version 6: " & tDet["dimension"] & " modules per side)" & return & return after tOut
      end if

      -- [5] format and version -> un-mask -> de-interleave -> Reed-Solomon -> bitstream
      put the milliseconds into tMark
      put dec_decode(tDet["bits"]) into tRes
      if tRes["error"] is not empty then
         put tRes["error"] into tErr
         put true into tFailed
      else
         put "STEP 5 - decode bits     (" & (the milliseconds - tMark) & " ms)" & return after tOut
         put "   version: " & tRes["version"] & "   ecLevel: " & tRes["ecLevel"] & "   mask: " & tRes["mask"] & return after tOut
         if tRes["mirrored"] is true then
            put "   note   : the symbol decoded on the mirror retry" & return after tOut
         end if
         put "   payload: " & (the number of bytes of tRes["bytes"]) & " bytes" & return & return after tOut
         put "==============================" & return & "DECODED TEXT:" & return & tRes["text"] & return after tOut
      end if
   catch tErr
      put true into tFailed
   end try
   if tFailed then
      put return & "x  the single pass stopped here: " & tErr & return after tOut
      put "-> retrying with qrDecodeResultRobust(image, " & quote & "TRY_HARDER,ALSO_INVERTED" & quote & "):" & return after tOut
      put qrDecodeResultRobust(sQdImage, "TRY_HARDER,ALSO_INVERTED") into tRes
      if tRes["error"] is empty then
         put "OK recovered by the " & tRes["strategy"] & " binarizer at " & tRes["procW"] & "x" & tRes["procH"] & ":" & return & return & tRes["text"] & return after tOut
         uiStatus "Single pass stopped; the robust call recovered it.", "warn"
      else
         put "x  no QR code found: " & tRes["error"] & return after tOut
         uiStatus "No QR code found in " & sQdImageName & ".", "bad"
      end if
   else
      uiStatus "Pipeline complete for " & sQdImageName & ".", "ok"
   end if
   put tOut into field "pipe:out"
end qdRunPipeline

-- A sampled bit matrix as block art, two characters per module.
function qdMatrixAscii pM
   local tW, tH, tX, tY, tLine, tOut
   put bitMatrix_getWidth(pM) into tW
   put bitMatrix_getHeight(pM) into tH
   put empty into tOut
   repeat with tY = 0 to (tH - 1)
      put "   " into tLine
      repeat with tX = 0 to (tW - 1)
         if bitMatrix_get(pM, tX, tY) then
            put "##" after tLine
         else
            put "  " after tLine
         end if
      end repeat
      put tLine & return after tOut
   end repeat
   return tOut
end qdMatrixAscii

-- ==========================================================================
-- Samples tab: the seven embedded images and their known texts.
-- ==========================================================================

command qdHandleSamples pRole
   if pRole is "runAll" then
      qdRunAllSamples
   else
      qdLoadSample pRole
      qdShowTab "decode"
   end if
end qdHandleSamples

command qdRunAllSamples
   local tOldDelim, tKey, tOut, tT0
   put 0 into sQdPass
   put 0 into sQdFail
   put "== samples: each line is one decode against the known text ==" & return into tOut
   put tOut into field "samples:out"
   put the milliseconds into tT0
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   repeat for each item tKey in kQdSamples
      qdCheckSample tKey, qdSampleHints(tKey), true
   end repeat
   set the itemDelimiter to tOldDelim
   -- the negative: an inverted symbol WITHOUT its flag must fail, or the flag means nothing
   qdCheckSample "inverted", "TRY_HARDER", false
   put return & "      " & sQdPass & " passed, " & sQdFail & " failed, " & (sQdPass + sQdFail) & " checks in " \
         & (the milliseconds - tT0) & " ms - select this block and copy it into the OXT pass record" & return after field "samples:out"
   if sQdFail = 0 then
      uiStatus "All " & sQdPass & " sample checks passed on this engine.", "ok"
   else
      uiStatus sQdFail & " sample check(s) FAILED - see the Samples log.", "bad"
   end if
end qdRunAllSamples

-- One sample through the robust call: pExpectDecode true means the text must
-- match; false means the decode must FAIL with a NotFound error.
command qdCheckSample pKey, pHints, pExpectDecode
   local tRes, tT0, tMs, tGot, tWant, tOk, tLine, tErr
   -- byte-exact: `is` alone folds case (the suite's reporter lesson)
   set the caseSensitive to true
   put the milliseconds into tT0
   try
      put qrDecodeResultRobust(qdSampleData(pKey), pHints) into tRes
   catch tErr
      put empty into tRes
      put "THREW: " & tErr into tRes["error"]
   end try
   put (the milliseconds - tT0) into tMs
   if pExpectDecode then
      put textEncode(tRes["text"], "UTF-8") into tGot
      put qdHexToBytes(qdSampleTextHex(pKey)) into tWant
      put ((tRes["error"] is empty) and (tGot is tWant) and (the number of bytes of tGot = the number of bytes of tWant)) into tOk
      if tOk then
         put "PASS  " & qdSampleLabel(pKey) & " [" & pHints & "] " & tMs & " ms, " & tRes["strategy"] & " " & tRes["procW"] & "x" & tRes["procH"] into tLine
         if tRes["mirrored"] is true then
            put ", mirrored" after tLine
         end if
         if tRes["inverted"] is true then
            put ", inverted" after tLine
         end if
      else if tRes["error"] is not empty then
         put "FAIL  " & qdSampleLabel(pKey) & " [" & pHints & "] " & tMs & " ms: " & tRes["error"] into tLine
      else
         put "FAIL  " & qdSampleLabel(pKey) & " [" & pHints & "] " & tMs & " ms: got " & quote & tRes["text"] & quote & ", expected " & quote & qdSampleText(pKey) & quote into tLine
      end if
   else
      put (tRes["error"] begins with "NotFound") into tOk
      if tOk then
         put "PASS  " & qdSampleLabel(pKey) & " [" & pHints & "] fails without ALSO_INVERTED, as it must: " & tRes["error"] into tLine
      else
         put "FAIL  " & qdSampleLabel(pKey) & " [" & pHints & "] decoded WITHOUT its flag (error: " & scShow(tRes["error"]) & ")" into tLine
      end if
   end if
   if tOk then
      add 1 to sQdPass
   else
      add 1 to sQdFail
   end if
   put tLine & return after field "samples:out"
   set the vscroll of field "samples:out" to the formattedHeight of field "samples:out"
end qdCheckSample

function qdSampleLabel pKey
   if pKey is "v1num" then return "v1 numeric (v01-L-num.png)"
   if pKey is "mirror" then return "mirrored symbol (mirror-v3Q.png)"
   if pKey is "inverted" then return "inverted, white on black (inverted-v3Q.png)"
   if pKey is "utf8" then return "UTF-8 bytes (utf8-bytes.png)"
   if pKey is "scale1" then return "1 px per module (scale1-v3L.png)"
   if pKey is "rot25" then return "rotated 25 degrees (rot+25-v3Q.png)"
   if pKey is "photo" then return "a real photograph (hello_world.png)"
   return pKey
end qdSampleLabel

-- The hints each sample needs; only the inverted one needs more than TRY_HARDER.
function qdSampleHints pKey
   if pKey is "inverted" then return "TRY_HARDER,ALSO_INVERTED"
   return "TRY_HARDER"
end qdSampleHints

-- The known text as hex of its UTF-8 bytes (this file is pure ASCII, and the
-- UTF-8 sample's text is not).
function qdSampleTextHex pKey
   if pKey is "v1num" then return "393431393835373133303433323039333030333939"
   if pKey is "mirror" then return "524f54415445204d45203132333435204f70656e5854616c6b"
   if pKey is "inverted" then return "524f54415445204d45203132333435204f70656e5854616c6b"
   if pKey is "utf8" then return "636166c3a920e2809320c3bc62657220e282ac203132"
   if pKey is "scale1" then return "6f6e6520706978656c20706572206d6f64756c65"
   if pKey is "rot25" then return "524f54415445204d45203132333435204f70656e5854616c6b"
   if pKey is "photo" then return "48656c6c6f20776f726c6421"
   return empty
end qdSampleTextHex

function qdSampleText pKey
   return textDecode(qdHexToBytes(qdSampleTextHex(pKey)), "UTF-8")
end qdSampleText

-- The sample images themselves: PNG bytes, base64 in the source. Five are from
-- qr/fixtures/synthetic (generated by tools/gen_synthetic_fixtures.py from an
-- independent encoder), hello_world.png is the upstream golden photograph.
function qdSampleData pKey
   local tB64
   put empty into tB64
   if pKey is "v1num" then
      put "iVBORw0KGgoAAAANSUhEUgAAAHQAAAB0CAAAAABx8Un7AAAA/0lEQVR42u3ZSwrFIAxAUfe/" \
            & "6b5pEfN7MUbKdVi0p9BgEh1PwxigoKCgoKAfR4cy3nPec73rQPvQ5c+fUOlDPO8D7UHnF2vB" \
            & "41kHei86z4msA70XXcGg96PR5+VZBjSFagWWJ4C2V4OgKdRsfoQkXtq1gW7rT60A0XDtY0DP" \
            & "olbgaAndkwBAz6OrZlcLGusgBLQfVQsqJZCkDSKUxEHLUK0g8x5whCsH0FI0mgDSDRRoKRop" \
            & "wix8a9cGmkI9Bxpm4xstzEDLUeviQCrQrMQOeh8qBYrUSG8JJNBS1LPZl9wqgqbRfy4IvAU3" \
            & "6Hk0cvjovQAE7UNPDFBQUFBQ0I+hP0AWa6tjN9blAAAAAElFTkSuQmCC" into tB64
   end if
   if pKey is "mirror" then
      put "iVBORw0KGgoAAAANSUhEUgAAAMMAAADDCAAAAAAaFPp2AAAB2klEQVR42u3bwZaDIAwFUP//" \
            & "p2f2PYV5gVjreFnZ1grXRQ4JcPzcvx0MDAwMDAwMDAwMDAwMDAwMDAynGI6/28vN7z6WrtLe" \
            & "GBgYVg3Br0fYXm4eahbGwsDAUDIMBzMc1nBsc1zQGwMDw9mG4S07MxEGBoZrDe80wXfbvTEw" \
            & "MLTnD6XQNXRdmwMxMDzGkKb5PVeX1SoZGJ5gWF0cG5UI6tW9y9YUGRieYAiG1VMxmKcdDAwM" \
            & "q4b5PCAdQpA6zB/VtMbOwMCQjmM+oqASELwTBgaGzhpZKaUPgsniQxkYGDrzhzToBMlGWlBM" \
            & "ywYMDAyddb7FTTFp1sDAwHCOoV7YK01HSlkIAwPDfk2gVA+sx680p2BgYOjcN1NL1cNNMaU3" \
            & "xsDAsGUIAkfpXOliRwwMDPuGUomvFIhKm1f350sMDAy12ftaXlBfs2dgYGjPH0onSNJItvhf" \
            & "BgaGc9bjSjX+IOJ989kyBoY7G0rnRXe+C1bwGBgYmgzbhfnS0nwa2BgYGJpq90Hv9XiT5igM" \
            & "DAwfMczHtgNpOkvDwMCwHZeCon660H5ZbGVg+L+GxV/rJ1JKlQAGBoZz6nzpP+b+z+1ZZ2B4" \
            & "quE+jYGBgYGBgYGBgYGBgYGBgYGBYaf9ArA69M/eeTNqAAAAAElFTkSuQmCC" into tB64
   end if
   if pKey is "inverted" then
      put "iVBORw0KGgoAAAANSUhEUgAAAMMAAADDCAAAAAAaFPp2AAABxElEQVR42u3bQW4DIRAEQP//" \
            & "08nd8pJuYNeRqD7Z8iq4FGnCDOT1EhERERERERERkc/5+TtvD7+9uvx547fBagwMDLOG6tPL" \
            & "5cYfTK7GwMAwa/hUHy7rUlDnLt+mqzEwMNxoqDYhwRaFgYHhP9eldA/BwMDwnCEVpjOBcSfx" \
            & "jR6IgeEYQzB52/jqa7NKBoYTDN+aHXzt3I6B4QRDujeoGv5q7MfAwLDJEGwuqkle1YVs/xUw" \
            & "MDBUFSWtUH3/sF6mGBgYgsHA5GB+PPa7p+1gYGBIF7msQcHXD6Z765sQBgaG4CCsrzJpn5Fe" \
            & "xmFgYNhUl1YGe2Prygk8AwPD0mFbwOzvsqaPMDAw7LwLl95p6e/DBDWNgYFh56FcP85Lh3j9" \
            & "wwwMDJvG9mkPX80EqlrFwMCwc9fRN+39OP7GW3EMDEcbghOyjZdcn7syw8BwqmGyagXdQNVJ" \
            & "PBIGhhMM6YQu2Cr0Q4BNxYmBgSFoCcYNf1WrHqlLDAwMk5Vi3Fj0B3Wb7sIxMDAs//WfPMYL" \
            & "5g4MDAx3G/rBXtVxPFKXGBjOMlRndNUu4e6JPQMDw+Scb+X/VR6++8PAcKpBRERERERERETk" \
            & "jPwCipoIR5lC/wIAAAAASUVORK5CYII=" into tB64
   end if
   if pKey is "utf8" then
      put "iVBORw0KGgoAAAANSUhEUgAAAIQAAACECAAAAAB0L9x7AAABP0lEQVR42u3awRLCIAyE4b7/" \
            & "S+vVcWCzFK3Z+nOpg1P8DhkIicejwThAgAABAgQIELdCHGK8fq/ecdYBkYUYBs9k8XeIuw6I" \
            & "PMQo0NRz9L5aB8R9EGpTA/GfiNkmBeL+CDU/XMj4MRC5iCrRdZ9fzbZBXIawLrBF0nvJrRzE" \
            & "ZYjZ4VQF6mjDUgcZiCyEWxDZmQeRiagWnyXAqti2HJggWiDcw8kpqlpJMojWCOfCoy4/TuIM" \
            & "IgshD5qiCVMdfqcSXRAtEKuJiUp6reAF0R5RFrqqJGVhkwORg6gSW+fCvN2wB9EC4RbNZp9V" \
            & "YNuBCaIVYvWPPWcK7yDyEKtFdbUZOckuiAyE24hfab6dOkVBRCCcYutHOj8gIhBVkd2BgMhE" \
            & "OPNWk21nswLRBrHboFeXYBB5iF8MECBAgAABAkQ04glO/IMS05cWWQAAAABJRU5ErkJggg==" into tB64
   end if
   if pKey is "scale1" then
      put "iVBORw0KGgoAAAANSUhEUgAAACUAAAAlCAAAAADg9X/fAAAAzElEQVR42s1U0RLCMAzi/386" \
            & "nrdCoMmDb3Nena2MNkCG+uXCOyg813eCHlwV6jwA2NBqfx2mG3dWByrGjoJTLaiDDbJxLtUY" \
            & "n6vGliW2nHpRoVTrmYmLkoaumHrZnDLU0L7pVeEwgCLE8eeOKl9UqIGi1mVEnRPnOiMSgTDH" \
            & "3aZebZLfVSOKtlfh9lF6xO6xo/7xIim3+Qj7qTLXHiLWqJZ88WjK2p5VVOQLoYSeciWafvRQ" \
            & "Wb6YgrWHLCeotbdDr9sh+R/dON3+u7fcB9Heo4elTH/cAAAAAElFTkSuQmCC" into tB64
   end if
   if pKey is "rot25" then
      put "iVBORw0KGgoAAAANSUhEUgAAAQQAAAEECAAAAADrYxXWAAAJq0lEQVR42u2d0ZbbMAhE+f+f" \
            & "Vk9PH5rYzAyyJSzF7NOedjcbXyEEAyjW6qtZISgIBaEgFISCUBAKQkEoCAWhIBSEglAQCkJB" \
            & "KAgFoSAUhIJQEApCQSgIBaEgFISCUBAKQkHYH4JZQbC/XwVhBwyWwWB1DFkQlsZgWQxWxjAf" \
            & "wgbmYNMNYYNdMR3CDs7BEgxheQyWYgiLY7AkQzhxeBEEdmq+AMLng9riAVQGhOPjLofBEnbD" \
            & "+XEXMwXLMQSE4QUQmPW/wCd4hvCFwd4CwU0lDUVSPwcBG8LXv7ZFdoetYgg/B2EzQ5gIoccQ" \
            & "2ief34DQbwj//s0NL7eG0GUIH2/liY1hDxgCTjAf8pA21RD8UMl/0AezKptpCODp/EDpByGQ" \
            & "pNGl9KjaMg2Ch+HsNz/+75cgIMXEMwT77wsfjRvnxQlnDOwAPaL6mQTKXVj/AJVvyPaDQDBQ" \
            & "Q6Cvtx8EKiiZNhh17m4CwX9GGUT473DuwZHcpMEiKf8ZP06QaRimhM0YA2cgSlZ7QcC1lg+b" \
            & "aKFAyfaEwMLm743xaRkBQ2if58qyEA5tKdxHBvPrb59oczQHm+QGCQZ4KqAHQ950RQhq+3JD" \
            & "IG8Me9P9IJxTJcaA1HOHu8mJ24Edn/0QXAxLng7Rw0y6e5VmtdNhu9ARGaTghgtdadbhB9aF" \
            & "gNOBY62FrbMyhAHJ1Yzt0MD7hsuo1tkMSHJQznscgn+S+0t3cg7EEHxJbsRZYRMMQVm89214" \
            & "NxiOui5jsCmGQC0efItyMBFpjkiwLMEQThYPNgbKx7Uh3NwUNujxD45AWbwx0+HZOUq7bpiD" \
            & "DbOBjjK8I5rJyEJa3A0MNm4fkAq0SdGMVetjrucGhhwIpz9IfuNg+VHXcweDTWNgvkx8dGOM" \
            & "GlHcsCO5gMFam4pBnWjWsA8h1Rt6wnZjGHZEmvr6XjvHWq6lTtb8E7YHwwwIPhK2n7khOK0v" \
            & "Pc4hDwINb3nEfFZbWCzIchAfQwaEL0UAhbeRtQM/gMMOFxhwobMhfDedofBWiWanCtVpmeVu" \
            & "cA6iJAhc9Ph2XD3ZIdw5pndOpyFMheAHR6wOcYqV3BUVLrS/+ccGnoxuyvOdUJ2tlcdFZEUv" \
            & "9s1O8wmyRUnWIZqvPJMm14GGMDxsRokiLrYeT0mpLw43hNEQSKIoIYATpLkd8CMNYTKESG3y" \
            & "kDQGR0NGGsJNCHaMapx3zPvYmA4nqxGDDOEeBPMDpVj95GQKJLykkcNtQ7gPwdhkuIrje+ei" \
            & "wM8+D6Hh0Z3AqJcbC0qDltV6S4NgarDPoGWAt4CMX7lUpkrMd4z+cnCN8Hzi49fzX8ZU0pis" \
            & "MWqblI8rU564nHrNEAbkDljH6NFDaI1CRCEBavMTKPT3UbbsfCvV5S5xPbnuIK5FIPXjnsNd" \
            & "xpx4IeZC8LQvcdijxw+4MzNWiPHChpYFAfap4kSRJRR+scpxHByDpUFgEXu0B/EgIYA8lKvU" \
            & "Doa8gqyxW0JwFY6I0J35EsSQWZVGVg1KbF/LCETo3sRZr0la2BwQEs5dCKCVpytxZquSB6Ef" \
            & "A7B4fDIGDYFVYJ5Tm1mR2qu10NyKe14csaZBwEuDGhb0ih5tQfVt3QqULkPA7h7yURWqGOGI" \
            & "inahf80ur34jp5tnnrRCxdTL7pmhFAinRpTWMbpDAsBTen19cCoRAiyMqIRO1l15A1RkcCpn" \
            & "O7iN10Q38HNPVYcGDVBLjATStEXG8d5+ikRHs4ZEh4TN3nOxOJ4kHio6moLhzqgEWiQ11Oqr" \
            & "CX7ZhXe1PwXBqF2fh2SdSSXyFP5+IvLUQxCw2q+vCJCB0rG9k6Wh4zDYpT0QUftBlkADJdoS" \
            & "e0hDB2Kwi44grvaTAOdUh1ByVdeg8XwI+GkjCRb1E1yvCg8az4PQ1XTBlCAQMyGvZ1KjegpC" \
            & "pCaEG5TBzEdEoGhOy1/eSKCI3GA/tmz4j03EsjDsjk1cgEDWi7XgyFoUeAXtMi6LKZcgoMXE" \
            & "xwfpzGaJoq/D9RRuJkNQ8iJKDFEHvBcW+DocHcTOghByAs1PBxrTF4lAgYX7gfc+22VD4Gpz" \
            & "gGWgCS8y+XHfEHogBPJib/0N35IBh8NCJ8gRVUuDwNT+ngIqsAw3Z9AjQGkQtNrP3ybMRGUb" \
            & "R8M+YUzwbNcMAWOQqogrxaodEBFwEiD0X3PS+A9juDKQHMygEwLLoqCawIHx+beA1LgChEgP" \
            & "Irw4rNH5NxqQPAHhYm+9X6EKvAIoX4u27gwIMjGkvyZLWFB4iVR8EyBcH7KAozt9piSa11oa" \
            & "hH5DoGEG7neV4eWw1KkHQr8hHNu6/UTRYooSyxJGCGw2xxBopYDOvdOzdNJnJ9kkQ6DUelvz" \
            & "jpvoI3/Jk9y7x6501UAaAtlEp2JVBgQ5dhVs68bNa6gjK6a2tDQIrAJD5taOfl9fIyc30fiG" \
            & "DYsaApFTTbZPIR9vsbv1PDMbWZHtgADlVBjmBHy8vl7BUDN8KgQpp3Y3Z5nFr1eQe6blQBBy" \
            & "Kp9carrxJKpekt6WlLC5f+zKb+sOLC78qxPa1i5qjNw5NJEp6qIbUy8RqkQIgY8F5oVkDoGp" \
            & "sqwBKhsCFteDd3953UqRzospCcNlCKjPXFaoTvrZRfVySK3lNgRf+I0IbI5o5h+2upKzAITL" \
            & "AhuRRpDkjg7bJdp6+5VWL7Zwm9dIlWHWZ6uO6G1u6rkMX0/a5LHBZqiehoCv1qZ5TrxRKTBD" \
            & "tQAEfrU2k1MbvmnBAq5n+CE54OoAZhm+nBrTF4nrGewchioSaoylte6JT2ZgC0GQGoPf0xvM" \
            & "ovAZtIZjDCjzHXIDCUJnSAjTILBpoJiKH+OzBQQuE7NYOcZnFwhqapDpi+m7YdKHYflpd7i+" \
            & "nrwb5ny4tp92yzMwcMPSYrkDw4DVMZE5BmTuTSDgDEMEAvS+mKnvsbUkDDJQCk7N7Akhds+o" \
            & "7k+z/SEEo+vZw7DPbgeSe/rOwX4QAvnALywleZ2tW0IIrqU3DURd6paOUV4mFO9N2BFCZAFl" \
            & "f9xWYXNAh7tuCG1vCPxCpeZ3IfjG0DaGAA4Hcg3LL4XNXQ7A4EjUqyC4H0O+f9h86yjIwPAw" \
            & "hJ7h2HkYnnGMLdAzbz8PgVq8vR5C5PauN0Bo6J6A34SAuxDm6+wLQYh+Nmb7bQiqAcreASHQ" \
            & "HfmDYbPEMOl6sdUhtMBFc2+A4N8ZkLEhloLAL69pb4HAJsNfBGFOu+Z2EFpWeLAJhPZyCM27" \
            & "yfV1EBKdw8oQ0pzDJhBaQSgICZ5xBwgvPiILQkEoCAWhIBSEglAQCkJBKAgFoSAUhIJQEApC" \
            & "QSgIBaEgFISCUBAKQkEoCAWhIBSEglAQfujrDx6k+BxcfUAkAAAAAElFTkSuQmCC" into tB64
   end if
   if pKey is "photo" then
      put "iVBORw0KGgoAAAANSUhEUgAAAMgAAADICAYAAACtWK6eAAAL+ElEQVR4Xu3dUXYbSw4DUHn/" \
            & "i/ZsYNQ3RxhMdVt4vwxIFEgUS3Kc9/P7+/v72n9TYAr8VwV+ZpBNxhR4r8AMsumYAhcKzCAb" \
            & "jykwg2wGpsBnCmyDfKbbUF+iwAzyJY3eMT9TYAb5TLehvkSBGeRLGr1jfqbADPKZbkN9iQIz" \
            & "yJc0esf8TIEZ5DPdhvoSBWaQL2n0jvmZAjPIZ7oN9SUKzCBf0ugd8zMFZpDPdBvqSxSIDfLz" \
            & "8/OnpdKvy6TnV36Jq/rKL7zq3z2u84v/DAKFJHA6YMrPBuKCUv6Uv/idjuv84jeDzCCakUfH" \
            & "Z5By+yRwegMrv46n+sovvOrfPa7zi/82yDaIZuTR8Rmk3D4JnN7Ayq/jqb7yC6/6d4/r/OK/" \
            & "DbINohl5dHwGKbdPAqc3sPLreKqv/MKr/t3jOr/41zdISlAHSOMakJT/3fO3+aX9Eb7NfwYJ" \
            & "f45wvIEh//aASZ803uY/g4QDpgbXGxjyb/OTPmm8zX8GCQdMDa43MOTf5id90nib/wwSDpga" \
            & "XG9gyL/NT/qk8Tb/GSQcMDW43sCQf5uf9Enjbf4zSDhganC9gSH/Nj/pk8bb/GeQcMDU4HoD" \
            & "Q/5tftInjbf5HzeIDpgKqJ9jqP7w1//7GOl39/6J3wxy+AbWgD3doBpAxdvnV/0ZZAa5nJF0" \
            & "QDWAiqf1hVf9GWQGmUEuFJhBZpAZZAZ5r8Bf/wygJ0b7/HrCKN7mr/rbINsg2yDbINsg7xTY" \
            & "BrneIdsghzcIV3zIr51fBlN9xffEKv/Dc22BNSCqrwG5e37x0/kUl36qL7zqb4OEN3S9QSE/" \
            & "DkCYX+dXfcU14KovvOrPIOUBiRsU8uMAhPk1oKqvuPRTfeFVfwYpD0jcoJAfByDMrwFVfcWl" \
            & "n+oLr/ozSHlA4gaF/DgAYX4NqOorLv1UX3jVn0HKAxI3KOTHAQjza0BVX3Hpp/rCq/4MUh6Q" \
            & "uEEhPw5AmF8DqvqKSz/VF171Z5CHD4garHg6YMKrvuIacNUXXvVnkBnkckY0YBpQDaDiaX3h" \
            & "VX8GmUFmkAsFZpAZZAaZQd4roCeCVrTwWuGKq77wiou/6guv+oqn9YVX/W2QbZBtkG2QbZB3" \
            & "CmgD6AYWXje04ml94VV/G2QbZBvkzhtEDm7HdQOmN1Cbf5r/6edv8z++QdIGp/i2wCm/Nv7p" \
            & "52/zn0HCJ1Z7gNv52wP2dP4zyAwSfQZpG0D52wafQWaQGWQf0ntf8+qGu3u8fQO3z9/mvw2y" \
            & "DbINsg2yDdL6QWF7Qyj/4zeIDnj3uH4Okjbo7vi790f81D/h608sEbh7XALffcBT/nfvj/jp" \
            & "/MLPIFBIAs8gGrGzcfVP7GaQGUQz8uj4DFJunwTeBik3IEyv/in9Nsg2iGbk0fEZpNw+CbwN" \
            & "Um5AmF79U/ptkG0Qzcij48cN8mj1/g/ktWFEIW2w8i9+rUC8QSYwBA7//yczyNkJm0HK+m+D" \
            & "lAUup59B2gJvg5QV7qafQbr6vrZBygKX088gbYG3QcoKd9PPIF19t0HK+rbTzyBlhffEKgtc" \
            & "Th8bJB2A9Hzp16Dir/yn8dIv5ZfmF17xtv6qP4OEv3KbDmCKZ4PD86X5hVd8BpFCiEtApU8H" \
            & "9DS+fb40v/CKq7+p/qq/DRLesGmDUjwbHJ4vzS+84jOIFNoGiRQ6bcCI/Ov1mkFCBSWg0qcD" \
            & "dBrfPl+aX3jF1d9Uf9XfEyt8gqQNSvFscHi+NL/wis8gUmhPrEih0waMyP+FJ1YqgPBqsPCK" \
            & "pzeU8qfxu/NLzyd8en7hVT9+YqlAGp9Bfi8lbOuT9i/Fa8B1fuHFbwb5vfcAqsEaEA3A3ePp" \
            & "+YXX+WeQGUQzcjSuAdcFIbwON4PMIJqRo3EN+AwS/j6Fups2QPnT+N35pecTPj2/8Kq/DbIN" \
            & "ohk5GteAb4Nsg+xbrAsF/rxBdEBdX+kNk+YXXnGd//T5Un46v+KqL7z0E/74E6stQDu/BFZc" \
            & "/NRg4VU/zS+86ivePh/r/7ZPCAZtAdr5JbDi4qf2CK/6aX7hVV/x9vlYfwa5luj0AKh+e4CU" \
            & "X/w0gIqrvvApvz2xoHAqsBqoAVB94VU/zS+86ivePh/rb4Nsg1wpoAGdQWSxMK4GKL0a1M4v" \
            & "foqL3+nzpfx0fsVVX3jpJ/yeWHtiXSqgAU0HkAMa/hws5ff1BokFDBuoARG/9gCn+U/jpa/i" \
            & "Mwj+qgkFnEGqGyg1mPqn+Awyg9x6wGeQ8Aa++xNEN5Tidz9fm98MMoNceqQ9gDJoOqCn8Tqf" \
            & "4nti7Ym1J9aFAjPIDDKDzCDvFdAThis4fCIqv/ilTxjVT/Ofxut8ih/fICKYxtUg5f/rA5qe" \
            & "X/h2XP1V/8RvBoFCErjeoPCfDhU/DYjOL3w7rvOl/GeQGST6Fq1tAOWfQaQQ4hJQ6XUDKb/w" \
            & "qp/mF171U/7Kn8Z1vpT/Nsg2yDbInb/FSm8Q4XXDCK8bSPmFV/00v/Cqn/JX/jSu86X8t0G2" \
            & "QbZBtkE+v6d0A9VvsH2Lddm8uv6nf+X289G9B7LeoNAgUkn8hVe8fcGIv+qL/59/YkmANF5v" \
            & "0AyyDZIO6Un8DHKtvm7wVL8Ur9nZBpFCiNcbtA2yDRLO6FH4DLINcnQA7158BplB7j6jR/nN" \
            & "IDPI0QG8e/EZZAaJPiTdfcDFT9/CCK/4aYOJXxpv65fyEz7+FksNFoG7x9sNln5pfeVv65/y" \
            & "b/NT/hkECrUbrAFO6yu/BiSNp/zT+il+BplB0hm6xM8g5X+0oNq9f0jebrBu+LS+8v+DBNEf" \
            & "SflHxf8H4G2QbZD/wRi9TzGDbINEA6YbPh0w5Y/I/wM45f8PJap/ZBtkG6Q6YDNI+S/TVbv3" \
            & "er10w6YNTvMLn+qj86l+ihd/5Rc+jdc3yOkDSqB0ANr5xU/1FVd/VD/Fp/yET+MzSHkDnh4w" \
            & "DUg64Ck+5Sd8Gp9BZpDLGTptcBkwNYDwM8gMMoNcKDCDzCAzyAzyXoH0CcEVHRpQ/FRfcT1h" \
            & "VD/Fp/yET+PbIOEAqwGnB0z80gFP8Sk/4dP4cYNogNIDpg0UPuUnvPQ5zS/lL7zi7fPPIOUN" \
            & "ogYrPoNcKzSDaIIQl4B3H8C781N7xF94xdVf4RXfBtkG0YxE8RkkHLDTAqp++4bS9N2dX8pf" \
            & "eMXb/dkGCQ2uBqbxGWSfQdIZusTrhrn7AN6dn5on/sIrrv4Kr/g2yDaIZiSKzyDhgJ0WUPV1" \
            & "QwkfTdfr9Urrt/E632l9xE/xbZAZPHqicsDKv5KtC0D8FJ9BZpAZ5EKBGWQGmUFmkPcK6I2s" \
            & "FS68Vrjiaf02XvxP6yN+im+DbINsg2yDbIO8U0A3vDYQb+B9SP+JbiA1SA1QXA1W/RQvfoqn" \
            & "9dt48Ze+wiuu8wmv+J5Y5SdWvYEhfw7Iw/PrfIrPIOEA6IacQa5H8LR+M8jv76UGaYNSvBqk" \
            & "eLv+0/NLP8W3QbZBqhcIBzDUX/nT+AwSNqh9w6rB7fpPzy/9FJ9BZpBtkP0c5NzPQfYhfR/S" \
            & "93OQCwVmkBkkMojegO14+sYWvs1fBrw7v1QfnU/6qP7xzyAi2I6nAgvf5q8BuDu/VB+dT/qo" \
            & "/gxS/pCuBqRxDYAGKK0vvPgJr7jOl9afQWYQzWAUTwdUxWcQKRTGU4GFD+kRrgG8Oz8eEH9A" \
            & "55M+qr8Nsg2iGYni6YCq+AwihcJ4KrDwIT3CNYB358cDboOkEmV4DdDTB1Dny9QzWvo5w/Wf" \
            & "0PnS+vUnVirAabwEVoPEP82f4sVPcdUXXvql+VVf8RkECqlBarAakOZP8eKnuOoLL/3S/Kqv" \
            & "+Awyg2hGLuPpAM8gkfznwRoANVgnSPOnePFTXPWFl35pftVXfBtkG0Qzsg2SKKQbIMl9B6xu" \
            & "sPT8af4Un2qs+sov/dL8qq/4Nsg2iGZkGyRRSDdAkvsOWN1g6fnT/Ck+1Vj1lV/6pflVX/F4" \
            & "g6jA4lPgyQrMIE/u3rjXFZhB6hKvwJMVmEGe3L1xryswg9QlXoEnKzCDPLl7415XYAapS7wC" \
            & "T1ZgBnly98a9rsAMUpd4BZ6swAzy5O6Ne12BGaQu8Qo8WYEZ5MndG/e6AjNIXeIVeLICM8iT" \
            & "uzfudQVmkLrEK/BkBWaQJ3dv3OsK/AfkMf5suLokAQAAAABJRU5ErkJggg==" into tB64
   end if
   if tB64 is empty then
      return empty
   end if
   return base64Decode(tB64)
end qdSampleData

-- ==========================================================================
-- About tab.
-- ==========================================================================

command qdHandleAbout pRole
   if pRole is "selfcheck" then
      put empty into field "about:log"
      qdScRun
   end if
end qdHandleAbout

-- ==========================================================================
-- The boot self-check (the carried block owns the plumbing; this handler
-- owns the assertions). Nothing here hosts, connects, binds or takes a
-- singleton: the decodes are pure computation on bytes carried in the
-- script, and the PNG decode uses the library's own private invisible
-- host stack.
-- ==========================================================================

command qdScRun
   local tMissing, tVer, tErr, tOldDelim, tCount
   scBegin "about:log"
   put empty into tVer
   try
      put qrLibraryVersion() into tVer
   catch tErr
      put "THREW: " & tErr into tVer
   end try
   scAssert "the embedded library answers qrLibraryVersion() = 0.2.0 (got " & scShow(tVer) & ")", (tVer is "0.2.0")
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put the number of items of kQdScControls into tCount
   set the itemDelimiter to tOldDelim
   put scMissing(kQdScControls) into tMissing
   if tMissing is empty then
      scAssert "all " & tCount & " controls this script names exist", true
   else
      scAssert "all " & tCount & " controls this script names exist (missing: " & tMissing & ")", false
   end if
   scLine "      four embedded samples through qrDecodeResultRobust (pure computation):"
   qdScSample "v1num", "TRY_HARDER"
   qdScSample "mirror", "TRY_HARDER"
   qdScSample "inverted", "TRY_HARDER,ALSO_INVERTED"
   qdScSample "utf8", "TRY_HARDER"
   scArmProbe
end qdScRun

command qdScSample pKey, pHints
   local tRes, tErr, tGot, tWant, tOk, tDetail
   set the caseSensitive to true
   try
      put qrDecodeResultRobust(qdSampleData(pKey), pHints) into tRes
   catch tErr
      put empty into tRes
      put "THREW: " & tErr into tRes["error"]
   end try
   put textEncode(tRes["text"], "UTF-8") into tGot
   put qdHexToBytes(qdSampleTextHex(pKey)) into tWant
   put ((tRes["error"] is empty) and (tGot is tWant) and (the number of bytes of tGot = the number of bytes of tWant)) into tOk
   if tRes["error"] is not empty then
      put "error: " & tRes["error"] into tDetail
   else
      put tRes["strategy"] & " " & tRes["procW"] & "x" & tRes["procH"] into tDetail
   end if
   scAssert qdSampleLabel(pKey) & " decodes to its known text [" & pHints & "] (" & tDetail & ")", tOk
end qdScSample
