script "xtQRdecoder"
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
--   3. shl() is precision-safe: the spec's `u32(a * (2^n))` overflows 2^53 and
--      silently loses LOW-order bits when shifting a full 32-bit word left by a
--      large count (e.g. BitMatrix.getEnclosingRectangle). See shl() below.
--   4. binaryDecode needs an OUTPUT variable; the spec's one-liner for
--      floatToIntBits is not valid xTalk. Corrected below.
-- =====================================================================


-- ---- universal 32-bit constants (decimal; hex shown in comments) -----
constant kUInt32   = 4294967296     -- 2^32
constant kUIntMax  = 4294967295     -- 0xFFFFFFFF   (Java -1 in our unsigned model)
constant kMaxInt32 = 2147483648     -- 2^31; sign-bit threshold (NOT Integer.MAX_VALUE = 2^31-1)


-- ---- core normalisation ----------------------------------------------
-- Normalise any integer into the unsigned 32-bit range [0, 2^32).
-- Java/PHP -1 -> 4294967295 ; -16777216 -> 4278190080 ; 2^32 -> 0.
function u32 n
   put n mod kUInt32 into n
   if n < 0 then add kUInt32 to n
   return n
end u32

-- Mask to a single unsigned byte (the ubiquitous Java "& 0xFF").
function u8 n
   return (n bitAnd 255)            -- 0xFF
end u8


-- ---- shift emulation (Java <<, >>>, >>) ------------------------------
-- xTalk has no shift operators; emulate with arithmetic. The shift count
-- is masked to 0..31 to match Java's `count & 31` for 32-bit ints.

-- Logical/arithmetic LEFT shift, 32-bit  (Java: a << n).
-- PRECISION-SAFE: drop the bits that would shift out past bit 31 BEFORE
-- multiplying, so the product stays < 2^32 (well under the 2^53 exact limit).
-- A naive u32(a * 2^n) loses low bits when a is large and n is large.
function shl a, n
   local m
   put (n mod 32) into n
   put u32(a) into a
   put (2 ^ (32 - n)) into m         -- modulus discards the out-shifted high bits
   return ((a mod m) * (2 ^ n))      -- result is already in [0, 2^32)
end shl

-- UNSIGNED right shift  (Java: a >>> n). Operand treated as unsigned 32-bit.
-- Replaces the PHP shims uRShift() and sdvig3().
function uShr a, n
   put (n mod 32) into n
   return (u32(a) div (2 ^ n))
end uShr

-- ARITHMETIC right shift  (Java: a >> n) on a word interpreted as SIGNED 32-bit.
-- Returns the unsigned 32-bit BIT-PATTERN of the result (i.e. sign-extended).
function aShr a, n
   local d
   put (n mod 32) into n
   put u32(a) into a
   put (2 ^ n) into d
   if a < kMaxInt32 then
      return (a div d)                                  -- top bit clear: same as >>>
   else
      -- top bit set (negative): OR in the high sign-extension bits.
      -- (kUInt32 - (kUInt32 div d)) is exactly the top-n-bits mask.
      return u32(((a div d) bitOr (kUInt32 - (kUInt32 div d))))
   end if
end aShr


-- ---- Integer.numberOfTrailingZeros -----------------------------------
-- Count low-order zero bits; i == 0 -> 32. Used by BitArray.getNextSet/Unset.
function numberOfTrailingZeros i
   local n
   put u32(i) into i
   if i = 0 then return 32
   put 0 into n
   repeat while (i bitAnd 1) = 0
      add 1 to n
      put (i div 2) into i
   end repeat
   return n
end numberOfTrailingZeros


-- ---- Java String.hashCode  (h = 31*h + c) over BYTES -----------------
-- Only used for equality/dedup, never on the decode-critical path. u32 each
-- step so the value matches Java's bit pattern exactly.
function hashCode s
   local h, k
   put 0 into h
   repeat with k = 1 to the number of bytes of s
      put u32((31 * h) + byteToNum(byte k of s)) into h
   end repeat
   return h
end hashCode


-- ---- Float.floatToIntBits --------------------------------------------
-- IEEE-754 single-precision raw bits. The spec's one-liner is NOT valid
-- xTalk (binaryDecode requires an output variable) -- corrected here.
-- binaryEncode/binaryDecode use machine byte order on both sides, so the
-- round-trip is endian-safe. Likely unused on the QR path (it appears only
-- in ResultPoint / PerspectiveTransform hashing) -- included for completeness.
function floatToIntBits f
   local tBits
   get binaryDecode("i", binaryEncode("f", f), tBits)
   return u32(tBits)
end floatToIntBits


-- ---- fill_array  (customFunctions.php) -------------------------------
-- Build a dense, 0-based array of pCount copies of pValue starting at pIndex.
-- QUIRK preserved from PHP: pCount <= 0 returns a SINGLE-element array (one
-- slot holding pValue). BitMatrix / binarizer sizing relies on this in
-- degenerate cases. In every real call site pIndex == 0 and pValue == 0, so
-- this reproduces the PHP "[0]" result, and the integer layer (incl. this
-- helper) is engine-verified by suite_qrCompat. The degenerate pCount<=0 branch
-- is not reached by the QR path; it is kept only for source fidelity.
function fill_array pIndex, pCount, pValue
   local tArr, k
   if pCount <= 0 then
      put pValue into tArr[pIndex]
      return tArr
   end if
   repeat with k = pIndex to (pIndex + pCount - 1)
      put pValue into tArr[k]
   end repeat
   return tArr
end fill_array


-- ---- System.arraycopy  (in place, for performance) -------------------
-- Copy pLen elements from pSrc[pSrcPos..] to pDest[pDestPos..]. 0-based,
-- matching the source. Pass BOTH arrays by reference (@) so the large bit /
-- luminance arrays are never copied by value (spec 5, 11).
-- CAVEAT: forward copy. If src and dest alias with overlapping FORWARD regions
-- the result differs from Java's temp-buffer semantics. No such overlapping
-- self-copy occurs on the QR decode path.
command arraycopy @pSrc, pSrcPos, @pDest, pDestPos, pLen
   local k
   repeat with k = 0 to (pLen - 1)
      put pSrc[pSrcPos + k] into pDest[pDestPos + k]
   end repeat
end arraycopy


-- ---- string byte access (0-based, like PHP $s[$i]) -------------------
-- Returns the unsigned byte value (0..255) at 0-based index i of string s.
-- Keeps call sites readable and 0-based (spec 6.7).
function byteAt s, i
   return byteToNum(byte (i + 1) of s)
end byteAt

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
   put fill_array(0, (pn + qn - 1), 0) into tProduct
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
   put fill_array(0, (n + pDegree), 0) into tProduct
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
   put fill_array(0, pTwoS, 0) into syndromeCoeffs
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

   -- run until r's degree is less than R/2  (R == 2t == number of EC codewords)
   repeat while poly_degree(r) >= (pTwoT div 2)
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
   put fill_array(0, numErrors, 0) into tRes
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
   put fill_array(0, s, 0) into tRes
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
   return ((pObj["bits"][(i div 32)] bitAnd shl(1, (i bitAnd 31))) <> 0)
end bitArray_get

command bitArray_set @pObj, i
   local w
   put (i div 32) into w
   put u32(pObj["bits"][w] bitOr shl(1, (i bitAnd 31))) into pObj["bits"][w]
end bitArray_set

command bitArray_flip @pObj, i
   local w
   put (i div 32) into w
   put u32(pObj["bits"][w] bitXor shl(1, (i bitAnd 31))) into pObj["bits"][w]
