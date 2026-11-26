- Release changes: the apply dialog can also drop what blocks hold in the refs and vars the release removes, so they end on the module's version in one step; Revert puts the dropped values back, and says which it could not.
  Run `mix brando.gen.migrations` for `brando_253`, then `mix brando.migrate` and `mix brando.migrate --tenants` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
