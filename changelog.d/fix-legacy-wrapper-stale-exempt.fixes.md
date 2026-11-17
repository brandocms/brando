- The 0.51 upgrade's Legacy Content Wrapper blocks no longer count as stale for holding a picture, video, HTML, comment or other non-text block in `content`, and **Resolve blocks** no longer offers to drop that content.

- `brando_147` puts the text editor's extensions on the Legacy Content Wrapper's text refs only.

- `mix brando.repair.legacy_media` links a video ref only to a video `brando_133` would link it to (a `default` target), never to a field's video.
