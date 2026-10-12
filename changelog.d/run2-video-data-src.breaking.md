- **Front-end code that reads a file video's `data-src` from the `<video>`
  element must read it from the wrapper.** `Brando.HTML.Video` renders
  `data-src` on the `[data-smart-video]` wrapper for every file video; the
  `<video>` itself carries `data-src` only when the video preloads, and `src`
  otherwise. Brando before 0.53 preloaded every file video, so pages rendered
  then had `data-src` on the `<video>`, and a site script such as
  `video.src = video.getAttribute('data-src')` now sets `src` to `"null"` and
  the video never plays. Read `el.closest('[data-smart-video]').dataset.src`,
  or fall back to it. `mix brando.migrate55` lists the scripts that read
  `data-src` near video markup.
