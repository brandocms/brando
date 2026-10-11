- **`brando_108` migrates Villain fragment blocks.** It wrote
  `content_blocks.fragment_id`, a column `brando_119` adds, so a pre-blocks
  site with a fragment block stopped at `brando_108` with `column
  "fragment_id" of relation "content_blocks" does not exist`. `brando_108`
  now adds the column itself, and `brando_119` leaves it in place. If your
  application has copied these two migrations but not run them,
  `mix brando.migrations.check --update` replaces the copies.

- **`brando_108` keeps the vars of a multi module block.** A multi module's
  own vars, such as a heading above its entries, and its datasource selection
  were dropped without a warning, so templates printed them empty. Only the
  entries' vars came through.

- **Legacy file videos keep looping, and a URL cover no longer prints as
  text.** Brando before 0.54 rendered every file video with `loop` and drew its
  SVG placeholder whatever the block's `cover` held. `brando_133` wrote
  `loop: false` for blocks saved without the setting, and carried a cover
  such as a Vimeo thumbnail URL over as-is, which `Brando.HTML.Video` then
  printed on the page. `brando_133` now defaults `loop` to true and turns any
  cover other than `"false"`, `"svg"` or `"true"` into `"svg"`, and
  `Brando.HTML.Video` draws the placeholder for a cover string it does not
  know. Safe markup passed as `cover` still renders as before.

- **`brando_133` keeps legacy embeds and each block's video shape.** A Vimeo
  or YouTube block saved with only its remote id got a video record under a
  provider URL built from that id, but the refs were linked by the raw id, so
  they were never linked and lost the video when their data was cleaned up.
  Both steps now use the same source. Blocks that share a file share one
  video, sized by the first block that used it (the choice was arbitrary
  before); a block that drew the file in another shape keeps that shape as
  its own aspect ratio.
