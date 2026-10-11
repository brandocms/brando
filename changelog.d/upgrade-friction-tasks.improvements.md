- **`mix brando.doctor` checks the admin routes Blueprints link to.** For
  each of the application's Blueprints with an admin listing or form route,
  the new Admin routes check reports a missing
  `admin_<singular>_form_path` with `:update` (or the `router_scope:`
  variant) as an error, naming the Blueprint and the helper, before a
  listing crashes on it. Blueprints expose the helper they call as
  `__admin_route_helper__/1`.
