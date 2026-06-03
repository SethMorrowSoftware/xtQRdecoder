# QR Code Detector / Decoder — Port Specification for xTalk (server-side)

**Source project:** `khanamiryan/php-qrcode-detector-decoder` (a PHP port of the Java **ZXing** "Zebra Crossing" library).
**Target:** Pure server-side **xTalk**. It relies only on language features present in **9.6.3-era engines (and earlier)**, so the same code runs on those and on later open-source xTalk engines, forks, and variants (e.g. community builds, OpenXTalk).
**Document purpose:** A complete, implementation-ready specification describing what the library does, how it is structured, the exact algorithms and data tables that must be reproduced, and the concrete language-level translation rules required to move from PHP/Java idioms to xTalk.

> This is a *decoder/reader only*. It detects and reads existing QR codes from raster images. It does **not** generate/encode QR codes.

---

## 1. Provenance, scope, and licensing

### 1.1 Lineage
The algorithm is **ZXing** (Apache-2.0), hand-ported to PHP, which we are now porting again to xTalk. ZXing is the canonical, well-tested reference implementation. Because the PHP layer is itself a literal transliteration of Java, **the PHP source — not idiomatic PHP — is the authority for behaviour.** Where the PHP code carries Java idioms (32-bit `int` math, `>>>` unsigned shift, `System.arraycopy`, `Integer.numberOfTrailingZeros`), those idioms define the contract the xTalk port must satisfy bit-for-bit.

### 1.2 In-scope (must port)
- QR Code detection in arbitrary raster images (rotation/perspective tolerant).
- Decoding for QR **versions 1–40**, all four error-correction levels (L, M, Q, H).
- Encoding modes: Numeric, Alphanumeric, Byte (8-bit/Latin-1/ECI), Kanji (Shift-JIS), Hanzi (GB2312), plus structural elements ECI, FNC1, Structured Append, Terminator.
- Reed–Solomon error correction over GF(256).
- "Pure barcode" fast path (`PURE_BARCODE` hint) and normal photographic path.
- Two binarizers: Global Histogram and Hybrid (local adaptive). Hybrid is the default.

### 1.3 Out-of-scope (present in source but not required)
- Aztec / Data Matrix / Maxicode Galois fields are *defined* in `GenericGF` but unused by the QR path. Port only `QR_CODE_FIELD_256` unless you want the others.
- `IMagickLuminanceSource`, `RGBLuminanceSource`, `PlanarYUVLuminanceSource`, `MonochromeRectangleDetector` are alternate front-ends not needed for the core server use case. Only one luminance source is required (see §7).
- `LuminanceSource::rotateCounterClockwise*` throw "unsupported" in the GD source; you may stub them.

### 1.4 Licensing obligations
The upstream is dual-licensed **Apache-2.0 / MIT**, and the underlying ZXing is **Apache-2.0**. The xTalk port:
- May be released under Apache-2.0 or MIT (keep both NOTICE/attribution files).
- Must retain ZXing copyright headers in ported files and an attribution to `khanamiryan/php-qrcode-detector-decoder`.
- Is fully compatible with open-source xTalk engine usage because the library is your own script; no proprietary components are required.

---

## 2. Target runtime and constraints

### 2.1 Engine
- **xTalk server** engine (headless `.lc` scripts invoked via CGI/command line), or a standalone/IDE engine running headless. No GUI is required at runtime, but the engine's **image object** is used for pixel access (see §7).
- Language: **xTalk only.** No widget/builder extensions, no external "C" builders, no browser-widget tricks. This keeps the port portable across community forks.

### 2.2 Language features available in 9.6.3 and earlier (relied upon)
- Associative + numerically-keyed **arrays** (`tArray[tKey]`), passed to handlers **by reference** with `@`.
- `bitAnd`, `bitOr`, `bitXor`, `bitNot` operators (operate on **unsigned 32-bit** integers, 0…4294967295).
- `binaryEncode` / `binaryDecode`, `byteToNum`, `numToByte`, `baseConvert`.
- `textEncode` / `textDecode` (UTF-8/16/32, ASCII, ISO-8859-1, MacRoman, Native).
- Numbers are IEEE-754 doubles internally; integer ops are exact up to 2^53.
- Custom `function`/`command` handlers, `try/catch/throw`, `local`/`global`.

### 2.3 Language features that are **absent** and must be emulated (critical)
- **No classes / objects.** OOP must be emulated procedurally (see §5).
- **No bit-shift operators** (`<<`, `>>`, `>>>`). Use arithmetic: left shift `n` ≡ `* (2^n)`; logical right shift `n` ≡ `div (2^n)`. (See §6.3.)
- **No signed 32-bit integer wraparound.** xTalk's `bitAnd/bitOr/bitXor/bitNot` treat operands as *unsigned* 32-bit; arithmetic does not wrap at all. Java/ZXing relies on signed 32-bit overflow and sign-extension. This must be normalized (see §6.1–6.2).
- **No native Shift-JIS / GB2312 decoders** in `textDecode`. Kanji/Hanzi segments need a bundled mapping table or a documented limitation (see §8.7).

---

## 3. End-to-end processing pipeline

The decode is a linear pipeline. Each stage is a module group in the port.

```
image bytes (PNG/JPG/GIF/BMP)
   │
   ▼
[A] Luminance acquisition            GDLuminanceSource   →  flat 0..255 grey array (row-major)
   │
   ▼
[B] Binarization                     HybridBinarizer     →  BitMatrix (1 bit/pixel, true = black)
   │   (falls back to GlobalHistogramBinarizer for images < 40px on a side)
   ▼
[C] Detection                        Detector
   │   • FinderPatternFinder  → 3 finder-pattern centres (the big corner squares)
   │   • module size + dimension estimate → provisional Version
   │   • AlignmentPatternFinder (v2+) → 4th reference point
   │   • PerspectiveTransform + DefaultGridSampler → sampled square BitMatrix
   ▼
[D] Bit-matrix parsing               BitMatrixParser
   │   • read format information (EC level + data mask), with mirror fallback
   │   • read version (v7+) from version-info blocks
   │   • DataMask un-masking
   │   • read raw codewords in zig-zag order
   ▼
[E] Error correction                 DataBlock (de-interleave) + ReedSolomonDecoder over GF(256)
   ▼
[F] Bitstream decode                 DecodedBitStreamParser
   │   • walk mode segments (numeric / alphanumeric / byte / kanji / hanzi / ECI / …)
   │   • apply character set (ASCII, ISO-8859-1, UTF-8, Shift-JIS, GB2312)
   ▼
Result { text, rawBytes, points, ecLevel, byteSegments, structuredAppend? }
```

