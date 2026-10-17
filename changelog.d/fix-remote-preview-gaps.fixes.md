- **The live preview and the blocks follow every change to an image or a
  relation, and another editor's changes reach the blocks**. A preview option
  declared on an image, video or file field (`rerender_on_change [[:cover]]`,
  or in `reassign_on_change`) fired only when the asset was picked in this
  editor: an upload, a removal, or another editor's pick (which arrives as
  `cover_id`) left the preview as it was. After an earlier pick the preview
  kept showing that asset, also over another editor's pick, an upload, or a
  title edited in the asset's drawer. A relation picked in a subform row now
  fires a trigger declared on the subform, as typing in the row does. Blocks
  that show entry fields (`{{ entry.title }}`, `{% picture entry.cover %}`)
  now update when another editor changes the field, as they do when you type
  in it.
