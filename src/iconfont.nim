## Icon-font fallback for symbol glyphs.
##
## The system mono font (loaded by rawk-bufferlib's loadFont) typically lacks
## the high-PUA codepoints that TUIs and Nerd-Font-aware programs emit —
## think Powerline separators, claude-code's status icons, lazygit glyphs.
## Drawing those through the primary face paints .notdef tofu boxes.
##
## We probe for a "Symbols Nerd Font" face (purpose-built fallback that
## ships only the icon glyphs) once at startup, then `drawGlyphWithFallback`
## activates it just for the codepoints the primary doesn't carry. Mirrors
## Exrawk's icons.nim approach; the per-glyph charmap check via
## `fontHasGlyph` is what keeps regular non-ASCII (Greek, math, CJK) on the
## primary face — the symbol font has no Latin coverage, so unconditional
## swaps would regress those.

import std/[os, osproc, strutils]
import rawk_luigi
import config

var iconFont: ptr Font

proc fcMatch(family: string): string =
  ## Wrap `fc-match --format=%{file}`. Returns "" if fontconfig isn't
  ## available or the family resolves to a substitution (fc-match always
  ## returns *something* — we reject hits whose basename doesn't mention
  ## the requested family).
  try:
    let (output, code) = execCmdEx("fc-match --format=%{file} " & quoteShell(family))
    if code != 0: return ""
    let p = output.strip()
    if p.len == 0 or not fileExists(p): return ""
    let head = family.split(' ')[0].toLowerAscii
    if head notin p.toLowerAscii: return ""
    return p
  except CatchableError:
    return ""

proc probeIconFontPath*(): string =
  ## Best-effort discovery of a nerd-symbols font. Prefer the dedicated
  ## "Symbols Nerd Font Mono" (small file, exists purely to backfill the
  ## PUA glyphs); otherwise any matching .ttf/.otf under common font dirs.
  for q in ["Symbols Nerd Font Mono", "Symbols Nerd Font"]:
    let p = fcMatch(q)
    if p.len > 0: return p
  let roots = [
    "/usr/share/fonts",
    "/usr/local/share/fonts",
    getHomeDir() / ".local" / "share" / "fonts",
    getHomeDir() / ".fonts",
  ]
  for root in roots:
    if not dirExists(root): continue
    for path in walkDirRec(root, yieldFilter = {pcFile}):
      let lower = path.extractFilename.toLowerAscii
      if not lower.endsWith(".ttf") and not lower.endsWith(".otf"): continue
      if "symbols" in lower and "nerd" in lower: return path
  for root in roots:
    if not dirExists(root): continue
    for path in walkDirRec(root, yieldFilter = {pcFile}):
      let lower = path.extractFilename.toLowerAscii
      if not lower.endsWith(".ttf") and not lower.endsWith(".otf"): continue
      if "nerd" in lower and ("regular" in lower or "mono" in lower):
        return path
  ""

proc installIconFont*() =
  ## Resolve the icon face: honor `icon_font_path` from the user's config
  ## first, else probe. A miss leaves iconFont nil — drawGlyphWithFallback
  ## stays a no-op wrapper around drawGlyphCp.
  var path = config.iconFontPath
  if path.len == 0:
    path = probeIconFontPath()
    if path.len > 0: config.iconFontPath = path
  if path.len == 0 or not fileExists(path): return
  iconFont = fontCreate(path.cstring, config.fontSize)

proc iconFontLoaded*(): bool = iconFont != nil

proc drawGlyphWithFallback*(p: ptr Painter; x, y: cint; cp: cint; color: uint32) =
  ## If the active font lacks `cp` but the icon face has it, paint with the
  ## icon face. Otherwise paint with whatever's currently active — keeps
  ## regular non-ASCII on the primary face and only swaps when the swap
  ## actually rescues a glyph.
  if iconFont != nil and ui.activeFont != nil and
     fontHasGlyph(ui.activeFont, cp) == 0 and
     fontHasGlyph(iconFont, cp) != 0:
    let prev = fontActivate(iconFont)
    drawGlyphCp(p, x, y, cp, color)
    discard fontActivate(prev)
  else:
    drawGlyphCp(p, x, y, cp, color)
