- **The live preview and the blocks follow every change to an image or a
  relation, and another editor's changes reach the blocks**. A preview option
  declared on an asset or relation (`rerender_on_change [[:cover]]`, or in
  `reassign_on_change`) fired only when the image was picked in this editor:
  an upload, a removal, or another editor's pick (which arrives as
  `cover_id`) left the preview as it was, and after an earlier pick the
  preview kept showing that image. A relation picked in a subform row now
  fires a trigger on the subform, as typing in the row does, and renders at
  once rather than after 1.2 seconds. Blocks that show entry fields
  (`{{ entry.title }}`, `{% picture entry.cover %}`) now update when another
  editor changes the field, as they do when you type in it.
