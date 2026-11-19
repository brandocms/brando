- Connected AI tools get the site's guidance: `brando_content_describe_content_type` returns the Assistant guidance for the content type and describes each field from its admin label and instructions (the Assistant reads the descriptions too), and a new "Guidance for building from Figma" under Configuration → Integrations → Connected AI tools comes with `brando_figma_read_frame`.
  Run `mix brando.gen.migrations` for `brando_236`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
