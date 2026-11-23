- Fragments have language links: the fragment form lists a fragment's linked versions and the unlinked fragments with its keys in other languages, and `config :brando, Brando.Pages.Fragment, translatable: [mode: :synchronized]` synchronizes them as pages are; `mix brando.fragments.pair` links existing fragments that share their keys.
  Run `mix brando.gen.migrations` for `brando_244`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
  To link existing fragments, run `mix brando.fragments.pair` (with `--site` and `--environment` in a tenant installation), check its list, then run it with `--apply`; there is no release form.
