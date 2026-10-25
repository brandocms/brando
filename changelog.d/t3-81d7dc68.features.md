- **Bunny videos can play as an MP4 instead of the stream.** A video, a video
  block or ref, and a gallery object have a Quality: Automatic (the default)
  streams a video with controls or a play button and plays a loop as an MP4,
  Streaming always uses HLS, and an MP4 resolution (360p to 1080p) plays that
  file, falling back to the next one down. Bunny makes the MP4s when the
  library's **MP4 Fallback** encoding setting is on; a video without them
  streams. Templates set a placement's default with
  `<.video video={…} opts={[quality: :mp4_720]} />` or
  `{% video entry.video { quality: "mp4_720" } %}`, which an editor's choice
  overrides, and `config :brando, Brando.Videos, default_mp4_resolution: 720`
  sets what Automatic plays. `brando_221` adds `videos.quality` in every
  environment; run `mix brando.gen.migrations` and `mix brando.migrate`.
  Existing Bunny videos stream until **Fetch details** in the video library
  looks up their MP4s.

- Saving a video renders the entries whose blocks show it again, so a new
  title, playback setting or quality reaches their stored HTML.
