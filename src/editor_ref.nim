## Re-establishes the global editor pointer that rawk_bufferlib no longer
## owns. Set once by `ui.buildUi` after `editorCreate`; read by every prawk
## module that previously reached for `editor.theEditor`.
##
## Also re-introduces the three no-arg conveniences rawk_bufferlib dropped
## (they took a global as input, which a vendorable lib can't keep).

import rawk_bufferlib

var theEditor*: ptr Editor

proc editorIsDirty*(): bool =
  if theEditor == nil: false
  else: rawk_bufferlib.editorIsDirty(theEditor)

proc editorForceOpenFile*(path: string) =
  if theEditor != nil: editorOpenFile(theEditor, path)

proc editorWrapToggleActive*() =
  if theEditor != nil: editorWrapToggle(theEditor)