The public entry point (`QrReader`) wires A→B and constructs the reader; `QRCodeReader::decode` runs C→F. On any `NotFoundException | FormatException | ChecksumException`, the public `text()` returns `false` and stashes the error.

---

## 4. Module inventory (PHP → xTalk mapping)

50 PHP files, ~9,800 LOC. Below, each PHP class is listed with its role, the key methods to port, and whether it is required. "xTalk unit" is the suggested xTalk handler-group / script file name.

| PHP class (file) | Role | Required | Suggested xTalk unit |
|---|---|---|---|
| `QrReader` | Public façade: load image → source → binarizer → bitmap → reader; `text()`, `decode()`, `getError()` | ✅ | `qrReader.lc` |
| `Reader` (interface) | Marker interface | — (drop) | n/a |
| `QRCodeReader` | Orchestrates detect+decode; `extractPureBits`, `moduleSize` for pure path | ✅ | `qrCodeReader.lc` |
| `BinaryBitmap` | Caches the black matrix; crop/rotate wrappers | ✅ | `binaryBitmap.lc` |
| `Binarizer` (abstract) | Base for binarizers | ✅ (as convention) | folded into binarizers |
| `LuminanceSource` (abstract) | Base for sources; `toString` ascii preview | ✅ (as convention) | folded into source |
| `GDLuminanceSource` | Reads pixels → greyscale flat array; `getRow`, `getMatrix`, `crop` | ✅ | `luminanceSource.lc` |
| `GlobalHistogramBinarizer` | Global black-point via 32-bucket histogram; `getBlackMatrix`, `estimateBlackPoint`, `getBlackRow` | ✅ | `globalHistogramBinarizer.lc` |
| `HybridBinarizer` | Local adaptive threshold (8×8 blocks, 5×5 averaging); `getBlackMatrix`, `calculateBlackPoints`, `calculateThresholdForBlock`, `thresholdBlock`, `cap` | ✅ | `hybridBinarizer.lc` |
| `Common\BitArray` | Packed bit vector (int[] of 32-bit words) | ✅ | `bitArray.lc` |
| `Common\BitMatrix` | Packed 2-D bit grid (int[] words, `rowSize` words/row) | ✅ | `bitMatrix.lc` |
| `Common\BitSource` | MSB-first bit reader over byte array; `readBits`, `available` | ✅ | `bitSource.lc` |
| `Common\PerspectiveTransform` | 3×3 projective transform; square↔quad, `times`, `transformPoints` | ✅ | `perspectiveTransform.lc` |
| `Common\GridSampler`/`DefaultGridSampler` | Sample module grid through the transform; `checkAndNudgePoints` | ✅ | `gridSampler.lc` |
| `Common\DetectorResult` | Holds `{bits, points}` | ✅ | array struct |
| `Common\DecoderResult` | Holds `{rawBytes, text, byteSegments, ecLevel, structured…}` | ✅ | array struct |
| `Common\Detector\MathUtils` | `round`, `distance` | ✅ | `mathUtils.lc` |
| `Common\Detector\MonochromeRectangleDetector` | Alt detector | ❌ | skip |
| `Common\CharacterSetECI` | ECI value ↔ charset name table | ✅ | `characterSetECI.lc` |
| `Common\AbstractEnum` | Reflection-based enum shim | ❌ (replace with constants) | n/a |
| `Common\Reedsolomon\GenericGF` | Galois field GF(256): exp/log tables, `multiply`, `inverse`, `buildMonomial` | ✅ | `genericGF.lc` |
| `Common\Reedsolomon\GenericGFPoly` | Polynomial over GF; `multiply`, `divide`, `evaluateAt`, `addOrSubtract` | ✅ | `genericGFPoly.lc` |
| `Common\Reedsolomon\ReedSolomonDecoder` | Euclidean decoder; `decode`, `runEuclideanAlgorithm`, `findErrorLocations/Magnitudes` | ✅ | `reedSolomonDecoder.lc` |
| `Qrcode\Detector\FinderPatternFinder` | Locate 3 corner finders; cross-checks (H/V/diagonal) | ✅ | `finderPatternFinder.lc` |
| `Qrcode\Detector\FinderPattern` | A finder centre {x,y,estModuleSize,count} | ✅ | array struct |
| `Qrcode\Detector\FinderPatternInfo` | The chosen TL/TR/BL triple | ✅ | array struct |
| `Qrcode\Detector\AlignmentPattern(+Finder)` | Locate the alignment square (v2+) | ✅ | `alignmentPatternFinder.lc` |
| `Qrcode\Detector\Detector` | Top-level detect: transform + sample | ✅ | `detector.lc` |
| `Qrcode\Decoder\BitMatrixParser` | Read format/version/codewords; mirror | ✅ | `bitMatrixParser.lc` |
| `Qrcode\Decoder\Version` | **Version/EC block tables (v1–40)**, alignment centres, version-info decode | ✅ | `version.lc` |
| `Qrcode\Decoder\FormatInformation` | Decode 15-bit format info (EC level+mask), Hamming-nearest | ✅ | `formatInformation.lc` |
| `Qrcode\Decoder\ErrorCorrectionLevel` | L/M/Q/H ordinals & bit mapping | ✅ | `errorCorrectionLevel.lc` |
| `Qrcode\Decoder\Mode` | Mode table (bits, char-count-bits per version range) | ✅ | `mode.lc` |
| `Qrcode\Decoder\DataMask` | 8 mask predicates + `unmaskBitMatrix` | ✅ | `dataMask.lc` |
| `Qrcode\Decoder\DataBlock` | De-interleave codewords into RS blocks | ✅ | `dataBlock.lc` |
| `Qrcode\Decoder\DecodedBitStreamParser` | Bits → text per mode | ✅ | `decodedBitStreamParser.lc` |
| `Qrcode\Decoder\Decoder` | Orchestrate parse→RS→bitstream; mirror retry | ✅ | `decoder.lc` |
| `Qrcode\Decoder\QRCodeDecoderMetaData` | Mirror flag + point reorder | ✅ | array struct |
| `Result`, `ResultPoint` | Output value + 2-D point ops | ✅ | `resultPoint.lc` (Result = the result array) |
| `*Exception` (`NotFound/Format/Checksum/Reader`) | Control-flow exceptions | ✅ | xTalk `throw` strings (see §6.6) |
| `Common\customFunctions.php` | Java-idiom helpers (see §6) | ✅ (rewrite) | `qrCompat.lc` |

