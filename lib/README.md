# xtQRdecoder - script-only library (`xtQRdecoder.livecodescript`)

A single-file, **script-only stack** containing the entire xtQRdecoder QR decoder.
Drop it into any project and use it on **OpenXTalk, xTalk desktop, mobile, or
server** - no externals, no GUI, no compilation. It's the standard,
source-control-friendly xTalk library format: plain text, loadable by any engine
with `start using`.

> Generated from the `qr/*.lc` modules by
> [`tools/build_livecodescript.py`](../tools/build_livecodescript.py) - the modules
> are the single source of truth, so **don't edit the combined file by hand**
> (edit a module and rebuild; see [Rebuilding](#rebuilding)).

> **Verification status.** The library's algorithm is proven under the headless
> model and the static gates on every push (see
> [`docs/VERIFICATION.md`](../docs/VERIFICATION.md)); the unit harness and the
> golden fixtures passed on a 9.6.11-class xTalk *server* build at the 0.1.0
> release. Loading this file with `start using` on a desktop or mobile engine has
> **not** been observed on an engine yet: that leg is *verified statically; needs
> an OXT pass*. If you run it, please record the engine and the result in an
> issue.

## Install

Copy `lib/xtQRdecoder.livecodescript` into your project, then load it once early
in your app (e.g. in `preOpenStack`). There is no `folder` property of a stack;
derive the folder from the stack's own file path:

```xtalk
on preOpenStack
   local tDir
   put the effective filename of this stack into tDir
   set the itemDelimiter to "/"
   delete the last item of tDir            -- the folder holding this stack
   start using stack (tDir & "/xtQRdecoder.livecodescript")
end preOpenStack
```

Once `start using` succeeds, **all the public functions below are in scope**
anywhere in your app (it's a back-script / library stack). `qrLibraryVersion()`
returns the library version (`"0.2.0"`), which is the cheap way to check that
the file you loaded is the one you think it is.

## Public API

| Function | Returns |
|---|---|
| **`qrDecodeResultRobust(imageBytes [,hints [,maxDim]])`** | **result array - use this for photos** (multi-strategy: hybrid+global binarizers over a resolution ladder) |
| `qrDecodeResult(imageBytes [,hints])` | result array, single pass / full resolution (never throws) |
| `qrDecodeFromData(imageBytes [,hints])` | decoded **text** only, single pass; empty on failure |
| `qrDecodeFromFile(path [,hints])` | decoded **text** only, single pass; empty on failure |
| `qrLibraryVersion()` | the library version string |

> **Use `qrDecodeResultRobust` for real-world photographs** (glare, blur, dense
> codes). It's what the `qr_demo.lc` scanner uses. The single-pass calls decode
> once at full resolution and are best suited to clean, already-cropped images.

Result-array keys: `["text"]`, `["bytes"]`, `["error"]`, `["version"]`,
`["ecLevel"]`, `["mask"]`, `["points"]`, `["charset"]`, `["fnc1"]`,
`["symbologyModifier"]`, `["structuredAppendSeq"]` / `["structuredAppendParity"]`,
`["mirrored"]`, `["inverted"]`, and (robust only) `["strategy"]`, `["step"]`,
`["procW"]`, `["procH"]`, `["attempts"]`. Hints: `TRY_HARDER`, `ALSO_INVERTED`,
`BINARY_MODE`, `PURE_BARCODE`, `NR_ALLOW_SKIP_ROWS`, `ALLOWED_DEVIATION`,
`MAX_VARIANCE`. See the [root README](../README.md#api-reference) for the full
reference, and [Troubleshooting](../README.md#troubleshooting) /
[Limitations](../README.md#limitations) for image-format and Kanji/Hanzi notes.

## Example - decode a file the user picks

```xtalk
on mouseUp
   local tRes
   answer file "Choose a QR image"
   if it is empty then exit mouseUp
   put qrDecodeResultRobust(url ("binfile:" & it), "TRY_HARDER,ALSO_INVERTED") into tRes
   if tRes["error"] is empty then
      answer "Decoded (v" & tRes["version"] & ", EC " & tRes["ecLevel"] & "):" \
         & return & tRes["text"]
   else
      answer "No QR found:" & return & tRes["error"]
   end if
end mouseUp
```

**The showcase stack**, [`examples/xtQRdecoder-demo.livecodescript`](examples/xtQRdecoder-demo.livecodescript),
is a one-file demo in the xTalk Suite's style that carries this library inside
it and builds its own tabbed window: every hint, every result key, the pipeline
stage by stage, and seven embedded samples decoded for a PASS/FAIL record of your
engine. A complete, ready-to-paste **"Scan QR" button** (with the mobile-camera
variant) is in [`examples/scanButton.livecodescript`](examples/scanButton.livecodescript),
and a two-button demo stack in [`examples/demoStack/`](examples/demoStack/).
[`examples/README.md`](examples/README.md) explains all three.

## Rebuilding

`lib/xtQRdecoder.livecodescript` is generated; after changing any `qr/*.lc`
module, regenerate it with `python3 tools/build_livecodescript.py` (and
`--check` to verify it's in sync; CI runs the check). See
[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) section 7 for details.

## License

Apache-2.0, same as the rest of xtQRdecoder. Full attribution to ZXing and
`khanamiryan/php-qrcode-detector-decoder` is in the repository
[`NOTICE`](../NOTICE).
