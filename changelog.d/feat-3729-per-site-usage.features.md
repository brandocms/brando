- With `tenancy_mode: :multi`, the Sites screen shows superusers each site's storage (media, kept static builds, each environment's database and its archives) and its requests and bytes served per day, with a "Measure now" action.
  Run `mix brando.gen.migrations` for `brando_243`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
  Add `plug Brando.Plug.Usage` first in the endpoint, before `Brando.Plug.SiteAssets`.
  With your own `config :brando, Oban` on a `:multi` installation, add `site_usage: [limit: 1]` to its queues and `{"45 5 * * *", Brando.Worker.SiteUsage, args: %{"all" => true}}` to its crontab.
