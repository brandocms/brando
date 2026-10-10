- **A module save no longer runs a block render pass that never rendered
  anything** (#3130). Since 0.54, saving a module, syncing it and resolving
  stale blocks ran a per-block render that matched nothing and re-rendered
  no block; entries, which pages and the live preview render from, were
  re-rendered as before. The pass and `Blocks.render_blocks/1` are removed.
  `Blocks.sync_and_render_blocks/3` is now `Blocks.sync_blocks/3` and,
  like `Blocks.refresh_module_in_blocks/1`, returns the synced block ids.