---

## 5. OOP-to-procedural translation strategy

xTalk has no classes. Two viable patterns; **the spec recommends Pattern A** for fidelity and debuggability.

### Pattern A — "Object as array, methods as namespaced handlers" (recommended)
Represent each instance as an xTalk array variable. Each PHP method becomes a handler whose first parameter is the instance array, passed **by reference** so mutations persist.

```xtalk
-- PHP:  $bm = new BitMatrix(21, 21);  $bm->set($x,$y);  $v = $bm->get($x,$y)
-- xTalk:
put bitMatrix_new(21, 21) into tBM            -- returns an array
bitMatrix_set tBM, x, y                        -- command, mutates @tBM
put bitMatrix_get(tBM, x, y) into v            -- function, reads
```

Conventions:
- Constructor → `function <class>_new(...) returns <array>`.
- Mutator method → `command <class>_<method> @pObj, ...`.
- Accessor/pure method → `function <class>_<method>(pObj, ...)`.
- Instance fields → array keys: `tBM["width"]`, `tBM["bits"][i]`.
- Static constants → script-local constants or a one-time-initialized global array (mirrors the PHP `::Init()` pattern used by `Mode`, `DataMask`, `GenericGF`).

**Pass-by-reference cost:** xTalk copies arrays on assignment. For the large `bits` arrays (BitMatrix/luminances), **always** pass with `@` and never assign to a fresh variable inside hot loops, or performance collapses. Where PHP returns a mutated copy via `arraycopy`, prefer mutating in place in xTalk.

### Pattern B — Script-only stacks as classes (alternative)
Use `script only stack` files with behaviors; instantiate via `create`. This is cleaner OOP but ties you to engines that fully support behaviors headless and is heavier on the server engine. **Not recommended** for maximal fork compatibility; documented only as an option.

### Inheritance
Only two shallow hierarchies exist: `Binarizer ← GlobalHistogramBinarizer ← HybridBinarizer`, and `LuminanceSource ← GDLuminanceSource`. Flatten them: `HybridBinarizer` simply calls the global-histogram fallback handler directly when the image is below `MINIMUM_DIMENSION` (40 px). No dispatch machinery needed.

### Enums
`ErrorCorrectionLevel`, `Mode`, `CharacterSetECI` are enums in spirit. Replace `AbstractEnum`/reflection entirely with plain constant tables (arrays). Do **not** port `AbstractEnum.php`.

---

## 6. The hard part: integer, bitwise, and helper semantics

This is where a naïve port silently produces wrong output. ZXing assumes Java `int` = **signed 32-bit, two's-complement, wrapping**. PHP emulates this imperfectly (64-bit ints + occasional masking + the `uRShift`/`sdvig3` shims). xTalk behaves differently again. Define one canonical integer model and route **every** bit operation through helpers in `qrCompat.lc`.

### 6.1 Canonical 32-bit model
Adopt: **all bit-packed words are stored as unsigned 32-bit integers (0 … 4294967295).** This matches xTalk's `bitAnd/bitOr/bitXor/bitNot` domain exactly, so packed-bit logic "just works" without sign surprises. The PHP/Java code stores some words as negative (e.g. `-1`, `-16777216`); in our model those become their unsigned equivalents (`0xFFFFFFFF`, `0xFF000000`). The two are bit-identical; only the printed decimal differs. **Never compare packed words to negative literals** — translate any `== -1` to `== 0xFFFFFFFF`, any `mask = -1` to `mask = 0xFFFFFFFF`.

Helper:
```xtalk
constant kUInt32 = 4294967296   -- 2^32
function u32 n   -- normalize any integer into [0, 2^32)
   put n mod kUInt32 into n
   if n < 0 then add kUInt32 to n
   return n
end u32
```

### 6.2 Where signedness actually matters
Most QR bit math is on **non-negative** values (pixel 0–255, coordinates, bit indices). Signedness bites in exactly these places — handle each explicitly:
- **`BitMatrix.get`** uses Java `>>>` (unsigned). Port via §6.3 `uShr`.
- **`BitArray` mask building** (`mask = -1`, `~((1<<k)-1)`) — use `0xFFFFFFFF` and `u32(bitNot(...))`.
- **`BitArray.reverse`** does the classic bit-swap with `0x55555555`, `0x33333333`, `0x0f0f0f0f`, `0x00ff00ff`, `0x0000ffff` constants and `<<`/`>>` — all unsigned; port the shifts via §6.3 and keep words `u32`.
- **`getEnclosingRectangle` / `getTopLeftOnBit` / `getBottomRightOnBit`** scan with `theBits << (31-bit)` and `>>> bit`; keep `u32` and use `uShr`.
- **GF(256) arithmetic** is on values 0–255; XOR via `bitXor` is safe.
- **`hashCode`** (`31*h + c`) overflows a Java int; only used for `equals`/dedup. The port can keep full-precision xTalk numbers **as long as both sides use the same function** — equality still holds. (Or `u32` each step to match Java exactly.)

### 6.3 Shift emulation (no native operators exist)
```xtalk
function shl a, n            -- logical/arith left shift, 32-bit
   return u32(a * (2^n))
end shl

function uShr a, n           -- UNSIGNED right shift  (Java >>>)
   return (u32(a) div (2^n))
end uShr

function aShr a, n           -- ARITHMETIC right shift (Java >>) on a signed-interpreted word
   put u32(a) into a
   if a < 2147483648 then    -- positive in signed view
      return a div (2^n)
   else                      -- negative: sign-extend
      return u32(a) div (2^n) - (kUInt32 div (2^n))  -- or compute via signed value
   end if
end aShr
```
Replace the PHP shims accordingly:
- `uRShift($a,$b)` → `uShr(a,b)`
- `sdvig3($a,$b)` (used in `getEnclosingRectangle`/`getBottomRightOnBit`, always unsigned `>>>`) → `uShr(a,b)`
- `1 << k` → `shl(1,k)` (or just `2^k` when `k<31` and result stays ≤ 2^31)
- `x >> k` on a **non-negative** value → `x div (2^k)` (the common case in binarizers/parsers)

> **Caution:** PHP writes `(int)($i / 32)` everywhere to mean *integer/floor* division of a non-negative index. In xTalk use `(i div 32)`, **not** `trunc(i/32)` inside hot loops (both work for non-negatives; `div` is clearer and faster). For coordinate math that PHP truncates with `(int)`, use `trunc()` (toward zero) — QR coordinates are non-negative so `trunc`==`floor` here.

