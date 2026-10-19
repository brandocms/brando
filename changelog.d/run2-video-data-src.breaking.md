- A file video's `data-src` is on its `[data-smart-video]` wrapper; the `<video>` has it only when
  it preloads, so a site script that reads it from the `<video>` sets `src` to `"null"`
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
  Read `el.closest('[data-smart-video]').dataset.src` instead; `mix brando.migrate55` lists the
  scripts under `assets/` that read `data-src` from a video.
