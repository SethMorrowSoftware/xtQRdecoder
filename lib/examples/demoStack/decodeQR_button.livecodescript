-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Seth Morrow
-- Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
-- ZXing is Apache-2.0; see the NOTICE file for full attribution.
-- =====================================================================
-- "Decode QR" button -- the simplest robust decode.
-- Put this script on a button. The result lands in field "output" on the same
-- card. The xtQRdecoder library must be in scope (pasted into the stack script,
-- or loaded with `start using` -- see this folder's README).
--
-- EVIDENCE: verified statically; needs an OXT pass (see the README).
-- =====================================================================

on mouseUp
   local tPath, tRes, tCard
   -- remember the card that owns the output field BEFORE calling the library:
   -- an unqualified `field "output"` resolves against the defaultStack, which is
   -- whatever stack is frontmost (xtalk-suite engine notes 5.3)
   put the long id of this card into tCard

   -- 1) ask the user for an image
   answer file "Choose a QR image" with type "Images|png,jpg,jpeg,gif,bmp"
   if it is empty then exit mouseUp        -- cancelled
   put it into tPath

   -- 2) robust, multi-strategy decode (hybrid + global binarizers, two scales)
   --    with TRY_HARDER. It never throws; any failure reason is in ["error"].
   put qrDecodeResultRobust(url ("binfile:" & tPath), "TRY_HARDER") into tRes

   -- 3) decoded text into the output field (or the reason it failed)
   if tRes["error"] is empty then
      put tRes["text"] into field "output" of tCard
   else
      put "No QR code found -- " & tRes["error"] into field "output" of tCard
   end if
end mouseUp
