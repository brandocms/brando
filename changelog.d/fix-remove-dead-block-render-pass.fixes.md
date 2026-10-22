- A module save no longer runs a block render pass that rendered nothing
  ([#3130](https://github.com/brandocms/brando/pull/3130)).
  `Blocks.render_blocks/1` is removed. Rename `Blocks.sync_and_render_blocks/3` to
  `Blocks.sync_blocks/3`, which returns the synced block ids.
