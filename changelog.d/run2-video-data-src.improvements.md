- **`mix brando.migrate55` lists front-end scripts that read a video's
  `data-src` from the `<video>`.** Since 0.55 a file video's `data-src` sits
  on its `[data-smart-video]` wrapper, and the `<video>` carries `src` unless
  it preloads, so a site script that copies `video.getAttribute('data-src')`
  into `src` sets `src="null"` and the video does not play. The task scans
  `assets/` (not `node_modules`, build output or `assets/backend`) for
  `getAttribute('data-src')` and `.dataset.src` in scripts that handle videos,
  and names each line with what to read instead. It changes nothing.
