-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Seth Morrow
-- Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
-- =====================================================================
-- "Verbose Decode" button -- walks the decode pipeline one stage at a time and
-- reports what each stage produced into field "output", to show the library off.
-- If the single-pass walk can't find/read the code, it falls back to the
-- one-call robust API so the demo still succeeds where it can.
--
-- It calls a few INTERNAL pipeline handlers (luminanceSource_*, binaryBitmap_*,
-- dt_detect, dec_decode, bitMatrix_*) purely to narrate the stages -- they are
-- in scope because the whole library lives in the stack script. For real use you
-- only need the one-liner the "Decode QR" button uses.
--
-- EVIDENCE: verified statically; needs an OXT pass (see the README).
-- =====================================================================

local sOutCard      -- the card holding field "output", captured before any yield
local sBusy         -- re-entry guard: qrEcho pumps messages (wait ... with messages)

on mouseUp
   local tPath, tData, tMark, tMaxDim
   local tPlane, tStep, tSrc, tBmp, tBlack, tHints, tDet, tPts, tRes, e

   -- a second click while a decode is narrating would interleave two runs
   if sBusy is true then exit mouseUp
   -- an unqualified `field "output"` resolves against the defaultStack (whatever
   -- stack is frontmost), and qrEcho yields to the event loop between stages, so
   -- pin the output card once, up front (xtalk-suite engine notes 5.3)
   put the long id of this card into sOutCard
   put empty into field "output" of sOutCard
   answer file "Choose a QR image to inspect" with type "Images|png,jpg,jpeg,gif,bmp"
   if it is empty then exit mouseUp
   put it into tPath
   put url ("binfile:" & tPath) into tData
   put true into sBusy

   qrEcho "xtQRdecoder -- verbose pipeline"
   qrEcho "=============================="
   qrEcho "STEP 0 - input"
   qrEcho "   file : " & tPath
   qrEcho "   size : " & (the number of bytes of tData) & " bytes"
   qrEcho ""

   put 1200 into tMaxDim

   try
      -- [A] decode the compressed image to a raw 4-byte/pixel plane
      put the milliseconds into tMark
      put luminanceSource_decodeRawPlane(tData) into tPlane
      qrEcho "STEP 1 - image decode    (" & (the milliseconds - tMark) & " ms)"
      qrEcho "   source : " & tPlane["width"] & " x " & tPlane["height"] & " px"
      qrEcho "   raw    : " & (the number of bytes of tPlane["raw"]) & " bytes  (4 B/px, 0,R,G,B)"
      qrEcho ""

      -- [A'] greyscale + nearest-neighbour downsample (a documented hot loop)
      put the milliseconds into tMark
      put luminanceSource_stepForDims(tPlane["width"], tPlane["height"], tMaxDim) into tStep
      put luminanceSource_fromRawPlane(tPlane, tMaxDim) into tSrc
      qrEcho "STEP 2 - greyscale       (" & (the milliseconds - tMark) & " ms)"
      qrEcho "   maxDim : " & tMaxDim & " px  ->  downsample step " & tStep
      qrEcho "   grid   : " & tSrc["width"] & " x " & tSrc["height"] & "  (luma 0-255, row-major)"
      qrEcho ""

      -- [B] binarize with the hybrid local-adaptive threshold
      put the milliseconds into tMark
      put binaryBitmap_new(tSrc, "hybrid") into tBmp
      put binaryBitmap_getBlackMatrix(tBmp) into tBlack
      qrEcho "STEP 3 - binarize hybrid (" & (the milliseconds - tMark) & " ms)"
      qrEcho "   matrix : " & bitMatrix_getWidth(tBlack) & " x " & bitMatrix_getHeight(tBlack) & "  (1 bit/px, true = black)"
      qrEcho ""

      -- [C] detect finder patterns -> module size -> perspective transform -> sample
      put the milliseconds into tMark
      put true into tHints["TRY_HARDER"]
      put dt_detect(tBlack, tHints) into tDet
      put tDet["points"] into tPts
      qrEcho "STEP 4 - detect          (" & (the milliseconds - tMark) & " ms)"
      qrEcho "   grid   : " & tDet["dimension"] & " modules/side  (~ version " & ((tDet["dimension"] - 17) div 4) & ")"
      qrEcho "   finder : TL " & qrPt(tPts[1]) & "   TR " & qrPt(tPts[2]) & "   BL " & qrPt(tPts[0])
      if tPts[3] is not empty then
         qrEcho "   align  : " & qrPt(tPts[3])
      end if
      qrEcho ""
      if tDet["dimension"] <= 60 then
         qrEcho "   sampled grid (the de-skewed QR itself):"
         qrEcho qrMatrixAscii(tDet["bits"])
      end if

      -- [D-F] format/version -> un-mask -> de-interleave -> Reed-Solomon -> bitstream
      put the milliseconds into tMark
      put dec_decode(tDet["bits"]) into tRes
      if tRes["error"] is not empty then throw tRes["error"]
      qrEcho "STEP 5 - decode bits     (" & (the milliseconds - tMark) & " ms)"
      qrEcho "   version: " & tRes["version"]
      qrEcho "   ecLevel: " & tRes["ecLevel"]
      qrEcho "   mask   : " & tRes["mask"]
      if tRes["mirrored"] is true then
         qrEcho "   note   : symbol decoded on the mirror retry"
      end if
      qrEcho "   payload: " & (the number of bytes of tRes["bytes"]) & " bytes"
      qrEcho ""
      qrEcho "=============================="
      qrEcho "DECODED TEXT:"
      qrEcho tRes["text"]
   catch e
      qrEcho ""
      qrEcho "x  single-pass pipeline stopped here:"
      qrEcho "   " & e
      qrEcho ""
      qrEcho "-> retrying with the one-call robust API:"
      qrEcho "   qrDecodeResultRobust(bytes, " & quote & "TRY_HARDER" & quote & ")"
      put qrDecodeResultRobust(tData, "TRY_HARDER") into tRes
      if tRes["error"] is empty then
         qrEcho "OK recovered via '" & tRes["strategy"] & "' @ " & tRes["procW"] & "x" & tRes["procH"] & ":"
         qrEcho ""
         qrEcho tRes["text"]
      else
         qrEcho "x  no QR code found: " & tRes["error"]
      end if
   end try
   put false into sBusy
end mouseUp


-- append one line to field "output" and let the screen repaint between stages
-- (qualified through sOutCard: after `wait ... with messages` another stack may
-- be in front, and an unqualified field reference would resolve against it)
on qrEcho pLine
   put pLine & return after field "output" of sOutCard
   set the scroll of field "output" of sOutCard to (the formattedHeight of field "output" of sOutCard)
   wait 0 milliseconds with messages
end qrEcho


-- a detected reference point as "(x, y)" to one decimal place
function qrPt pPt
   return "(" & (round(pPt["x"] * 10) / 10) & ", " & (round(pPt["y"] * 10) / 10) & ")"
end qrPt


-- render a (small) sampled bit matrix as monospace block art
function qrMatrixAscii pM
   local tW, tH, x, y, tLine, tOut
   put bitMatrix_getWidth(pM) into tW
   put bitMatrix_getHeight(pM) into tH
   put empty into tOut
   repeat with y = 0 to (tH - 1)
      put empty into tLine
      repeat with x = 0 to (tW - 1)
         if bitMatrix_get(pM, x, y) then
            put "##" after tLine
         else
            put "  " after tLine
         end if
      end repeat
      put tLine & return after tOut
   end repeat
   return tOut
end qrMatrixAscii