end bitArray_flip

command bitArray_setBulk @pObj, i, pNewBits
   put u32(pNewBits) into pObj["bits"][(i div 32)]
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
   put (tCurrent bitAnd u32(bitNot(shl(1, (pFrom bitAnd 31)) - 1))) into tCurrent
   repeat while tCurrent = 0
      add 1 to tBitsOffset
      if tBitsOffset = tWordCount then return tSize
      put pObj["bits"][tBitsOffset] into tCurrent
   end repeat
   put ((tBitsOffset * 32) + numberOfTrailingZeros(tCurrent)) into tResult
   return min(tResult, tSize)
end bitArray_getNextSet

-- index of the first unset bit at or after pFrom (returns size if none)
function bitArray_getNextUnset pObj, pFrom
   local tSize, tWordCount, tBitsOffset, tCurrent, tResult
   put pObj["size"] into tSize
   if pFrom >= tSize then return tSize
   put the number of elements of pObj["bits"] into tWordCount
   put (pFrom div 32) into tBitsOffset
   put u32(bitNot(pObj["bits"][tBitsOffset])) into tCurrent
   put (tCurrent bitAnd u32(bitNot(shl(1, (pFrom bitAnd 31)) - 1))) into tCurrent
   repeat while tCurrent = 0
      add 1 to tBitsOffset
      if tBitsOffset = tWordCount then return tSize
      put u32(bitNot(pObj["bits"][tBitsOffset])) into tCurrent
   end repeat
   put ((tBitsOffset * 32) + numberOfTrailingZeros(tCurrent)) into tResult
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
      put u32(shl(2, tLastBit) - shl(1, tFirstBit)) into tMask   -- ones firstBit..lastBit
      put u32(pObj["bits"][i] bitOr tMask) into pObj["bits"][i]
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
      put u32(shl(2, tLastBit) - shl(1, tFirstBit)) into tMask
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
      put u32(pObj["bits"][w] bitOr shl(1, (pObj["size"] bitAnd 31))) into pObj["bits"][w]
   end if
   add 1 to pObj["size"]
end bitArray_appendBit

-- append the low pNumBits of pValue, most-significant bit first
command bitArray_appendBits @pObj, pValue, pNumBits
   local nbl
   if (pNumBits < 0) or (pNumBits > 32) then throw "BitArray: numBits must be 0..32"
   bitArray_ensureCapacity pObj, (pObj["size"] + pNumBits)
   repeat with nbl = pNumBits down to 1
      bitArray_appendBit pObj, ((uShr(pValue, (nbl - 1)) bitAnd 1) = 1)
   end repeat
end bitArray_appendBits

command bitArray_xor @pObj, pOther
   local n, i
   if pObj["size"] <> pOther["size"] then throw "BitArray: sizes don't match"
   put the number of elements of pObj["bits"] into n
   repeat with i = 0 to (n - 1)
      put u32(pObj["bits"][i] bitXor pOther["bits"][i]) into pObj["bits"][i]
   end repeat
end bitArray_xor

-- read pNumBytes bytes (MSB-first) starting at bit pBitOffset; returns dense 0-based array
function bitArray_toBytes pObj, pBitOffset, pNumBytes
   local tOut, i, j, theByte, bo
   put pBitOffset into bo
   repeat with i = 0 to (pNumBytes - 1)
      put 0 into theByte
      repeat with j = 0 to 7
         if bitArray_get(pObj, bo) then put u32(theByte bitOr shl(1, (7 - j))) into theByte
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
      put u32(pObj["bits"][i]) into x
      put ((uShr(x, 1) bitAnd 1431655765) bitOr u32(shl((x bitAnd 1431655765), 1))) into x   -- 0x55555555
      put ((uShr(x, 2) bitAnd 858993459) bitOr u32(shl((x bitAnd 858993459), 2))) into x     -- 0x33333333
      put ((uShr(x, 4) bitAnd 252645135) bitOr u32(shl((x bitAnd 252645135), 4))) into x     -- 0x0f0f0f0f
      put ((uShr(x, 8) bitAnd 16711935) bitOr u32(shl((x bitAnd 16711935), 8))) into x       -- 0x00ff00ff
      put ((uShr(x, 16) bitAnd 65535) bitOr u32(shl((x bitAnd 65535), 16))) into x           -- 0x0000ffff
      put x into newBits[(tLen - i)]
   end repeat
   if tSize <> (tOldLen * 32) then
      put ((tOldLen * 32) - tSize) into leftOffset
      put uShr(newBits[0], leftOffset) into currentInt
      repeat with i = 1 to (tOldLen - 1)
         put newBits[i] into nextInt
         put u32(currentInt bitOr shl(nextInt, (32 - leftOffset))) into currentInt
         put currentInt into newBits[(i - 1)]
         put uShr(nextInt, leftOffset) into currentInt
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
-- get/getEnclosingRectangle/getTopLeftOnBit/getBottomRightOnBit use the Java
-- `theBits << (31-bit)` / `>>> bit` idioms. These are exactly why qrCompat.shl
-- is precision-safe: shl(theBits,31-bit)=0 iff the low (bit+1) bits are zero,
-- matching Java's overflow-discard semantics bit-for-bit (spec section 6.2).
--
-- NOTE: the giant hard-coded debug array literal in PHP BitMatrix::set() is
-- dead cruft and is intentionally NOT ported (spec section 8.1 warning).
-- =====================================================================

function bitMatrix_new pWidth, pHeight
   local tObj, tRowSize, tCount, k, tBits
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

function bitMatrix_get pObj, x, y
   local tOffset
   put (y * pObj["rowSize"] + (x div 32)) into tOffset
   return ((uShr(pObj["bits"][tOffset], (x bitAnd 31)) bitAnd 1) <> 0)
end bitMatrix_get

command bitMatrix_set @pObj, x, y
   local tOffset
   put (y * pObj["rowSize"] + (x div 32)) into tOffset
   put u32(pObj["bits"][tOffset] bitOr shl(1, (x bitAnd 31))) into pObj["bits"][tOffset]
end bitMatrix_set

command bitMatrix_unset @pObj, x, y
   local tOffset
   put (y * pObj["rowSize"] + (x div 32)) into tOffset
   put u32(pObj["bits"][tOffset] bitAnd u32(bitNot(shl(1, (x bitAnd 31))))) into pObj["bits"][tOffset]
end bitMatrix_unset

