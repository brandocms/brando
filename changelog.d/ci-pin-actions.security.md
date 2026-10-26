- `mix brando.install --domain` no longer trusts every subdomain of the domain in `check_origin`: it lists the domain, its `www.` host, the staging host and each `--origin`, so a page on a subdomain someone else controls cannot open a LiveView socket with an editor's cookies.
  Applications installed before keep their `check_origin`; replace `"//*.example.com"` in `config/prod.exs` with the hosts the application serves (`"//www.example.com"`, `"//staging.example.com"`), or keep the wildcard if every subdomain is yours.

- The generated Dockerfile fetches an exact `sentry-cli` version (`ARG SENTRY_CLI_VERSION`) in the step that holds the Sentry token, instead of the newest 3.x release.
  Applications generated before can pin it the same way: replace `@sentry/cli@3` in the Dockerfile with an exact version.
