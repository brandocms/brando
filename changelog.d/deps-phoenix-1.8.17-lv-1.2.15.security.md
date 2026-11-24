- `phoenix` 1.8.17 and `phoenix_live_view` 1.2.15, which fix a channel message that cannot be
  serialized taking down every client on a shared topic, an unsanitized presence key crashing the
  Presence tracker, and a LiveView joined without a `url` skipping its `live_session`'s `on_mount`
  hooks.
  Run `mix deps.update phoenix phoenix_live_view`. If your `assets/package.json` pins `phoenix` or
  `phoenix_live_view`, pin them to `1.8.17` and `1.2.15` and rebuild your backend assets.
