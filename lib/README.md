# xtQRdecoder — script-only library (`xtQRdecoder.livecodescript`)

A single-file, **script-only stack** containing the entire xtQRdecoder QR decoder.
Drop it into any project and use it on **OpenXTalk, xTalk desktop, mobile, or
server** — no externals, no GUI, no compilation. It's the standard,
source-control-friendly xTalk library format: plain text, loadable by any engine
with `start using`.

> Generated from the `qr/*.lc` modules by
> [`tools/build_livecodescript.py`](../tools/build_livecodescript.py) — the modules
> are the single source of truth, so **don't edit the combined file by hand**
> (edit a module and rebuild; see [Rebuilding](#rebuilding)).

## Install

Copy `lib/xtQRdecoder.livecodescript` into your project, then load it once early
in your app (e.g. in `preOpenStack`):

```xtalk
start using stack (the folder of me & "/xtQRdecoder.livecodescript")
```

Once `start using` succeeds, **all the public functions below are in scope**
anywhere in your app (it's a back-script / library stack).

## Public API

| Function | Returns |
|---|---|
| **`qrDecodeResultRobust(imageBytes [,hints [,maxDim]])`** | **result array — use this for photos** (multi-strategy: hybrid+global, two scales) |
| `qrDecodeResult(imageBytes [,hints])` | result array, single pass / full resolution (never throws) |
| `qrDecodeFromData(imageBytes [,hints])` | decoded **text** only, single pass; empty on failure |
| `qrDecodeFromFile(path [,hints])` | decoded **text** only, single pass; empty on failure |

> **Use `qrDecodeResultRobust` for real-world photographs** (glare, blur, dense
> codes). It's what the `qr_demo.lc` scanner uses. The single-pass calls decode
> once at full resolution and are best suited to clean, already-cropped images.

Result-array keys: `["text"]`, `["bytes"]`, `["error"]`, `["version"]`,
`["ecLevel"]`, `["mask"]`, `["points"]`, and (robust only) `["strategy"]`,
`["procW"]`, `["procH"]`. Hints: `TRY_HARDER`, `BINARY_MODE`, `PURE_BARCODE`,
`NR_ALLOW_SKIP_ROWS`, `ALLOWED_DEVIATION`, `MAX_VARIANCE`. See the
[root README](../README.md#api-reference) for the full reference, and
[Troubleshooting](../README.md#troubleshooting) / [Limitations](../README.md#limitations)
for image-format and Kanji/Hanzi notes.

## Example — decode a file the user picks

```xtalk
on mouseUp
   answer file "Choose a QR image"
   if it is empty then exit mouseUp
   put qrDecodeResultRobust(url ("binfile:" & it), "TRY_HARDER") into tRes
   if tRes["error"] is empty then
      answer "Decoded (v" & tRes["version"] & ", EC " & tRes["ecLevel"] & "):" \
         & return & tRes["text"]
   else
      answer "No QR found:" & return & tRes["error"]
   end if
end mouseUp
```

A complete, ready-to-paste **"Scan QR" button** (with the mobile-camera variant)
is in [`examples/scanButton.livecodescript`](examples/scanButton.livecodescript).

## Rebuilding

`lib/xtQRdecoder.livecodescript` is generated; after changing any `qr/*.lc`
module, regenerate it with `python3 tools/build_livecodescript.py` (and
`--check` to verify it's in sync). See
[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §7 for details.

## License

Apache-2.0, same as the rest of xtQRdecoder. Full attribution to ZXing and
`khanamiryan/php-qrcode-detector-decoder` is in the repository
[`NOTICE`](../NOTICE).
