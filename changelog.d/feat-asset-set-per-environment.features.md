- In `:multi` and `:single`, an environment can have a frontend asset set of its own, which its host serves and its pages, live and shared previews and static builds render with in place of the site's active set; Frontend assets in the admin activates and clears it, and deploy tooling calls `Brando.Assets.SiteAssets.activate_environment_set/2` and `clear_environment_set/1`.
  Run `mix brando.gen.migrations` for `brando_228`, then `mix ecto.migrate`.

- A host that resolves to an environment answers a path its own sets lack from the own set of another environment of the same site, with `Cache-Control: no-cache`, so a live or shared preview of that environment shown on it loads every file of the set; a path two other environments hold with different content stays unanswered.