### 6.4 `arraycopy` (System.arraycopy)
PHP `arraycopy($src,$srcPos,$dest,$destPos,$len)` returns a **new** `$dest` with a spliced region. Port as an in-place command for performance:
```xtalk
command arraycopy @pSrc, pSrcPos, @pDest, pDestPos, pLen
   repeat with k = 0 to pLen - 1
      put pSrc[pSrcPos + k] into pDest[pDestPos + k]
   end repeat
end arraycopy
```
Mind the **0-based** indices in the source (see §6.7).

### 6.5 Other helpers (`customFunctions.php`)
- **`numberOfTrailingZeros(i)`** — count low zero bits; `i==0 → 32`. Direct loop port; used by `BitArray.getNextSet/getNextUnset`.
- **`hashCode(s)`** — Java string hash `h = 31*h + ord(c)`. Port over the **byte** sequence (use `byteToNum(byte k of s)`). Used only for equality/dedup; not on the decode-critical path.
- **`floatToIntBits(f)`** — IEEE-754 raw bits. PHP uses `unpack('i',pack('f',f))`. xTalk: `binaryDecode("i", binaryEncode("f", f))`. **Verify it is unused on the QR path** (it appears only in `ResultPoint`/`PerspectiveTransform` hashing) — likely droppable.
- **`fill_array(index,count,value)`** — build a dense array; note the quirk: `count<=0` returns `[0]` (single element). Replicate that quirk because `BitMatrix`/binarizer sizing relies on it for degenerate cases.

### 6.6 Exceptions → typed error results
PHP throws `NotFoundException`, `FormatException`, `ChecksumException`, `ReaderException`, plus `InvalidArgumentException`/`RuntimeException`. xTalk has `throw <string>` / `try…catch e`. Strategy:
- Throw tagged strings: `throw "NotFound: " & reason`, `throw "Format: " & reason`, `throw "Checksum: " & reason`.
- In `qrCodeReader_decode`, wrap the pipeline in `try`/`catch e`; if `e` begins with `NotFound`/`Format`/`Checksum`, set result = false and store the message (mirrors `QrReader::decode`). Re-throw anything unexpected for debugging.
- The **mirror-retry** logic in `Decoder` and `BitMatrixParser` depends on catching a failure, calling `mirror()`/`remask()`, and retrying — preserve the exact try/retry/re-throw order (see §8.5).

### 6.7 Array indexing: 0-based source vs 1-based xTalk
The PHP/Java code is uniformly **0-based**. Two acceptable strategies:
1. **Keep 0-based numeric keys** in xTalk arrays (xTalk allows `tA[0]`). This minimizes translation risk — copy index expressions verbatim. **Recommended.** Just remember `the number of elements of tA` still counts entries, and never use `repeat for each` (unordered) where order matters — use `repeat with i = 0 to n-1`.
2. Shift everything to 1-based. **Discouraged** — every `i/32`, `i & 0x1F`, table index, and zig-zag offset would need an off-by-one audit.

Strings: PHP `$s[$i]` (0-based byte) → xTalk `byte (i+1) of s` (1-based). Wrap in a helper `byteAt(s,i)` returning `byteToNum(byte (i+1) of s)` to keep call sites readable and 0-based.

---

## 7. Luminance acquisition on the server (replacing GD)

The PHP `GDLuminanceSource` uses `imagecreatefromstring` + `imagecolorat` + `imagecolorsforindex`. There is **no GD in xTalk**; use the engine's image object, which works headless on xTalk server.

### 7.1 Loading bytes → pixels
```xtalk
-- pImageData = raw bytes of a PNG/JPG/GIF/BMP (e.g. from "binfile:" URL or POST upload)
create invisible image "qrSrc"
set the lockLoc of image "qrSrc" to true
put pImageData into image "qrSrc"               -- decodes the format
put the formattedWidth  of image "qrSrc" into tW
put the formattedHeight of image "qrSrc" into tH
set the width  of image "qrSrc" to tW           -- ensure imageData == full resolution
set the height of image "qrSrc" to tH
put the imageData of image "qrSrc" into tRaw     -- 4 bytes/pixel, row-major
```

### 7.2 imageData layout (verified against xTalk docs)
`imageData` is **4 bytes per pixel**, pixels ordered left→right then top→bottom. **Byte 1 = 0 (unused/alpha-stripped), byte 2 = Red, byte 3 = Green, byte 4 = Blue.** This maps directly onto the PHP greyscale rule.

### 7.3 Greyscale conversion (must match PHP exactly)
PHP rule per pixel: if `r==g==b`, luminance = `r`; else luminance = `(r + 2*g + b) / 4` (integer-ish; PHP leaves it as a float that later gets `& 0xff`). Reproduce:
```xtalk
-- build flat 0-based luminance array, length tW*tH
local tLum
put 0 into idx
repeat with p = 0 to (tW*tH - 1)
   put p*4 into o
   put byteToNum(byte (o+2) of tRaw) into r
   put byteToNum(byte (o+3) of tRaw) into g
   put byteToNum(byte (o+4) of tRaw) into b
   if (r = g) and (g = b) then
      put r into tLum[idx]
   else
      put trunc((r + 2*g + b) / 4) into tLum[idx]   -- match PHP /4
   end if
   add 1 to idx
end repeat
```
> **Fidelity note:** PHP stores `(r+2g+b)/4` as a float and only truncates via `& 0xff` later. Since downstream always does `value & 0xFF`, applying `bitAnd(value,255)` (= `value mod 256` for non-negatives) at read time reproduces PHP behaviour. Keeping `trunc(.../4)` at build time is equivalent because the sum ≤ 1020 → /4 ≤ 255, integer anyway when divisible; the fractional cases differ by <1 and are masked. Validate against fixtures (§10).

### 7.4 `getRow` / `getMatrix` / `crop`
- `getMatrix()` → return the whole `tLum` (no copy) when the full image is requested (the common case). Crop variants use `arraycopy` per row.
- `getRow(y,row)` → copy `tW` values starting at `(y+top)*dataWidth+left`.
- `crop` is only exercised by `MonochromeRectangleDetector`/rotation paths we skip; implement lazily.

### 7.5 Performance reality
Reading `the imageData` once and indexing a flat xTalk array is the right approach. **Do not** call any per-pixel engine property in a loop. For large photos, pre-downscale (set image width/height before reading imageData) is acceptable and matches ZXing's tolerance, but changes results — keep full-res for fixture validation.


