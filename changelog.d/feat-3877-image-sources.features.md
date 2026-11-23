- `brando_figma_read_frame` names the media library image each layer shows (`asset`) once `brando_figma_import_images` has imported or reused it, so a tool can match a frame's pictures against the library and an entry's images without importing again; frames imported before are named after their next import.
  Run `mix brando.gen.migrations` for `brando_247`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