command bitMatrix_flip @pObj, x, y
   local tOffset
   put (y * pObj["rowSize"] + (x div 32)) into tOffset
   put u32(pObj["bits"][tOffset] bitXor shl(1, (x bitAnd 31))) into pObj["bits"][tOffset]
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
         put u32(pObj["bits"][tIdx] bitOr shl(1, (x bitAnd 31))) into pObj["bits"][tIdx]
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
      put u32(pRow["bits"][x]) into pObj["bits"][tOffset + x]
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
      put u32(pObj["bits"][i] bitXor pMask["bits"][i]) into pObj["bits"][i]
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
               repeat while shl(theBits, (31 - tBitN)) = 0
                  add 1 to tBitN
               end repeat
               if ((x32 * 32) + tBitN) < tLeft then put ((x32 * 32) + tBitN) into tLeft
            end if
            if ((x32 * 32) + 31) > tRight then
               put 31 into tBitN
               repeat while uShr(theBits, tBitN) = 0
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
   repeat while shl(theBits, (31 - tBitN)) = 0
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
   repeat while uShr(theBits, tBitN) = 0
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
      put shl((255 div (2 ^ (8 - toRead))), bitsToNotRead) into tMask
      put pObj["bytes"][pObj["byteOffset"]] into curByte
      put uShr((curByte bitAnd tMask), bitsToNotRead) into tResult
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
         put u32((shl(tResult, 8)) bitOr (curByte bitAnd 255)) into tResult
         add 1 to pObj["byteOffset"]
         subtract 8 from n
      end repeat
      if n > 0 then
         put (8 - n) into bitsToNotRead
         put shl((255 div (2 ^ bitsToNotRead)), bitsToNotRead) into tMask
         put pObj["bytes"][pObj["byteOffset"]] into curByte
         put u32((shl(tResult, n)) bitOr uShr((curByte bitAnd tMask), bitsToNotRead)) into tResult
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
   local tObj, p, o, r, g, b, n, tLum
   put pW into tObj["width"]
   put pH into tObj["height"]
   put (pW * pH) into n
   -- Hot loop (one iteration per pixel). Three behaviour-preserving speedups vs
   -- the naive form (spec section 11 -- this is the documented cost centre):
   --   * accumulate into a FLAT local (tLum) and store it into tObj["lum"] ONCE
   --     at the end, so each iteration does one array-key write instead of a
   --     nested tObj["lum"][idx] lookup-then-write;
   --   * use the loop counter p directly as the 0-based pixel index (idx == p);
   --   * carry the byte offset o with `add 4` instead of recomputing p*4.
   -- Result is bit-identical: pixel p reads bytes 4p+2/4p+3/4p+4 (R/G/B, the
   -- byte1=alpha,2=R,3=G,4=B layout of section 7.2) and writes lum[p].
   put 0 into o
   repeat with p = 0 to (n - 1)
      put byteToNum(byte (o + 2) of pRaw) into r
      put byteToNum(byte (o + 3) of pRaw) into g
      put byteToNum(byte (o + 4) of pRaw) into b
      if (r = g) and (g = b) then
         put r into tLum[p]
      else
         put trunc((r + (2 * g) + b) / 4) into tLum[p]
      end if
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

-- IMAGE-OBJECT PATH (section 7.1). Requires a working engine image object. A headless
-- engine may lack a default stack to host a control, so we ensure one exists
-- first; qr_imageprobe.lc confirms this path on a given engine.
--
-- Decode the image bytes to a raw 4-byte/pixel plane via the engine image
-- object, ONCE. Returns {["width"],["height"],["raw"]}. Separated from the
-- greyscale/downsample step so a robust reader can decode the (costly) image a
-- single time and then derive several luminance sources at different scales
-- from the same raw plane (spec section 11: the image decode + pixel loops dominate).
--
-- pMaxDim is accepted for signature compatibility but does not resize here:
-- downsampling is performed by the caller (luminanceSource_fromRawPlane), so this
-- handler always returns the full-resolution pixels. (The imageData layout after
-- an in-engine resize is build-specific, so resizing is left to the host app.)
function luminanceSource_decodeRawPlane pImageData, pMaxDim
   local tW, tH, tRaw, tName, e, tPlane
   -- ensure a host stack exists (ignore if a default one already does)
   try
      if there is not a stack "qrHostStack" then
         create invisible stack "qrHostStack"
      end if
   catch e
      -- a default stack may already be available; proceed regardless
   end try
   put "qrSrc_" & the milliseconds into tName       -- avoid name collisions
   create invisible image tName
   set the lockLoc of image tName to true
   put pImageData into image tName                  -- decode PNG/JPG/GIF/BMP
   put the formattedWidth of image tName into tW
   put the formattedHeight of image tName into tH
   set the width of image tName to tW
   set the height of image tName to tH
   put the imageData of image tName into tRaw       -- 4 bytes/pixel, row-major
   delete image tName
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
   local tW, tH, tStep
   put pPlane["width"] into tW
   put pPlane["height"] into tH
   put luminanceSource_stepForDims(tW, tH, pMaxDim) into tStep
   if tStep > 1 then
      return luminanceSource_downsampleRaw(tW, tH, pPlane["raw"], tStep)
   end if
   return luminanceSource_newFromImageData(tW, tH, pPlane["raw"])
end luminanceSource_fromRawPlane

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
-- pStep-th pixel in x and y (nearest-neighbour downsample). Reuses the verified
-- section 7.3 greyscale by reassembling a reduced 4-bpp raw and calling newFromImageData.
function luminanceSource_downsampleRaw pW, pH, pRaw, pStep
   local tOutW, tOutH, sx, sy, tOStep, o, tReduced
   put (((pW - 1) div pStep) + 1) into tOutW
   put (((pH - 1) div pStep) + 1) into tOutH
   put empty into tReduced
   -- Carry the source byte offset incrementally. Within a row each kept pixel is
   -- pStep source pixels (= pStep*4 bytes) past the previous one, so advance o by
   -- a constant add instead of recomputing ((sy*pStep)*pW + sx*pStep)*4 for every
   -- output pixel. The byte ranges copied are identical (same idiom as the
   -- per-pixel `add 4` in luminanceSource_newFromImageData).
   put (pStep * 4) into tOStep
   repeat with sy = 0 to (tOutH - 1)
      put (((sy * pStep) * pW) * 4) into o
      repeat with sx = 0 to (tOutW - 1)
         put (byte (o + 1) to (o + 4) of pRaw) after tReduced
         add tOStep to o
      end repeat
   end repeat
   return luminanceSource_newFromImageData(tOutW, tOutH, tReduced)
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

   return shl(bestValley, kLumShift)
end ghb_estimateBlackPoint

