## Clipboard shell-out. The helper binary depends on the build flavor:
##   X11 (default) → xclip
##   -d:wayland    → wl-copy / wl-paste (wl-clipboard package)
## Missing helper → silent no-op.
##
## Both X11 and Wayland expose two independent selections:
##   CLIPBOARD — the explicit-copy buffer (Ctrl+C / Ctrl+V).
##   PRIMARY   — the just-selected buffer (highlight → middle-click paste).
## Native apps write to both: PRIMARY on selection finalize, CLIPBOARD on
## explicit copy. We mirror that contract.

import std/[osproc, streams]

when defined(wayland):
  const
    pasteCmd = "wl-paste"
    pasteArgsClipboard = @["-n"]            # -n: don't append trailing newline
    copyCmd = "wl-copy"
    copyArgsClipboard: seq[string] = @[]    # default selection = clipboard
    copyArgsPrimary = @["-p"]               # -p: primary selection
else:
  const
    pasteCmd = "xclip"
    pasteArgsClipboard = @["-selection", "clipboard", "-o"]
    copyCmd = "xclip"
    copyArgsClipboard = @["-selection", "clipboard", "-i"]
    copyArgsPrimary = @["-selection", "primary", "-i"]

proc clipboardGet*(): string =
  ## Reads CLIPBOARD selection. Both helpers (with their respective flags)
  ## emit raw bytes with no trailing \n, which is what we want when piping
  ## into PTYs / palette buffers.
  try:
    let p = startProcess(pasteCmd, args = pasteArgsClipboard,
                        options = {poUsePath})
    # waitForExit reaps but doesn't release the pipe FDs — without close() we
    # leak per call and eventually EMFILE makes paste/copy silently no-op.
    defer: p.close()
    result = p.outputStream.readAll()
    discard p.waitForExit()
  except CatchableError:
    discard

proc writeSelection(args: seq[string], s: string) =
  try:
    let p = startProcess(copyCmd, args = args, options = {poUsePath})
    defer: p.close()
    p.inputStream.write(s)
    p.inputStream.close()
    discard p.waitForExit()
  except CatchableError:
    discard

proc clipboardSet*(s: string) =
  ## Explicit-copy target (Ctrl+C / Ctrl+Shift+C path).
  writeSelection(copyArgsClipboard, s)

proc clipboardSetPrimary*(s: string) =
  ## Selection-finalize target (mouse-up / shift+arrow). Middle-click pastes.
  writeSelection(copyArgsPrimary, s)

proc clipboardSetBoth*(s: string) =
  clipboardSet(s)
  clipboardSetPrimary(s)
