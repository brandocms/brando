- **The live preview and the blocks follow every change to an image or a
  relation, and another editor's changes reach the blocks** (#3224). A preview option
  declared on an image, video or file field (`rerender_on_change [[:cover]]`,
  or in `reassign_on_change`) fired only when the asset was picked in this
  editor: an upload, a removal, or another editor's pick (which arrives as
  `cover_id`) left the preview as it was. After an earlier pick the preview
  kept showing that asset, also over another editor's pick, an upload, or a
  title edited in the asset's drawer. A relation picked in a subform row now
  fires a trigger declared on the subform, as typing in the row does. Blocks
  that show entry fields (`{{ entry.title }}`, `{% picture entry.cover %}`)
  now update when another editor changes the field, as they do when you type
  in it. A revision loaded as a working copy, a restored recovery copy or a
  translation brings its own images and relations to the preview, rather
  than one picked before it, and a drawer save in a subform updates that
  row's asset. Clearing or resetting an image, video or file in a subform
  row, or putting a gallery there, no longer takes the form down while
  another row's removal is unsaved, and changes the row the form shows.

- **A select's `update_relation` fetcher may return the record** (#3224).
  A fetcher written as a `get_x!` query, as the container's palette select
  is, returns the record rather than `{:ok, record}`, and the select put
  nothing on the relation, so the form and the preview lost it until a
  reload.
