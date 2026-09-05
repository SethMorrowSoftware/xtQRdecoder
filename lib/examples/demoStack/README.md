# xtQRdecoder - simple demo stack

A tiny stack that shows off the library with two buttons:

- **Decode QR** - the simplest robust decode (one call).
- **Verbose Decode** - walks the pipeline stage by stage and prints what each
  stage produced (image -> greyscale -> binarize -> detect -> decode), including the
  de-skewed QR grid as block art. If the single pass can't read the code it falls
  back to the robust one-call API.

Both ask you to pick an image and write the result into a field named `output`.

## Build it (about a minute)

1. **New stack.** Create a new main stack - this is the demo.
2. **Library into the stack script.** Open the stack's script
   (Object > Stack Script) and paste the *entire* contents of
   [`../../xtQRdecoder.livecodescript`](../../xtQRdecoder.livecodescript) into
   it - but **delete the very first line**, `script "xtQRdecoder"`. (That line
   only means something when the file is loaded as a standalone *script-only
   stack*; inside a normal stack script it's a parse error.) That is what "the
   lib is in the stack script" means: every `qrDecode...` function - and the
   internal handlers the verbose button narrates - is now in scope for the
   buttons. No `start using` needed.

   > Prefer not to inline ~4,500 lines? Keep the file next to your stack and
   > load it in `preOpenStack` instead (there is no `folder` property of a
   > stack; derive the folder from the stack's own file path):
   >
   > ```xtalk
   > on preOpenStack
   >    local tDir
   >    put the effective filename of this stack into tDir
   >    set the itemDelimiter to "/"
   >    delete the last item of tDir
   >    start using stack (tDir & "/xtQRdecoder.livecodescript")
   > end preOpenStack
   > ```
   >
   > Everything else below is identical.

3. **Output field.** Add a field and name it `output`. Make it **scrolling** and
   give it a **monospaced** font (Monaco / Consolas / Courier) so the verbose
   view's QR grid art lines up.
4. **Two buttons.** Add two buttons. Paste
   [`decodeQR_button.livecodescript`](decodeQR_button.livecodescript) into one
   (name it "Decode QR") and
   [`verboseDecode_button.livecodescript`](verboseDecode_button.livecodescript)
   into the other ("Verbose Decode").

Run it, click a button, pick a QR image.

## Notes

- `answer file` is the desktop image picker. On mobile, swap it for
  `mobilePickPhoto` and export the photo to a file first - see
  [`../scanButton.livecodescript`](../scanButton.livecodescript) for the mobile
  variant.
- For real use you only ever need the one call the **Decode QR** button makes:
  `qrDecodeResultRobust(bytes, "TRY_HARDER")`. The verbose button only reaches
  into the internal handlers (`luminanceSource_*`, `binaryBitmap_*`, `dt_detect`,
  `dec_decode`, `bitMatrix_*`) to *show* the stages.
- PNG / GIF / BMP always decode; JPEG depends on your engine build - see the
  root README's [troubleshooting](../../../README.md#jpeg-isnt-decoding).
