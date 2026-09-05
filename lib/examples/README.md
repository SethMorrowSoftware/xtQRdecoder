# xtQRdecoder examples

Three ways to see the decoder work, from the one-file showcase to the two
snippets you paste into your own stack.

| File | What it is | Needs |
|---|---|---|
| **`xtQRdecoder-demo.livecodescript`** | **The showcase stack.** One paste-and-run file, laid out the way the xTalk Suite's demos are: it builds its own tabbed window on open (the suite's UI kit v2, carried verbatim), CARRIES the whole library inside itself, and carries seven sample images. Tabs: Decode (file picker, paste, drag-and-drop or a sample, shown in a preview beside the controls; every hint; every result key), Pipeline (the library stage by stage, with the de-skewed grid as block art), Samples (seven PASS/FAIL decodes against known texts - an engine record for your machine), About (the boot self-check log). | A desktop xTalk engine (OpenXTalk, or 9.6.3+). Nothing else. |
| `scanButton.livecodescript` | A ready-to-paste "Scan QR" button for your own app, with the mobile-camera variant. | `lib/xtQRdecoder.livecodescript` loaded with `start using` |
| `demoStack/` | A two-button demo (Decode, Verbose Decode) with a step-by-step README, for when you want to see the two calls in a stack you built by hand. | the library pasted into your stack script |

## Running the showcase

The demo is a stack SCRIPT, so you paste it into a stack and let it build
itself (opening the `.livecodescript` file itself loads the script and builds
no window - that is the engine, not the demo):

1. In OpenXTalk, create a new one-card stack: `File > New Mainstack`.
2. Open that stack's script: `Object > Stack Script`.
3. Open `xtQRdecoder-demo.livecodescript` in a text editor, copy ALL of it,
   paste it into the stack script, and Apply.
4. **Close the stack window and reopen it.** Reopening fires `preOpenStack`,
   which builds the whole UI, and `openStack`, which runs the boot
   self-check. (Or run `send "preOpenStack" to this stack` from the message
   box, then `send "openStack" to this stack`.)
5. Open the **Samples** tab and click **Decode all samples**. Seven `PASS`
   lines (plus one for the inverted symbol correctly failing without its
   flag) is the whole point. Then drop a photo of any QR code on the window
   and click **Decode (robust)**.

Two things the demo prints are worth keeping: the **About** tab's boot
self-check block and the **Samples** log. Both end with a count line, and
both are the record an engine pass can quote (`docs/VERIFICATION.md` says
where to put it).

## What is carried, and what keeps it exact

The showcase is three carried blocks plus the demo's own code, in this
order (OpenXTalk resolves script-level constants and locals by lexical
position, so the library comes first):

1. between `>>> BEGIN EMBEDDED LIBRARIES` and `<<< END EMBEDDED LIBRARIES`:
   `lib/xtQRdecoder.livecodescript`, the combined library, minus its
   `script` line;
2. between the `SUITE UI KIT v2 BEGIN/END` markers: the xTalk Suite's UI kit
   (`tools/ui-kit.livecodescript`, vendored byte-identical from
   `SethMorrowSoftware/xtalk-suite`);
3. between the `DEMO SELF-CHECK v1 BEGIN/END` markers: the suite's boot
   self-check block (`tools/demo-selfcheck.livecodescript`, vendored the same
   way).

`python3 tools/sync_demo_embeds.py` rewrites all three from their masters and
regenerates `kQdScControls`, the list of every control the demo names (the
self-check asserts each exists). `--check` runs in CI and refuses a stale
copy; `tools/test_gates.py` proves it does. Nobody edits inside the
sentinels: change the module, the master or the demo's own code, and re-sync.

## Honesty

The library's unit harness and golden photographs were engine-passed on a
9.6.11-class xTalk *server* build at the 0.1.0 release. The showcase, the
scan button and the demo stack have not been run on an engine yet: they are
*verified statically; needs an OXT pass*. The showcase exists so that pass
can be quoted rather than described.