---

## 8. Module algorithm specifications and required data tables

Only behaviour-critical detail is given; the PHP source remains the line-level authority. Constants/tables below **must be reproduced verbatim** — they are defined by the QR standard (ISO/IEC 18004) and ZXing.

### 8.1 BitMatrix (`bitMatrix.lc`)
Packed grid. Fields: `width`, `height`, `rowSize = (width + 31) div 32`, `bits[]` (length `rowSize*height`, 0-based, unsigned 32-bit words).
- `bitMatrix_new(width [,height][,rowSize][,bits])` — default `height=width`; default `rowSize` as above; default bits all 0 (use `fill_array`).
- `get(x,y)` → `(uShr(bits[y*rowSize + (x div 32)], (x bitAnd 0x1F)) bitAnd 1) <> 0`.
- `set(x,y)` → `offset = y*rowSize + (x div 32); bits[offset] = u32(bits[offset] bitOr shl(1, (x bitAnd 0x1F)))`.
  - ⚠️ **Do NOT port** the giant hard-coded debug array literal embedded in PHP `BitMatrix::set()` — it is dead/leftover debugging cruft and must be omitted.
- `unset`, `flip`, `xor`, `setRegion`, `rotate180`, `getRow`, `setRow`, `getEnclosingRectangle`, `getTopLeftOnBit`, `getBottomRightOnBit` — port directly using §6 helpers. `getRow`/`setRow` use `setBulk`/`arraycopy` of whole 32-bit words.
- `clone` returns a deep copy of `bits` (xTalk array assignment already deep-copies — but copy explicitly to be safe).

### 8.2 BitArray (`bitArray.lc`)
Packed vector, `bits[]` words + `size`. Methods used on the decode path: `set`, `get`, `getNextSet/Unset`, `setBulk`, `setRange`, `isRange`, `appendBit(s)`, `toBytes`, `xor`, `reverse`, `clone`. Note `getSizeInBytes = (size+7)/8` (used by callers as a count). `reverse` uses the unsigned bit-swap constants (§6.2) — keep `u32`.

### 8.3 BitSource (`bitSource.lc`)
MSB-first reader over a 0-based byte array.
- State: `bytes[]`, `byteOffset`, `bitOffset`.
- `readBits(numBits)` (1…32): assembles bits MSB-first across byte boundaries (port the three-branch loop exactly).
- `available()` = `8*(len - byteOffset) - bitOffset`.
This drives `DecodedBitStreamParser`.

### 8.4 Detection group
**MathUtils:** `round(d) = floor(d + 0.5)` → xTalk `round()` matches for positives; to be exact use `trunc(d + 0.5)`. `distance` = Euclidean hypot.

