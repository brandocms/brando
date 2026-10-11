- **`mix brando.doctor` checks the admin routes Blueprints link to.** For
  each of the application's Blueprints with an admin listing or form route,
  the new Admin routes check reports a missing
  `admin_<singular>_form_path` with `:update` (or the `router_scope:`
  variant) as an error, naming the Blueprint and the helper, before a
  listing crashes on it. Blueprints expose the helper they call as
  `__admin_route_helper__/1`.

- **`mix brando.migrate54` and `mix brando.migrate55` list the files they
  write when run with `--yes`.** Igniter shows no diff then and listed only
  removed files; a notice now names each file created or updated. The
  closing steps of `mix brando.migrate55` include `mix brando.images.adopt`,
  as the migration guide does.

- **`mix brando.migrate55` adds `Brando.Plug.Markdown` and
  `Brando.Plug.IndexNow` to the endpoint**, before the router (and before
  `Brando.Plug.Health`), as the install template orders them. An endpoint
  that already has one keeps it where it is; the migration guide no longer
  lists them as a manual step.
