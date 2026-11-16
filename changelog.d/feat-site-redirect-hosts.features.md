- An environment can have redirect hosts, such as `www.example.com`, which redirect permanently to its domain with the path and query kept, follow the domain when the environment is set live, and are bound once in the installation; a superuser edits them under the domain in Environments. With the served hosts file configured, they go in it as domains do, and the screen shows where each one stands.
  Run `mix brando.gen.migrations` for `brando_229`, then `mix brando.migrate` before the new release starts: with tenancy, a release stops at boot until it has run (see "Running migrations" in the deployment guide).
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.

- `Brando.Tenant.Origins` is a `check_origin` for a multi-site installation's endpoint that accepts the installation's hosts and every site's domain, so a LiveView on a site added in the admin connects; `mix brando.install --tenancy-mode multi` writes it.
  On an existing multi-site installation, replace the production endpoint's `check_origin` list in `config/prod.exs` with `{Brando.Tenant.Origins, :allowed?, []}`, keeping other origins in its argument.

- A response for an environment that is not live carries `X-Robots-Tag: noindex, nofollow`, so a working environment on a public host stays out of search results.