**FinderPatternFinder (`finderPatternFinder.lc`)** — the most intricate module.
- Constants: `CENTER_QUORUM = 2`, `MIN_SKIP = 3`, `MAX_MODULES = 57`.
- Scans rows looking for the 1:1:3:1:1 dark/light ratio (`foundPatternCross`, default `maxVariance` handling). On a candidate, runs `crossCheckVertical`, `crossCheckHorizontal`, and `crossCheckDiagonal` to confirm a true finder centre.
- `handlePossibleCenter` accumulates centres with confirmation counts; `haveMultiplyConfirmedCenters` (deviation 0.05) decides when enough are found; `selectBestPatterns` picks the best 3; `CenterComparator`/`FurthestFromAverageComparator` order them.
- Output `FinderPatternInfo { topLeft, topRight, bottomLeft }` (ZXing's orientation convention — preserve it; downstream transform depends on it).
- **Porting note:** the comparators rely on stable ordering. xTalk `sort` is stable; or implement the comparator logic inline. Avoid `sort` on arrays — sort a constructed list of indices.

**AlignmentPatternFinder (`alignmentPatternFinder.lc`)** — looks for the 1:1:1 alignment cross in a sub-region; `find()` returns one `AlignmentPattern` or throws NotFound.

**Detector (`detector.lc`)**
- `detect` → `FinderPatternFinder.find` → `processFinderPatternInfo`.
- `calculateModuleSize` averages `calculateModuleSizeOneWay` over TL→TR and TL→BL using black/white run sizing (`sizeOfBlackWhiteBlackRunBothWays`).
- `computeDimension` = round of distance-based estimate, snapped to `…% 4 == 1`; throws if not.
- `getProvisionalVersionForDimension(dimension)` → `(dimension-17)/4` → Version.
- Alignment search (v2+): guess bottom-right, correction `1 - 3/modulesBetweenFPCenters`, expanding radius loop `i = 4, 8, 16` (`i = i << 1`).
- `createTransform` builds the `PerspectiveTransform` from the 3 (or 4) reference points; `sampleGrid` runs `DefaultGridSampler` to emit the `dimension × dimension` BitMatrix.

**PerspectiveTransform (`perspectiveTransform.lc`)** — straight linear algebra (3×3). Port `squareToQuadrilateral`, `quadrilateralToSquare`, `quadrilateralToQuadrilateral`, `buildAdjoint`, `times`, `transformPoints`. All float math — no integer-semantics issues.

**DefaultGridSampler (`gridSampler.lc`)** — `sampleGrid(image, dim, transform)`; `checkAndNudgePoints` clamps sample points to the image edge. Reads `image.get(x,y)` per module.

### 8.5 Decoder group
**Version (`version.lc`)** — **largest data table.** Must contain, for **all 40 versions**:
- `versionNumber`
- `alignmentPatternCenters[]` (e.g. v1 = `[]`, v2 = `[6,18]`, v7 = `[6,22,38]`, …)
- four `ECBlocks` (one per EC level **in ordinal order H,L,M,Q — see ErrorCorrectionLevel ordinal mapping below**), each = `{ ecCodewordsPerBlock, [ECB{count, dataCodewords}, …] }`.
- `VERSION_DECODE_INFO[]` — the 34 raw version-info bit patterns for v7–40:
  `0x07C94,0x085BC,0x09A99,0x0A4D3,0x0BBF6,0x0C762,0x0D847,0x0E60D,0x0F928,0x10B78,0x1145D,0x12A17,0x13532,0x149A6,0x15683,0x168C9,0x177EC,0x18EC4,0x191E1,0x1AFAB,0x1B08E,0x1CC1A,0x1D33F,0x1ED75,0x1F250,0x209D5,0x216F0,0x228BA,0x2379F,0x24B0B,0x2542E,0x26A64,0x27541,0x28C69`
- `getDimensionForVersion = 17 + 4*versionNumber`.
- `getProvisionalVersionForDimension`, `getVersionForNumber`, `decodeVersionInformation` (Hamming-nearest within ≤3 bits), `buildFunctionPattern`.

> The 40-entry `buildVersions()` table (EC block structure) is ~200 lines of constants in `Version.php`. **Transcribe it exactly** — a single wrong `dataCodewords` value silently breaks RS for that version. Generate it programmatically from the PHP file (a small script that rewrites `new ECBlocks(ec,[new ECB(c,d)…])` into xTalk array literals) to eliminate transcription error.

**ErrorCorrectionLevel (`errorCorrectionLevel.lc`)** — note the **ordinal/bit subtlety**: ZXing orders the enum `L, M, Q, H` but the 2-bit field stored in format info is `M=00, L=01, H=10, Q=11`. The `ECBlocks` array in `Version` is indexed by **`getOrdinal()`**. Reproduce ZXing's exact ordinal mapping; don't "fix" the apparent reordering. Provide `forBits(bits)` and `getBits()`/`getOrdinal()`.

**Mode (`mode.lc`)** — table (verbatim):
| Mode | char-count-bits [v1-9, v10-26, v27-40] | 4-bit value |
|---|---|---|
| TERMINATOR | 0,0,0 | 0x00 |
| NUMERIC | 10,12,14 | 0x01 |
| ALPHANUMERIC | 9,11,13 | 0x02 |
| STRUCTURED_APPEND | 0,0,0 | 0x03 |
| BYTE | 8,16,16 | 0x04 |
| FNC1_FIRST_POSITION | 0,0,0 | 0x05 |
| ECI | 0,0,0 | 0x07 |
| KANJI | 8,10,12 | 0x08 |
| FNC1_SECOND_POSITION | 0,0,0 | 0x09 |
| HANZI (GB2312) | 8,10,12 | 0x0D |
`getCharacterCountBits(version)`: offset 0 if v≤9, 1 if v≤26, else 2. `forBits` maps the 4-bit value back to a mode (throw on unknown).

**FormatInformation (`formatInformation.lc`)** — decode the 15-bit format info: XOR with mask `0x5412`, then choose the `FORMAT_INFO_DECODE_LOOKUP` entry with the fewest differing bits (≤3). Yields `{ errorCorrectionLevel, dataMask (0-7) }`. Port the lookup table and `doDecodeFormatInformation` exactly; it is tried against both the primary and secondary copies of the format bits.

**DataMask (`dataMask.lc`)** — 8 mask predicates `isMasked(i,j)` (i = row, j = column):
| ref | formula |
|---|---|
| 0 | `((i + j) bitAnd 1) = 0` |
| 1 | `(i bitAnd 1) = 0` |
| 2 | `j mod 3 = 0` |
| 3 | `(i + j) mod 3 = 0` |
| 4 | `(((i div 2) + (j div 3)) bitAnd 1) = 0` |
| 5 | `((i*j) mod 2) + ((i*j) mod 3) = 0` |
| 6 | `(((i*j) mod 2) + ((i*j) mod 3)) bitAnd 1 = 0` |
| 7 | `((((i+j) bitAnd 1) + ((i*j) mod 3)) bitAnd 1) = 0` |
`unmaskBitMatrix(bits, dimension)` flips every `(i,j)` where the chosen mask predicate is true. (PHP refs 5 and 6 are written as `$temp=$i*$j; ...` — verify against the table above; ref 5 = "sum == 0", ref 6 = "sum & 1 == 0".)

**BitMatrixParser (`bitMatrixParser.lc`)**
- `readFormatInformation()` reads the two 15-bit copies (around top-left + split around the other two finders), decodes via `FormatInformation`. Caches result.
- `readVersion()` for dimension ≥ 45 (v7+): reads the two 18-bit version blocks, `Version.decodeVersionInformation`. For smaller, derive from dimension.
- `readCodewords()` walks the matrix in the standard **zig-zag** (up/down columns, skipping the timing column 6 and function patterns via `Version.buildFunctionPattern`), assembling bytes MSB-first. Returns the raw codeword byte array.
- `mirror()`, `setMirror()`, `remask()` support the mirrored-symbol retry.

**DataBlock (`dataBlock.lc`)** — `getDataBlocks(rawCodewords, version, ecLevel)` de-interleaves the codeword stream into per-block `{numDataCodewords, codewords[]}` according to the version's EC block layout (handles the "longer blocks" tail). Critical and easy to get wrong — follow ZXing's two-pass fill precisely.

**ReedSolomon group**
- **GenericGF (`genericGF.lc`)** — only `QR_CODE_FIELD_256` needed: primitive `0x011D`, size `256`, generatorBase `0`. `Init()` builds `expTable`/`logTable` (size 256) by `x <<= 1; if x >= size then x ^= primitive`. `multiply(a,b)=0 if a==0||b==0 else exp[(log[a]+log[b]) mod (size-1)]`. `inverse`, `exp`, `log`, `buildMonomial`, `addOrSubtract = bitXor`.
- **GenericGFPoly (`genericGFPoly.lc`)** — immutable polynomials; `multiply`, `multiplyByMonomial`, `multiply_(scalar)`, `divide`, `evaluateAt`, `addOrSubtract`, `getCoefficient`, `getDegree`. All coefficients 0–255 via `bitXor`/`multiply`.
- **ReedSolomonDecoder (`reedSolomonDecoder.lc`)** — `decode(received[], twoS)`: compute syndromes; if all zero, no errors; else `runEuclideanAlgorithm` → error locator + evaluator; `findErrorLocations` (Chien search) + `findErrorMagnitudes` (Forney); correct in place. Throw `ReedSolomonException` (→ surfaces as `Checksum`) on failure.

**Decoder (`decoder.lc`)** — `decodeBits(bits, hints)`:
1. `parser = BitMatrixParser(bits)`; try `decodeParser(parser)`.
2. On failure, if parser supports it: `parser.remask(); parser.setMirror(true); parser.mirror();` re-read format/version, re-`decodeParser`, and on success set `QRCodeDecoderMetaData{mirrored=true}` (which later reorders result points). Preserve this exact fallback.
- `decodeParser`: read version + format → `ecLevel`, `dataMask`; `dataMask.unmaskBitMatrix`; `readCodewords`; `DataBlock.getDataBlocks`; per block run RS `correctErrors`; concatenate corrected data codewords; `DecodedBitStreamParser.decode`.
- `correctErrors(codewordBytes, numDataCodewords)`: build int[] from bytes, `rsDecoder.decode(…, numEC)`, copy back; count/throw on failure.

**DecodedBitStreamParser (`decodedBitStreamParser.lc`)** — bits → text. Loop: read 4-bit mode; dispatch:
- **NUMERIC**: groups of 3 digits (10 bits), then 2 (7) or 1 (4). Append ASCII digits.
- **ALPHANUMERIC**: pairs (11 bits → `v/45`, `v%45`), trailing single (6 bits). Map via the 45-char table:
  `0-9 A-Z space $ % * + - . / :` (indices 0…44). In FNC1 mode `%` toggles to literal `%`.
- **BYTE**: `count` bytes; charset = current ECI, else guessed (ISO-8859-1 default; UTF-8 if BOM/heuristic). Append decoded text + collect `byteSegments`.
- **KANJI**: 13-bit groups → Shift-JIS double-byte (see §8.7).
- **HANZI (GB2312)**: subset byte (`GB2312_SUBSET=1`), then 13-bit groups → GB2312 double-byte.
- **ECI**: `parseECIValue` (1/2/3-byte) → set current `CharacterSetECI`.
- **STRUCTURED_APPEND**: read sequence + parity (sets DecoderResult metadata).
- **FNC1_FIRST/SECOND**, **TERMINATOR**: handle/stop.
Constants: `ALPHANUMERIC_CHARS` (the 45-char array above), `GB2312_SUBSET = 1`.

### 8.6 CharacterSetECI (`characterSetECI.lc`)
A table mapping ECI numeric values → encoding names and aliases (Cp437, ISO-8859-1…16, Shift_JIS, Cp1250-1256, UTF-8, UTF-16BE, US-ASCII, Big5, GB2312, EUC-KR, …). Build an xTalk array `value → canonicalName` plus `name → value`. Only the subset actually emitted by your fixtures is exercised, but port the whole table for correctness.

### 8.7 Character-encoding gap (Kanji / Hanzi) — IMPORTANT
PHP decodes Shift-JIS and GB2312 via `mb_convert_encoding` / `iconv`. **xTalk `textDecode` does NOT support Shift_JIS or GB2312** (supported: ASCII, ISO-8859-1, MacRoman, Native, UTF-8/16/32). Options, in order of preference:
1. **Bundle compact mapping tables** (Shift-JIS↔Unicode, GB2312↔Unicode) as data files; convert double-byte values to codepoints, then `textEncode(unicodeString,"UTF-8")` for output. (~No external deps; recommended for "pure" xTalk.)
2. **Shell out** to `iconv`/`uconv` via `shell()` — fast but breaks "pure xTalk" and platform portability.
3. **Document a limitation**: decode Numeric/Alphanumeric/Byte fully; for Kanji/Hanzi, return the raw double-byte codes or a best-effort. Acceptable only if your QR inputs are Latin/UTF-8 (the overwhelming common case: most modern QR uses BYTE+UTF-8).
For Byte segments, UTF-8 and ISO-8859-1 are natively handled by `textDecode`, so the common case is fully covered.


---

## 9. Public API for the xTalk port

Keep the surface tiny and faithful to `QrReader`. Suggested handlers in `qrReader.lc`:

```xtalk
-- Primary one-shot: returns decoded text, or empty + sets the error global on failure.
function qrDecodeFromData pImageData, pHints
   -- pImageData : raw image bytes (PNG/JPG/GIF/BMP)
   -- pHints     : optional array (see below); may be empty
   -- returns    : decoded text on success; empty string on failure
end qrDecodeFromData

function qrDecodeFromFile pFilePath, pHints
   return qrDecodeFromData(url ("binfile:" & pFilePath), pHints)
end qrDecodeFromFile

-- Rich result (mirrors getResult): an array with keys
--   text, rawBytes, points, ecLevel, byteSegments, structuredAppendSeq, structuredAppendParity, error
function qrDecodeResult pImageData, pHints
```

**Hints** (array keys, all optional — mirror the PHP/ZXing hint names so behaviour matches the test-suite):
- `PURE_BARCODE` (boolean) — use the fast `extractPureBits` path for clean, unrotated, bordered codes.
- `TRY_HARDER` (boolean) — more exhaustive finder scanning.
- `BINARY_MODE` (boolean) — return raw bytes verbatim (no charset decode) — needed for the binary fixture.
- `NR_ALLOW_SKIP_ROWS` (int) — finder row-skip tuning.
- `NEED_RESULT_POINT_CALLBACK` — drop or stub (UI-only).

**Failure contract:** mirror PHP — on `NotFound/Format/Checksum`, return empty and expose the tagged error via `qrDecodeResult(...)["error"]`. Do not let internal `throw`s escape the public function.

**Server usage sketch (CGI `.lc`):**
```xtalk
<?lc
   put "Content-Type: text/plain" & cr & cr
   put $_POST["image"] into tBytes          -- or read an uploaded temp file
   put qrDecodeFromData(tBytes, "BINARY_MODE,false") into tText
   if tText is empty then put "NO_QR" else put tText
?>
```

---

## 10. Testing strategy and golden vectors

Port the upstream fixtures as the acceptance suite. Build a tiny xTalk harness that runs each and compares.

| Fixture | Hints | Expected `text()` |
|---|---|---|
| `hello_world.png` | none | `Hello world!` |
| `empty.png` | none | (failure → empty/false) |
| `test.png` | `TRY_HARDER` | `https://www.gosuslugi.ru/covid-cert/verify/9770000014233333?lang=ru&ck=733a9d218d312fe134f1c2cc06e1a800` |
| `139225861-…888.png` | `TRY_HARDER`, `NR_ALLOW_SKIP_ROWS=0` | same gosuslugi URL as above |
| `binary-test.png` | `BINARY_MODE` | bytes `0x00..0xFF` (256-byte ramp) |

(The `.jpg` test is disabled upstream; treat as a stretch goal.)

### Recommended bottom-up validation order (catch errors where they're cheap)
1. **`qrCompat.lc`**: unit-test `u32`, `shl`, `uShr`, `aShr`, `numberOfTrailingZeros`, `arraycopy`, `fill_array` against hand-computed values, including negative/`0xFFFFFFFF` cases.
2. **GF(256)**: assert `exp/log` tables, `multiply`, `inverse` against known GF(256) products (e.g. `2·142=1`? verify with ZXing values).
3. **BitArray/BitMatrix**: round-trip set/get, `getRow/setRow`, `reverse`, `getTopLeftOnBit`.
4. **ReedSolomon**: feed a codeword block with injected errors ≤ t and assert correction; this is the single best integration test for the integer layer.
5. **Binarizer**: dump the BitMatrix of `hello_world.png` to ASCII (`toString`) and eyeball/compare against a PHP-generated reference dump.
6. **Detector → Decoder**: the five fixtures above.

> **Cross-oracle tip:** instrument the *PHP* library to dump intermediate artifacts (luminance row 0, the binarized matrix as text, raw codewords hex, corrected codewords hex, final bit segments) for each fixture. Diff the xTalk port against these dumps stage-by-stage. This localizes any divergence to a single module instead of "the answer is wrong."

---

## 11. Performance considerations

xTalk is interpreted; the pixel/bit loops are the cost centres. Budget and mitigations:
- **Luminance build & binarization** touch every pixel (W·H). For a 600×600 photo that's 360k iterations × a few ops. Expect this to dominate. Mitigate: read `imageData` once into a flat array; index by computed offset; avoid function-call overhead in the inner loop (inline `bitAnd(v,255)`); avoid array re-assignment (use `@`).
- **HybridBinarizer** is O(W·H) with small constant; keep it. It also short-circuits block scanning once dynamic range > `MIN_DYNAMIC_RANGE (24)` — preserve that early-out.
- **FinderPatternFinder** scans rows with `MIN_SKIP` row stepping — preserve skipping; don't scan every row unless `TRY_HARDER`.
- **Pass arrays by reference everywhere** (`@`). A single accidental by-value copy of a 360k-element array per call will destroy throughput.
- **Reed–Solomon and bitstream** are tiny (hundreds of codewords) — not worth optimizing.
- If throughput is insufficient for large images, **downscale before decode** (set image width/height before reading `imageData`); QR tolerates 2–4 px/module. This changes pixels, so validate fixtures at native size first.
- Memory: the PHP test sets a 2 GB limit defensively; in practice the flat arrays are W·H integers. xTalk arrays are heavier than C arrays — consider storing the luminance plane as a **binary string** (1 byte/pixel via `numToByte`) and reading with `byteToNum(byte n of …)` to cut memory and GC pressure for very large images.

---

## 12. Suggested file layout and build order

```
qr/
  qrCompat.lc                  -- §6 helpers (u32, shifts, arraycopy, fill_array, ntz, hashCode)
  mathUtils.lc
  bitArray.lc   bitMatrix.lc   bitSource.lc
  genericGF.lc  genericGFPoly.lc  reedSolomonDecoder.lc
  luminanceSource.lc           -- imageData → greyscale (§7)
  globalHistogramBinarizer.lc  hybridBinarizer.lc  binaryBitmap.lc
  perspectiveTransform.lc  gridSampler.lc
  finderPatternFinder.lc  alignmentPatternFinder.lc  detector.lc
  version.lc  errorCorrectionLevel.lc  mode.lc  formatInformation.lc
  dataMask.lc  dataBlock.lc  bitMatrixParser.lc
  characterSetECI.lc  decodedBitStreamParser.lc  decoder.lc
  resultPoint.lc
  qrCodeReader.lc  qrReader.lc -- public API (§9)
  tables/  sjis.dat  gb2312.dat  -- optional (§8.7)
```
Load order on the server: `include` (or `start using` for script-only stacks) `qrCompat.lc` first, then dependencies bottom-up, finally `qrReader.lc`. Run all `*_Init` (static-table) handlers once at startup (Mode, DataMask, GenericGF, Version tables).

**Build sequence (matches the test order in §10):** compat → GF/RS → bit structures → luminance/binarizer → detector/geometry → parser/decoder → public API.

**Tooling suggestion:** auto-generate `version.lc`, the `FORMAT_INFO` lookup, and the ECI table directly from the PHP source with a small generator script, rather than hand-typing ~250 lines of constants. Transcription errors in these tables are the most common silent failure.

---

## 13. Risk register / pitfall checklist

Tick every box before declaring parity:

- [ ] **Unsigned vs signed words** — no comparisons to negative literals survive; all packed words normalized via `u32`. (`mask=-1` → `0xFFFFFFFF`.)
- [ ] **`>>>` vs `>>`** — every PHP `uRShift`/`sdvig3` mapped to `uShr`; arithmetic `>>` on possibly-negative words uses `aShr`; `>>` on non-negative uses `div 2^n`.
- [ ] **`1 << k`** never overflows silently — use `shl`/`2^k` and `u32`.
- [ ] **0-based indexing** preserved throughout; string byte access uses `byte (i+1)`.
- [ ] **`fill_array(count<=0)` returns `[0]`** quirk reproduced.
- [ ] **Dead debug array in `BitMatrix::set`** omitted.
- [ ] **ErrorCorrectionLevel ordinal mapping** (L/M/Q/H vs bit field M=00,L=01,H=10,Q=11) reproduced, not "corrected."
- [ ] **Version EC-block table** transcribed for all 40 versions and verified (ideally generated).
- [ ] **DataMask refs 5 and 6** match the canonical formulas (sum==0 vs (sum&1)==0).
- [ ] **Mirror retry** in `Decoder`/`BitMatrixParser` preserved (catch → remask → setMirror → mirror → retry → metadata).
- [ ] **DataBlock de-interleave** two-pass logic exact (short vs long blocks).
- [ ] **Charset gap** addressed: Byte/UTF-8/ISO-8859-1 native; Kanji/Hanzi via table, shell, or documented limitation.
- [ ] **Arrays passed by reference** (`@`) in all hot paths; no inadvertent copies.
- [ ] **imageData byte order** confirmed `0,R,G,B`; full-resolution (lockLoc, no scaling) for fixture validation.
- [ ] **All five golden fixtures** pass with the specified hints.
- [ ] **Exceptions** never escape the public API; tagged `NotFound/Format/Checksum` produce empty/false.

---

## 14. Summary

The port is large but mechanical: ~50 small classes, two shallow inheritance chains, and a handful of big constant tables. **The entire risk concentrates in three places**: (1) the 32-bit signed/unsigned + shift semantics (§6), (2) the verbatim QR data tables (§8.5), and (3) server-side luminance acquisition replacing GD (§7). Get the `qrCompat.lc` integer layer provably correct first, validate Reed–Solomon end-to-end as the canary, transcribe the tables by generator rather than by hand, and diff every pipeline stage against an instrumented copy of the PHP original. Everything else is a direct, line-for-line transliteration where the PHP source — Java idioms and all — is the authoritative contract.
