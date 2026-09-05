-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Seth Morrow
-- Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
-- ZXing is Apache-2.0; see the NOTICE file for full attribution.
-- =====================================================================
-- xtQRdecoder - example "Scan QR" button script (desktop / mobile equivalent of
-- qr_demo.lc). Drop this on a button. It lets the user pick an image, runs it
-- through the xtQRdecoder script-only library exactly the way the web demo does
-- (qrDecodeResultRobust + TRY_HARDER), and reports the decoded text + metadata.
--
-- SETUP (once): make sure the library stack is loaded. Easiest is to load it in
-- your app's startup, e.g. in the stack script:
--
--    on preOpenStack
--       local tDir
--       put the effective filename of this stack into tDir
--       set the itemDelimiter to "/"
--       delete the last item of tDir       -- the folder holding this stack
--       start using stack (tDir & "/xtQRdecoder.livecodescript")
--    end preOpenStack
--
-- (There is no `folder` property of a stack; `the effective filename of this
-- stack` is the engine-proven way to find a sibling file.) If you'd rather keep
-- the button self-contained, it loads the library on demand from the file next
-- to the stack (see qrEnsureLibrary below).
--
-- EVIDENCE: verified statically - linted by both checkers and built only from
-- constructs the xTalk Suite has run on OpenXTalk; this button itself has not
-- been run on an engine yet (needs an OXT pass).
-- =====================================================================

on mouseUp
   local tPath, tHints, tRes, tMsg
   -- 1) make sure the xtQRdecoder library is in scope
   if not qrEnsureLibrary() then
      answer error "Could not load xtQRdecoder.livecodescript. Put it next to this stack."
      exit mouseUp
   end if

   -- 2) let the user choose an image (on mobile, use mobilePickPhoto instead - see note)
   answer file "Choose a QR image" with type "Images|png,jpg,jpeg,gif,bmp"
   if it is empty then exit mouseUp        -- cancelled
   put it into tPath

   -- 3) decode exactly like qr_demo.lc: robust multi-strategy + TRY_HARDER,
   --    1200px base scale. The library never throws; failures arrive in ["error"].
   put true into tHints["TRY_HARDER"]
   put qrDecodeResultRobust(url ("binfile:" & tPath), tHints, 1200) into tRes

   -- 4) show the outcome
   if tRes["error"] is empty then
      put tRes["text"] & return & return into tMsg
      put "Version " & tRes["version"] & " - EC " & tRes["ecLevel"] \
         & " - mask " & tRes["mask"] after tMsg
      put return & "Binarizer: " & tRes["strategy"] \
         & " - processed " & tRes["procW"] & "x" & tRes["procH"] & " px" after tMsg
      answer information tMsg with "Copy text" or "OK"
      if it is "Copy text" then
         set the clipboardData["text"] to tRes["text"]
      end if
   else
      -- precise reason (e.g. the JPEG-codec guard, or "NotFound: ...")
      answer warning ("No QR code found." & return & return & tRes["error"])
   end if
end mouseUp


-- Ensure the script-only library is loaded. Returns true if it is in use.
-- Safe to call repeatedly (start using is idempotent for an already-loaded stack).
function qrEnsureLibrary
   local tDir, tLib, tSavedDelim
   -- already loaded? (the stacksInUse is a return-delimited list of stack names)
   if "xtQRdecoder" is among the lines of the stacksInUse then return true

   -- derive the folder holding THIS stack from its own file path, then look for
   -- the library beside it (fallback: the standalone's resources folder)
   put the effective filename of this stack into tDir
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "/"
   delete the last item of tDir
   set the itemDelimiter to tSavedDelim
   put tDir & "/xtQRdecoder.livecodescript" into tLib
   if there is not a file tLib then
      put specialFolderPath("resources") & "/xtQRdecoder.livecodescript" into tLib
   end if
   if there is a file tLib then
      start using stack tLib
   end if
   -- the proven readiness test is membership of the stacksInUse, not a probe of
   -- an unproven property
   return ("xtQRdecoder" is among the lines of the stacksInUse)
end qrEnsureLibrary


-- ---------------------------------------------------------------------
-- MOBILE NOTE (verified statically; needs an OXT mobile pass): replace step 2
-- with a camera/library pick. mobilePickPhoto places the photo in a NEW image
-- object on the current card; export it to a temporary PNG and decode the file:
--
--    mobilePickPhoto "camera"                          -- or "library"
--    if the result is "cancel" then exit mouseUp
--    put the long id of the last image of this card into tImg
--    put specialFolderPath("temporary") & "/qrscan.png" into tTmp
--    export tImg to file tTmp as PNG
--    delete tImg
--    put qrDecodeResultRobust(url ("binfile:" & tTmp), tHints, 1200) into tRes
--
-- qrDecodeResultRobust downsamples large camera frames for you, so you don't
-- need to pre-scale. Everything else (steps 3-4) is identical.
-- ---------------------------------------------------------------------
