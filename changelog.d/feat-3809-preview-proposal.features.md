- A connected AI tool can get a 15-minute public link to a page of its own proposal before the person approves it, with `brando_content_preview_proposal`, to compare it with its design; the link stops working once the proposal is applied, replaced, cancelled or expires.
  Run `mix brando.gen.migrations` for `brando_241`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