function ghb_getBlackMatrix pSrc
   local tW, tH, tLum, tMatrix, x, y, tRow, tRight, tLeft, tPixel
   local tBuckets, b, blackPoint, tOffset, tRowBase
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
         add 1 to tBuckets[uShr(tPixel, kLumShift)]
      end repeat
   end repeat

   put ghb_estimateBlackPoint(tBuckets) into blackPoint

   -- threshold the whole image: pixel < blackPoint => black
   repeat with y = 0 to (tH - 1)
      put (y * tW) into tOffset
      repeat with x = 0 to (tW - 1)
         if tLum[tOffset + x] < blackPoint then bitMatrix_set tMatrix, x, y
      end repeat
   end repeat

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
-- pLum (the whole luminance plane) and pBP (the black points) are taken BY
-- REFERENCE -- this command only reads them, but @ guarantees the large arrays
-- are never copied per block (this runs once per 8x8 block, i.e. tens of
-- thousands of times on a big image). Same big-array-by-ref idiom as arraycopy.
command hb_thresholdBlock @pMatrix, @pLum, @pBP, tBx, tBy, pSubW, pSubH, pW, pH
   local tXoff, tYoff, tTop, leftBlk, tSum, dy, dx, tAvg, yy, xx, tPixel
   local tNbBase, tRowY, tRowBase
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

   -- hoist the pixel-row base (and the row's y, reused as the set() y-arg) out of
   -- the inner loop: per-pixel index arithmetic drops to a single add (tRowBase +
   -- xx). The flat index and the (x,y) passed to bitMatrix_set are unchanged.
   repeat with yy = 0 to (kBlockSize - 1)
      put (tYoff + yy) into tRowY
      put ((tRowY * pW) + tXoff) into tRowBase
      repeat with xx = 0 to (kBlockSize - 1)
         put pLum[tRowBase + xx] into tPixel
         if tPixel <= tAvg then bitMatrix_set pMatrix, (tXoff + xx), tRowY
      end repeat
   end repeat
end hb_thresholdBlock

function hb_getBlackMatrix pSrc
   local tW, tH, tSubW, tSubH, tBP, tMatrix, tBx, tBy, tLum
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
   -- Hoist the luminance plane into a local ONCE, then pass it (and the black
   -- points) by reference per block, instead of re-evaluating pSrc["lum"] -- a
   -- subarray extraction -- on every one of the tSubW*tSubH iterations.
   put pSrc["lum"] into tLum
   repeat with tBy = 0 to (tSubH - 1)
      repeat with tBx = 0 to (tSubW - 1)
         hb_thresholdBlock tMatrix, tLum, tBP, tBx, tBy, tSubW, tSubH, tW, tH
      end repeat
   end repeat
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

-- flip the masked cells of the dimension x dimension matrix, in place
command dataMask_unmask @pBits, pDimension, pRef
   local i, j
   repeat with i = 0 to (pDimension - 1)
      repeat with j = 0 to (pDimension - 1)
         if dataMask_isMasked(pRef, i, j) then
            bitMatrix_flip pBits, j, i        -- (x=j, y=i)
         end if
      end repeat
   end repeat
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
   put u32(n) into n
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
      put fmt_popcount(u32(pFormatInfo1 bitXor targetInfo)) into d1
      if d1 < bestDifference then
         put sFmtData[i] into bestData
         put d1 into bestDifference
      end if
      if pFormatInfo1 <> pFormatInfo2 then
         put fmt_popcount(u32(pFormatInfo2 bitXor targetInfo)) into d2
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
   put ecl_forBits(uShr(pDataBits, 3) bitAnd 3) into tRes["ecLevel"]
   put (pDataBits bitAnd 7) into tRes["dataMask"]
   return tRes
end fmt_unpack

-- ===================== module: version =================
-- =====================================================================
-- version.lc - QR Version/EC-block tables (v1-40). Spec section 8.5 (largest table).
-- Port of ZXing Qrcode\Decoder\Version. Requires: qrCompat.lc, errorCorrectionLevel.lc.
--
-- The table below was GENERATED from the ZXing data and independently verified:
--   * every version x level total codewords matches the ISO/IEC 18004 totals
--     (160/160 checks), and
--   * the 34 version-info words regenerate from BCH gen 0x1F25.
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
   put u32(n) into n
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

function ver_getDimensionForVersion pVersion
   ver_ensure
   return sVer[pVersion]["dimension"]
end ver_getDimensionForVersion

function ver_getAlignmentCenters pVersion
   ver_ensure
   return sVer[pVersion]["align"]      -- comma list (may be empty)
end ver_getAlignmentCenters

-- EC codewords per block, for version + EC ordinal
function ver_getEcCodewordsPerBlock pVersion, pEcOrdinal
   local tEC
   ver_ensure
   put sVer[pVersion]["ec"][pEcOrdinal] into tEC
   set the itemDelimiter to ";"
   return (item 1 of tEC)
end ver_getEcCodewordsPerBlock

-- returns the block layout as lines "count,dataCodewords" for version+ordinal
function ver_getEcBlocks pVersion, pEcOrdinal
   local tEC, tOut, i
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

-- version implied by a sampled dimension: (dimension - 17) / 4
function ver_getProvisionalVersionForDimension pDimension
   if ((pDimension mod 4) <> 1) then throw "Format: dimension not %4==1"
   return ((pDimension - 17) div 4)
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
      put ver_popcount(u32(pVersionBits bitXor targetVersion)) into bitsDifference
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
   put "39~6,26,52,78,104,130,156,182~30/20,117/4,118~28/40,47/7,48~30/43,24/22,25~30/10,15/67,16" & lf after t
   put "40~6,30,58,86,114,142,170,198~30/19,118/6,119~28/18,47/31,48~30/34,24/34,25~30/20,15/61,16" & lf after t
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
   return "ISO-8859-1"           -- unknown ECI: safe byte-preserving default
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
   local tMaxData, tShorterNumData, tLongerStart, tRawIndex, tMaxLen, tIdx

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
--   ["text"]   decoded text
--   ["bytes"]  raw decoded byte string (concatenation of byte segments)
--   ["error"]  set + result empty on FormatException
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
-- Modes fully supported: NUMERIC, ALPHANUMERIC, BYTE (ISO-8859-1/UTF-8/ASCII),
--   ECI (charset switch), TERMINATOR, FNC1, STRUCTURED_APPEND (skipped).
-- KANJI / HANZI raise the documented section 8.7 limitation (no native Shift-JIS/
--   GB2312 in xTalk); the common case is fully covered.
-- =====================================================================

constant kAlphanumChars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
constant kDigits = "0123456789"

local sSrc      -- the shared BitSource for the current decode

-- read n bits from the shared source; returns the value
function dbsp_read pNumBits
   bitSource_readBits sSrc, pNumBits
   return the result
end dbsp_read

-- main entry. pBytes is a 0-based dense array of codeword bytes.
function dbsp_decode pBytes, pVersion, pEcOrdinal
   local tResult, tRaw, tText, tMode, tBits, tCharset, tSeg, tByteRes, e
   put bitSource_new(pBytes) into sSrc
   put empty into tText
   put empty into tRaw
   put "ISO-8859-1" into tCharset       -- default charset until an ECI says otherwise

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
               put dbsp_decodeAlphanumeric(pVersion) into tSeg
               put tSeg after tText
               break
            case "BYTE"
               put dbsp_decodeByte(pVersion, tCharset) into tByteRes
               put tByteRes["text"] after tText
               put tByteRes["bytes"] after tRaw
               break
            case "ECI"
               put dbsp_parseEci() into tCharset
               break
            case "FNC1_FIRST_POSITION"
            case "FNC1_SECOND_POSITION"
               -- structural only; no characters emitted here
               break
            case "STRUCTURED_APPEND"
               -- read 4 (sequence) + 4 (total) + 8 (parity) = 16 bits, ignore
               put dbsp_read(16) into tBits
               break
            case "KANJI"
            case "HANZI"
               throw "Format: Kanji/Hanzi not supported in this build (spec 8.7)"
            default
               throw "Format: unhandled mode " & tMode
         end switch
      end repeat
   catch e
      put empty into tResult
      put e into tResult["error"]
      return tResult
   end try

   put tText into tResult["text"]
   put tRaw into tResult["bytes"]
   put empty into tResult["error"]
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
      put char (trunc(threeDigits / 100) + 1) of kDigits after tOut
      put char ((trunc(threeDigits / 10) mod 10) + 1) of kDigits after tOut
      put char ((threeDigits mod 10) + 1) of kDigits after tOut
      subtract 3 from tCount
   end repeat
   if tCount = 2 then
      put dbsp_read(7) into twoDigits
      if twoDigits >= 100 then throw "Format: numeric pair > 99"
      put char (trunc(twoDigits / 10) + 1) of kDigits after tOut
      put char ((twoDigits mod 10) + 1) of kDigits after tOut
   else if tCount = 1 then
      put dbsp_read(4) into oneDigit
      if oneDigit >= 10 then throw "Format: numeric single > 9"
      put char (oneDigit + 1) of kDigits after tOut
   end if
   return tOut
end dbsp_decodeNumeric

-- ALPHANUMERIC: pairs (11 bits -> v/45, v%45), trailing single (6 bits).
function dbsp_decodeAlphanumeric pVersion
   local tCount, tOut, v
   put dbsp_read(mode_charCountBits("ALPHANUMERIC", pVersion)) into tCount
   put empty into tOut
   repeat while tCount >= 2
      put dbsp_read(11) into v
      put char (trunc(v / 45) + 1) of kAlphanumChars after tOut
      put char ((v mod 45) + 1) of kAlphanumChars after tOut
      subtract 2 from tCount
   end repeat
   if tCount = 1 then
      put dbsp_read(6) into v
      put char (v + 1) of kAlphanumChars after tOut
   end if
   return tOut
end dbsp_decodeAlphanumeric

-- BYTE: `count` bytes; decode via current charset. Returns {text,bytes}.
function dbsp_decodeByte pVersion, pCharset
   local tCount, i, b, tBytes, tRes
   put dbsp_read(mode_charCountBits("BYTE", pVersion)) into tCount
   put empty into tBytes
   repeat with i = 1 to tCount
      put dbsp_read(8) into b
      put numToByte(b) after tBytes
   end repeat
   put tBytes into tRes["bytes"]
   put dbsp_decodeBytes(tBytes, pCharset) into tRes["text"]
   return tRes
end dbsp_decodeByte

-- turn a raw byte string into text using the (limited) native charsets.
--
-- PORTABILITY: this does NOT depend on the engine's `textDecode`. On a headless
-- the xTalk engine's `textDecode` is always available, but in a freshly loaded
-- script-only stack on the IDE / standalone / mobile engines it can throw before
-- the text-encoding subsystem is initialised -- which would fail every BYTE-mode
-- QR (URLs, vCards, Wi-Fi, ...). We decode ISO-8859-1 / ASCII by direct
-- byte->codepoint mapping and UTF-8 by a small hand-rolled decoder, so the
-- library works the same on desktop, mobile, and server. (ISO-8859-1 is exactly
-- "each byte 0..255 IS its codepoint", so the mapping is lossless and never
-- throws.)
function dbsp_decodeBytes pBytes, pCharset
   local cs
   put toUpper(pCharset) into cs
   if (cs = "UTF-8") or (cs = "UTF8") then
      return dbsp_utf8ToText(pBytes)
   end if
   -- ISO-8859-1 / Latin-1 / ASCII / anything else: direct byte->codepoint
   return dbsp_latin1ToText(pBytes)
end dbsp_decodeBytes

-- ISO-8859-1: every byte maps directly to the codepoint of the same value
-- (Unicode's first 256 codepoints ARE Latin-1). numToCodepoint is a core string
-- function (not the ICU/encoding library that textDecode needs), so it is
-- available in a script-only stack where textDecode is not.
function dbsp_latin1ToText pBytes
   local tTxt, i, n
   put the number of bytes of pBytes into n
   put empty into tTxt
   repeat with i = 1 to n
      put numToCodepoint(byteToNum(byte i of pBytes)) after tTxt
   end repeat
   return tTxt
end dbsp_latin1ToText

-- Minimal UTF-8 decoder (1-4 byte sequences) -> text, no textDecode dependency.
-- Malformed bytes degrade gracefully to their Latin-1 interpretation rather than
-- throwing, so a slightly-off payload still yields readable text.
function dbsp_utf8ToText pBytes
   local tTxt, i, n, b1, b2, b3, b4, cp, tCont
   put the number of bytes of pBytes into n
   put empty into tTxt
   put 1 into i
   repeat while i <= n
      put byteToNum(byte i of pBytes) into b1
      if b1 < 128 then
         put numToCodepoint(b1) after tTxt
         add 1 to i
      else if (b1 >= 194) and (b1 <= 223) and (i + 1 <= n) then
         put byteToNum(byte (i + 1) of pBytes) into b2
         if (b2 >= 128) and (b2 <= 191) then
            put (((b1 - 192) * 64) + (b2 - 128)) into cp
            put numToCodepoint(cp) after tTxt
            add 2 to i
         else
            put numToCodepoint(b1) after tTxt
            add 1 to i
         end if
      else if (b1 >= 224) and (b1 <= 239) and (i + 2 <= n) then
         put byteToNum(byte (i + 1) of pBytes) into b2
         put byteToNum(byte (i + 2) of pBytes) into b3
         if (b2 >= 128) and (b2 <= 191) and (b3 >= 128) and (b3 <= 191) then
            put (((b1 - 224) * 4096) + ((b2 - 128) * 64) + (b3 - 128)) into cp
            put numToCodepoint(cp) after tTxt
            add 3 to i
         else
            put numToCodepoint(b1) after tTxt
            add 1 to i
         end if
      else if (b1 >= 240) and (b1 <= 244) and (i + 3 <= n) then
         put byteToNum(byte (i + 1) of pBytes) into b2
         put byteToNum(byte (i + 2) of pBytes) into b3
         put byteToNum(byte (i + 3) of pBytes) into b4
         if (b2 >= 128) and (b2 <= 191) and (b3 >= 128) and (b3 <= 191) \
               and (b4 >= 128) and (b4 <= 191) then
            put (((b1 - 240) * 262144) + ((b2 - 128) * 4096) \
               + ((b3 - 128) * 64) + (b4 - 128)) into cp
            put numToCodepoint(cp) after tTxt
            add 4 to i
         else
            put numToCodepoint(b1) after tTxt
            add 1 to i
         end if
      else
         -- continuation byte out of place, or truncated sequence: Latin-1 it
         put numToCodepoint(b1) after tTxt
         add 1 to i
      end if
   end repeat
   return tTxt
end dbsp_utf8ToText

-- ECI: parse the 1/2/3-byte ECI designator and map to a charset name.
function dbsp_parseEci
   local firstByte, eciValue, tSecond, tThird
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
   return eci_charsetName(eciValue)
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
   if (tDim < 21) or ((tDim bitAnd 3) <> 1) then
      throw "Format: dimension " & tDim & " is not 4k+1 / >=21"
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
   -- v7+: read the two 18-bit version-info blocks (bottom-left + top-right)
   put 0 into versionBits
   repeat with i = 5 down to 0
      repeat with j = tDim - 9 down to tDim - 11
         put bmp_copyBit(pParser, i, j, versionBits) into versionBits
      end repeat
   end repeat
   put ver_decodeVersionInformation(versionBits) into tVer
   if tVer is not empty then return tVer
   -- second copy (transpose of the read coordinates)
   put 0 into versionBits
   repeat with j = 5 down to 0
      repeat with i = tDim - 9 down to tDim - 11
         put bmp_copyBit(pParser, i, j, versionBits) into versionBits
      end repeat
   end repeat
   put ver_decodeVersionInformation(versionBits) into tVer
   if tVer is not empty then return tVer
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
--   ["text"], ["bytes"], ["error"], plus ["ecLevel"], ["version"], ["mask"].
-- On any NotFound/Format/Checksum the result has ["error"] set and empty text.
--
-- Flow (dec_decodeParser):
--   1. read format info -> ecLevel, dataMask
--   2. read version
--   3. un-mask the matrix with the chosen data mask
--   4. read raw codewords (zig-zag, skipping function modules)
--   5. de-interleave into RS blocks; correct each block; concatenate data
--   6. DecodedBitStreamParser.decode
-- A mirrored-symbol retry wraps this: on failure, transpose and try once more.
-- =====================================================================

function dec_decode pBits
   local parser, tRes, e
   put bmp_new(pBits) into parser
   -- first attempt
   put dec_tryParser(parser) into tRes
   if tRes["error"] is empty then
      return tRes
   end if
   -- mirror retry: re-read everything transposed
   bmp_setMirror parser, true
   put dec_tryParser(parser) into tRes
   if tRes["error"] is empty then
      put true into tRes["mirrored"]
   end if
   return tRes
end dec_decode

-- one decode attempt; returns the bitstream result (with error set on failure).
function dec_tryParser pParser
   local tFmt, tEcLevel, tMask, tVersion, tBits, tCodewords
   local tBlocks, tNum, b, tCorrected, i, tData, tDataIdx, tSaved
   local tResult, tErr, e

   try
      put bmp_readFormatInformation(pParser) into tFmt
      put tFmt["ecLevel"] into tEcLevel
      put tFmt["dataMask"] into tMask
      put bmp_readVersion(pParser) into tVersion

      -- un-mask the data modules, then read codewords from the matrix.
      -- Work on a copy so the parser's matrix stays intact for a mirror retry.
      put pParser["bits"] into tBits
      dataMask_unmask tBits, ver_getDimensionForVersion(tVersion), tMask
      put pParser["bits"] into tSaved
      put tBits into pParser["bits"]
      put bmp_readCodewords(pParser, tVersion) into tCodewords
      put tSaved into pParser["bits"]

      -- de-interleave + per-block Reed-Solomon correction
      put db_getDataBlocks(tCodewords, tVersion, tEcLevel) into tBlocks
      put tBlocks["n"] into tNum
      put 0 into tDataIdx             -- concatenated corrected data codewords
      repeat with b = 0 to (tNum - 1)
         put dec_correctBlock(tBlocks[b], ver_getEcCodewordsPerBlock(tVersion, tEcLevel)) into tCorrected
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
      put empty into tErr
      put e into tErr["error"]
      return tErr
   end try
end dec_tryParser

-- correct one block's codewords with Reed-Solomon; returns the corrected
-- data codewords (0-based, length numData).
function dec_correctBlock pBlock, pEcwPerBlock
   local tLen, tCw, i, tOut
   put pBlock["len"] into tLen
   -- build a dense 0-based array of all codewords (data + ec) for rs_decode
   repeat with i = 0 to (tLen - 1)
      put pBlock["cw"][i] into tCw[i]
   end repeat
   rs_decode tCw, pEcwPerBlock          -- corrects in place; throws on failure
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
-- A sample point landing outside the image throws NotFound -- this mirrors the
-- PHP ArrayIndexOutOfBounds -> NotFoundException wrapper (a "twisted" transform).
-- =====================================================================

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
   if (pDimX <= 0) or (pDimY <= 0) then
      throw "NotFound: grid dimensions <= 0"
   end if
   put bitMatrix_new(pDimX, pDimY) into tBits
   put bitMatrix_getWidth(pImage) into tImgW
   put bitMatrix_getHeight(pImage) into tImgH
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
         if (tPX < 0) or (tPX >= tImgW) or (tPY < 0) or (tPY >= tImgH) then
            throw "NotFound: sample point (" & tPX & "," & tPY & ") outside image"
         end if
         if bitMatrix_get(pImage, tPX, tPY) then
            bitMatrix_set tBits, c, y
         end if
      end repeat
   end repeat
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
--  * CENTER_QUORUM=2, MIN_SKIP=3, MAX_MODULES=57 are inlined as literals.
-- =====================================================================

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

-- diagonal cross-check; returns true/false (used only in PURE_BARCODE mode)
function fpf_crossCheckDiagonal pImg, pStartI, pCenterJ, pMaxCount, pOrigTotal
   local tSC, i, tMaxI, tMaxJ, tTotal
   put 0 into tSC[0]
   put 0 into tSC[1]
   put 0 into tSC[2]
   put 0 into tSC[3]
   put 0 into tSC[4]
   put 0 into i
   repeat while ((pStartI >= i) and (pCenterJ >= i) and bitMatrix_get(pImg, (pCenterJ - i), (pStartI - i)))
      add 1 to tSC[2]
      add 1 to i
   end repeat
   if (pStartI < i) or (pCenterJ < i) then return false
   repeat while ((pStartI >= i) and (pCenterJ >= i) and (not bitMatrix_get(pImg, (pCenterJ - i), (pStartI - i))) and (tSC[1] <= pMaxCount))
      add 1 to tSC[1]
      add 1 to i
   end repeat
   if (pStartI < i) or (pCenterJ < i) or (tSC[1] > pMaxCount) then return false
   repeat while ((pStartI >= i) and (pCenterJ >= i) and bitMatrix_get(pImg, (pCenterJ - i), (pStartI - i)) and (tSC[0] <= pMaxCount))
      add 1 to tSC[0]
      add 1 to i
   end repeat
   if tSC[0] > pMaxCount then return false
   put bitMatrix_getHeight(pImg) into tMaxI
   put bitMatrix_getWidth(pImg) into tMaxJ
   put 1 into i
   repeat while (((pStartI + i) < tMaxI) and ((pCenterJ + i) < tMaxJ) and bitMatrix_get(pImg, (pCenterJ + i), (pStartI + i)))
      add 1 to tSC[2]
      add 1 to i
   end repeat
   if ((pStartI + i) >= tMaxI) or ((pCenterJ + i) >= tMaxJ) then return false
   repeat while (((pStartI + i) < tMaxI) and ((pCenterJ + i) < tMaxJ) and (not bitMatrix_get(pImg, (pCenterJ + i), (pStartI + i))) and (tSC[3] < pMaxCount))
      add 1 to tSC[3]
      add 1 to i
   end repeat
   if ((pStartI + i) >= tMaxI) or ((pCenterJ + i) >= tMaxJ) or (tSC[3] >= pMaxCount) then return false
   repeat while (((pStartI + i) < tMaxI) and ((pCenterJ + i) < tMaxJ) and bitMatrix_get(pImg, (pCenterJ + i), (pStartI + i)) and (tSC[4] < pMaxCount))
      add 1 to tSC[4]
      add 1 to i
   end repeat
   if tSC[4] >= pMaxCount then return false
   put (tSC[0] + tSC[1] + tSC[2] + tSC[3] + tSC[4]) into tTotal
   return ((abs(tTotal - pOrigTotal) < (2 * pOrigTotal)) and fpf_foundPatternCross(tSC, 0.5))
end fpf_crossCheckDiagonal

-- a horizontal candidate: cross-check, then accumulate/merge into pF["pat"].
-- rConfirmed (output) = true iff a finder candidate was confirmed this call.
command fpf_handlePossibleCenter @pFinder, pSC, pRowI, pEndCol, pPure, @rConfirmed
   local tTotal, tCenterJ, tCenterI, tEst, tFound, tIdx
   local tOldX, tOldY, tOldMs, tOldCt, tMSDiff, tCC
   put false into rConfirmed
   put (pSC[0] + pSC[1] + pSC[2] + pSC[3] + pSC[4]) into tTotal
   put fpf_centerFromEnd(pSC, pEndCol) into tCenterJ
   put fpf_crossCheckVertical(pFinder["bits"], pRowI, trunc(tCenterJ), pSC[2], tTotal) into tCenterI
   if tCenterI is empty then exit fpf_handlePossibleCenter
   put fpf_crossCheckHorizontal(pFinder["bits"], trunc(tCenterJ), trunc(tCenterI), pSC[2], tTotal) into tCenterJ
   if tCenterJ is empty then exit fpf_handlePossibleCenter
   if pPure then
      if not fpf_crossCheckDiagonal(pFinder["bits"], trunc(tCenterI), trunc(tCenterJ), pSC[2], tTotal) then
         exit fpf_handlePossibleCenter
      end if
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
-- when cmp(a,b)<0, i.e. when |a-avg| > |b-avg|. So this orders DESC by |dev|.
command fpf_sortFurthest @pList, pCountN, pAvg
   local i, j, tKey, tKeyDev, tCmpDev
   repeat with i = 1 to (pCountN - 1)
      put pList[i] into tKey
      put abs(tKey["ms"] - pAvg) into tKeyDev
      put (i - 1) into j
      repeat while j >= 0
         put abs(pList[j]["ms"] - pAvg) into tCmpDev
         if tCmpDev < tKeyDev then
            put pList[j] into pList[j + 1]
            subtract 1 from j
         else
            exit repeat
         end if
      end repeat
      put tKey into pList[j + 1]
   end repeat
end fpf_sortFurthest

-- stable insertion sort by CenterComparator (count DESC, then |dev| ASC)
command fpf_sortCenter @pList, pCountN, pAvg
   local i, j, tKey, tKeyDev, tKeyCt, tCmpDev, tCmpCt, tAfter
   repeat with i = 1 to (pCountN - 1)
      put pList[i] into tKey
      put tKey["ct"] into tKeyCt
      put abs(tKey["ms"] - pAvg) into tKeyDev
      put (i - 1) into j
      repeat while j >= 0
         put pList[j]["ct"] into tCmpCt
         put abs(pList[j]["ms"] - pAvg) into tCmpDev
         -- does pList[j] sort AFTER tKey (so we shift it right)?
         if tCmpCt = tKeyCt then
            put (tCmpDev > tKeyDev) into tAfter
         else
            put (tCmpCt < tKeyCt) into tAfter
         end if
         if tAfter then
            put pList[j] into pList[j + 1]
            subtract 1 from j
         else
            exit repeat
         end if
      end repeat
      put tKey into pList[j + 1]
   end repeat
end fpf_sortCenter

-- remove element pIdx from a 0-based list of pCountN elements, shifting down
command fpf_removeAt @pList, pCountN, pIdx
   local k
   repeat with k = pIdx to (pCountN - 2)
      put pList[k + 1] into pList[k]
   end repeat
end fpf_removeAt

-- pick the best 3 finder candidates; throws NotFound if fewer than 3 exist
function fpf_selectBestPatterns pFinder
   local tCountN, k, tList, tTotal, tSquare, tAvg, tStdDev, tLimit, i, tOut
   put pFinder["np"] into tCountN
   if tCountN < 3 then
      throw "NotFound: could not find 3 finder patterns (" & tCountN & " found)"
   end if
   repeat with k = 0 to (tCountN - 1)
      put pFinder["pat"][k] into tList[k]
   end repeat
   if tCountN > 3 then
      put 0 into tTotal
      put 0 into tSquare
      repeat with k = 0 to (tCountN - 1)
         add tList[k]["ms"] to tTotal
         add (tList[k]["ms"] * tList[k]["ms"]) to tSquare
      end repeat
      put (tTotal / tCountN) into tAvg
      put sqrt((tSquare / tCountN) - (tAvg * tAvg)) into tStdDev
      fpf_sortFurthest tList, tCountN, tAvg
      put max((0.2 * tAvg), tStdDev) into tLimit
      put 0 into i
      repeat while (i < tCountN) and (tCountN > 3)
         if abs(tList[i]["ms"] - tAvg) > tLimit then
            fpf_removeAt tList, tCountN, i
            subtract 1 from tCountN
            subtract 1 from i
         end if
         add 1 to i
      end repeat
   end if
   if tCountN > 3 then
      put 0 into tTotal
      repeat with k = 0 to (tCountN - 1)
         add tList[k]["ms"] to tTotal
      end repeat
      put (tTotal / tCountN) into tAvg
      fpf_sortCenter tList, tCountN, tAvg
   end if
   put tList[0] into tOut[0]
   put tList[1] into tOut[1]
   put tList[2] into tOut[2]
   return tOut
end fpf_selectBestPatterns

-- main entry: scan the image, returns {["bl"],["tl"],["tr"]} (ordered points)
function fpf_find pImg, pHints
   local tTryHarder, tPure, tNrSkip, tAllowedDev, tMaxVar
   local tMaxI, tMaxJ, tISkip, tDone, i, j, tSC, tCurState, tEndRow
   local tConfirmed, tRowSkip, tInfo, tPats, tFinder
   -- hints: read each key directly. A missing key (or a non-array pHints)
   -- yields empty in xTalk, so we just test the read value -- no need for
   -- "is an array" / "is among the keys of" (both unexercised on this engine).
   -- fpf_hintPresent() centralises the "present?" test using only proven constructs.
   put (pHints["TRY_HARDER"] is true) into tTryHarder
   put (pHints["PURE_BARCODE"] is true) into tPure
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
   -- iSkip = (3*maxI) / (4*MAX_MODULES). MAX_MODULES=57, so 4*57=228 (inlined as
   -- a literal: the engine dislikes a literal*literal product as a div operand).
   put ((3 * tMaxI) div 228) into tISkip
   if (tISkip < 3) or tTryHarder then put 3 into tISkip
   put false into tDone

   put pImg into tFinder["bits"]
   put 0 into tFinder["np"]
   put false into tFinder["skip"]

   put (tISkip - 1) into i
   repeat while (i < tMaxI) and (not tDone)
      put 0 into tSC[0]
      put 0 into tSC[1]
      put 0 into tSC[2]
      put 0 into tSC[3]
      put 0 into tSC[4]
      put 0 into tCurState
      put false into tEndRow
      repeat with j = 0 to (tMaxJ - 1)
         if bitMatrix_get(pImg, j, i) then
            -- black pixel
            if (tCurState bitAnd 1) = 1 then add 1 to tCurState
            add 1 to tSC[tCurState]
         else
            -- white pixel
            if (tCurState bitAnd 1) = 0 then
               if tCurState = 4 then
                  if fpf_foundPatternCross(tSC, tMaxVar) then
                     fpf_handlePossibleCenter tFinder, tSC, i, j, tPure, tConfirmed
                     if tConfirmed then
                        put 3 into tISkip
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
                           exit repeat
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
      if fpf_foundPatternCross(tSC, tMaxVar) then
         fpf_handlePossibleCenter tFinder, tSC, i, tMaxJ, tPure, tConfirmed
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
   put (pStartY + (pHeight / 2)) into tMiddleI
   put 0 into tAcc["np"]
   repeat with iGen = 0 to (pHeight - 1)
      if (iGen bitAnd 1) = 0 then
         put (tMiddleI + ((iGen + 1) / 2)) into i
      else
         put (tMiddleI - ((iGen + 1) / 2)) into i
      end if
      put trunc(i) into i
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
   put (0 - (tDx / 2)) into tErr
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
   if tEst1 is empty then return (tEst2 / 7)
   if tEst2 is empty then return (tEst1 / 7)
   return ((tEst1 + tEst2) / 14)
end dt_calculateModuleSizeOneWay

function dt_calculateModuleSize pImg, pTL, pTR, pBL
   return ((dt_calculateModuleSizeOneWay(pImg, pTL, pTR) + dt_calculateModuleSizeOneWay(pImg, pTL, pBL)) / 2)
end dt_calculateModuleSize

-- dimension (modules per side) from finder distances + module size; snap %4==1
function dt_computeDimension pTL, pTR, pBL, pModuleSize
   local tTltr, tTlbl, tDim, tMod
   put mu_round(rp_distance(pTL, pTR) / pModuleSize) into tTltr
   put mu_round(rp_distance(pTL, pBL) / pModuleSize) into tTlbl
   put round((((tTltr + tTlbl) / 2) + 7)) into tDim
   put (tDim bitAnd 3) into tMod
   if tMod = 0 then
      add 1 to tDim
   else if tMod = 2 then
      subtract 1 from tDim
   else if tMod = 3 then
      throw "NotFound: dimension " & tDim & " mod 4 == 3 unusable"
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
   local tAlignCenters, tAlign, tBRX, tBRY, tCorr, tEstAX, tEstAY, ii, e
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
      put mu_round(tTL["x"] + (tCorr * (tBRX - tTL["x"]))) into tEstAX
      put mu_round(tTL["y"] + (tCorr * (tBRY - tTL["y"]))) into tEstAY
      put 4 into ii
      repeat while ii <= 16
         try
            put dt_findAlignmentInRegion(pImg, tModuleSize, tEstAX, tEstAY, ii) into tAlign
            exit repeat
         catch e
            put empty into tAlign
         end try
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
--   plus ["points"] from the detector. On a NotFound the detector throws;
--   on Format/Checksum dec_decode returns ["error"] set.
-- =====================================================================

function qcr_decode pBitmap, pHints
   local tBits, tDetectorResult, tDecoderResult, tPure
   -- a missing key (or non-array pHints) reads as empty, so "is true" is false.
   put (pHints["PURE_BARCODE"] is true) into tPure
   if tPure then
      put qcr_extractPureBits(binaryBitmap_getBlackMatrix(pBitmap)) into tBits
      put dec_decode(tBits) into tDecoderResult
   else
      put dt_detect(binaryBitmap_getBlackMatrix(pBitmap), pHints) into tDetectorResult
      put dec_decode(tDetectorResult["bits"]) into tDecoderResult
      put tDetectorResult["points"] into tDecoderResult["points"]
   end if
   return tDecoderResult
end qcr_decode

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
--       multi-strategy (hybrid+global x two scales) -- best for real photos
--
-- hints may be an xTalk array, or a comma list of "KEY" / "KEY=VALUE"
-- (e.g. "TRY_HARDER" or "NR_ALLOW_SKIP_ROWS=0"). Failure contract: internal
-- NotFound/Format/Checksum never escape -- qrDecodeResult returns ["error"].
-- =====================================================================

-- normalise hints to an array (pass-through if already one). We detect an
-- already-array argument via "the keys of" (empty for a non-array / empty
-- string), avoiding the "is an array" operator which is unexercised here.
function qr_parseHints pHints
   local tArr, i, tItem, tKey, tVal, tCount
   if (the keys of pHints) is not empty then
      return pHints
   end if
   if pHints is empty then
      return tArr
   end if
   set the itemDelimiter to comma
   put the number of items of pHints into tCount
   repeat with i = 1 to tCount
      set the itemDelimiter to comma
      put (item i of pHints) into tItem
      if "=" is in tItem then
         set the itemDelimiter to "="
         put (item 1 of tItem) into tKey
         put (item 2 of tItem) into tVal
         put tVal into tArr[tKey]
      else
         put true into tArr[tItem]
      end if
   end repeat
   return tArr
end qr_parseHints

-- rich result; never throws (NotFound/Format/Checksum surface via ["error"])
function qrDecodeResult pImageData, pHints
   local tHintsArr, tSource, tBitmap, tResult, e, tErr
   put qr_parseHints(pHints) into tHintsArr
   try
      put luminanceSource_newFromData(pImageData) into tSource
      put binaryBitmap_new(tSource) into tBitmap
      put qcr_decode(tBitmap, tHintsArr) into tResult
      return tResult
   catch e
      put e into tErr["error"]
      return tErr
   end try
end qrDecodeResult

-- ROBUST multi-strategy decode for real-world phone photos (glare, blur, slight
-- tilt, dense codes). The image is decoded to a raw pixel plane exactly ONCE
-- (the costly step), then several (binarizer, max-dimension) strategies are
-- tried in cheapest-first order; the first that decodes wins. This is the path
-- the interactive scanner uses.
--
-- Why it helps where a single pass fails:
--   * Hybrid vs Global binarizer catch different failure modes -- hybrid's local
--     8x8 threshold handles uneven lighting/glare; the global histogram is a
--     better bet for low-contrast or evenly-lit frames where hybrid misfires.
--   * A higher-resolution retry recovers dense (v4+) codes whose thin modules
--     collapse under the aggressive nearest-neighbour downsample of the fast pass.
--
-- The result array carries ["strategy"] ("hybrid"/"global"), ["procW"],
-- ["procH"] describing the attempt that produced it (the successful one, or the
-- last tried on failure) -- useful diagnostics when the engine isn't visible.
-- NotFound/Format/Checksum never escape; failure surfaces via ["error"].
--
-- pMaxDim is the base (fast-pass) cap; omit for 1200. Hints pass straight
-- through (TRY_HARDER, BINARY_MODE, NR_ALLOW_SKIP_ROWS, ...).
function qrDecodeResultRobust pImageData, pHints, pMaxDim
   local tHintsArr, tPlane, tStrats, tN, k, tBin, tDim, tBaseDim, tHiDim
   local tSource, tBitmap, tResult, tLast, e, tErr
   put qr_parseHints(pHints) into tHintsArr

   if (pMaxDim is empty) or (pMaxDim <= 0) then
      put 1200 into tBaseDim
   else
      put pMaxDim into tBaseDim
   end if
   put trunc((tBaseDim * 4) / 3) into tHiDim     -- ~1.33x for the hi-res retry

   -- decode the image once; the per-strategy downsample (fromRawPlane) derives
   -- the working scales from this plane. A decode failure here is terminal.
   try
      put luminanceSource_decodeRawPlane(pImageData) into tPlane
   catch e
      put e into tErr["error"]
      return tErr
   end try

   -- strategy order: default+fast first (zero change for easy images), then a
   -- different binarizer, then more resolution. Each entry is "binarizer,maxdim".
   put ("hybrid," & tBaseDim) into tStrats[0]
   put ("global," & tBaseDim) into tStrats[1]
   put ("hybrid," & tHiDim) into tStrats[2]
   put ("global," & tHiDim) into tStrats[3]
   put 4 into tN

   put empty into tLast
   repeat with k = 0 to (tN - 1)
      set the itemDelimiter to comma
      put (item 1 of tStrats[k]) into tBin
      put (item 2 of tStrats[k]) into tDim
      put empty into tSource
      try
         put luminanceSource_fromRawPlane(tPlane, tDim) into tSource
         put binaryBitmap_new(tSource, tBin) into tBitmap
         put qcr_decode(tBitmap, tHintsArr) into tResult
      catch e
         put empty into tResult
         put e into tResult["error"]
      end try
      put tBin into tResult["strategy"]
      put tSource["width"] into tResult["procW"]
      put tSource["height"] into tResult["procH"]
      if tResult["error"] is empty then
         return tResult
      end if
      put tResult into tLast
   end repeat
   return tLast
end qrDecodeResultRobust

-- one-shot: decoded text on success, empty on any failure. With BINARY_MODE set
-- (hint), returns the raw decoded byte string verbatim (no charset decode) --
-- needed for binary payloads like the 256-byte ramp fixture (spec section 9).
function qrDecodeFromData pImageData, pHints
   local tRes, tHintsArr
   put qrDecodeResult(pImageData, pHints) into tRes
   if tRes["error"] is not empty then
      return empty
   end if
   put qr_parseHints(pHints) into tHintsArr
   if tHintsArr["BINARY_MODE"] is true then
      return tRes["bytes"]
   end if
   return tRes["text"]
end qrDecodeFromData

function qrDecodeFromFile pFilePath, pHints
   return qrDecodeFromData(url ("binfile:" & pFilePath), pHints)
end qrDecodeFromFile
