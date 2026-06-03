-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Seth Morrow
-- Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
-- =====================================================================
-- xtQRdecoder — example "Scan QR" button script (desktop / mobile equivalent of
-- qr_demo.lc). Drop this on a button. It lets the user pick an image, runs it
-- through the xtQRdecoder script-only library exactly the way the web demo does
-- (qrDecodeResultRobust + TRY_HARDER), and reports the decoded text + metadata.
--
-- SETUP (once): make sure the library stack is loaded. Easiest is to load it in
-- your app's startup, e.g. in the card/stack script:
--
--    on preOpenStack
--       start using stack (the folder of this stack & "/xtQRdecoder.livecodescript")
--    end preOpenStack
--
-- If you'd rather keep it self-contained, this script loads it on demand from a
-- file next to the stack (see qrEnsureLibrary below) — adjust the path to wherever
-- you put lib/xtQRdecoder.livecodescript.
-- =====================================================================

on mouseUp
   -- 1) make sure the xtQRdecoder library is in scope
   if not qrEnsureLibrary() then
      answer error "Could not load xtQRdecoder.livecodescript. Put it next to this stack."
      exit mouseUp
   end if

   -- 2) let the user choose an image (on mobile, use mobilePickPhoto instead — see note)
   answer file "Choose a QR image" with type "Images|png,jpg,jpeg,gif,bmp"
   if it is empty then exit mouseUp        -- cancelled
   local tPath
   put it into tPath

   -- 3) decode exactly like qr_demo.lc: robust multi-strategy + TRY_HARDER,
   --    1200px base scale. The library never throws; failures arrive in ["error"].
   local tHints, tRes
   put true into tHints["TRY_HARDER"]
   put qrDecodeResultRobust(url ("binfile:" & tPath), tHints, 1200) into tRes

   -- 4) show the outcome
   if tRes["error"] is empty then
      local tMsg
      put tRes["text"] & return & return into tMsg
      put "Version "  & tRes["version"]  & "  ·  EC " & tRes["ecLevel"] \
         & "  ·  mask " & tRes["mask"] after tMsg
      put return & "Binarizer: " & tRes["strategy"] \
         & "  ·  processed " & tRes["procW"] & "×" & tRes["procH"] & " px" after tMsg
      answer information tMsg with "Copy text" or "OK"
      if it is "Copy text" then set the clipboardData["text"] to tRes["text"]
   else
      -- precise reason (e.g. the JPEG-codec guard, or "NotFound: ...")
      answer warning ("No QR code found." & return & return & tRes["error"])
   end if
end mouseUp


-- Ensure the script-only library is loaded. Returns true if its API is callable.
-- Safe to call repeatedly (start using is idempotent for an already-loaded stack).
function qrEnsureLibrary
   -- already loaded? (the public function is in scope)
   if the keys of the stacksInUse contains "xtQRdecoder" then return true
   if "xtQRdecoder" is among the lines of the stacksInUse then return true

   -- load it from a file next to this stack — adjust the path if you keep it elsewhere
   local tLib
   put the folder of the topStack & "/xtQRdecoder.livecodescript" into tLib
   if there is a file tLib then
      start using stack tLib
   else
      -- fallback: a couple of common locations
      put specialFolderPath("resources") & "/xtQRdecoder.livecodescript" into tLib
      if there is a file tLib then start using stack tLib
   end if

   -- confirm a public handler is now reachable
   return ("qrDecodeResultRobust" is in the handlers of stack "xtQRdecoder")
end qrEnsureLibrary


-- ---------------------------------------------------------------------
-- MOBILE NOTE: replace step 2 with a camera/library pick. mobilePickPhoto puts
-- the photo into an image; export it to a file, then decode the file bytes:
--
--    mobilePickPhoto "camera"                       -- or "library"
--    put the templateImage into ...                 -- engine-specific; or:
--    export image "the picked image" to file tTmp as PNG
--    put qrDecodeResultRobust(url ("binfile:" & tTmp), tHints, 1200) into tRes
--
-- qrDecodeResultRobust downsamples large camera frames for you, so you don't
-- need to pre-scale. Everything else (steps 3-4) is identical.
-- ---------------------------------------------------------------------
