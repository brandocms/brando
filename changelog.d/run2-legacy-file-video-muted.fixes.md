- **Converted legacy file videos stay muted, and keep their shape without a
  stray aspect ratio.** Villain video blocks had no `muted` setting, and
  `brando_133` wrote `muted: false` unless the block autoplayed. Brando before
  0.53 rendered every file video muted, and a page saved then still showed
  that HTML, so a hero video started by the site's own script lost its
  `muted` on the first resave and browsers refused to play it. A file video
  without a play button or controls is now converted with `muted: true`; one
  with either keeps its sound, and autoplay still always mutes. Blocks that
  share a file but drew it at another scale of the same shape (840×1052 and
  971×1216) no longer get an aspect-ratio override, and a file video whose
  block does keep its own aspect ratio now renders its `width`/`height`,
  orientation and cover placeholder in that shape, as embeds do. Sites that
  have already run `brando_133` can tick Muted on the video blocks that need
  it.
