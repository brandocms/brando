- **`mix brando.install` no longer writes `fabfile.py` or `deployment.cfg`.**
  New applications deploy with Florist (see the deployment guide), and
  `brando.install.fabfile` was already retired. Existing applications keep
  their files, and `mix brando.migrate55` still converts them to
  `florist.config.exs`.

- **New applications' deployment templates use the application's own
  domain.** `config/prod.exs` and `config/staging.exs` no longer list two
  agency domains in `check_origin`; staging allows `*.<app>.com` and
  `localhost:4000`. The prod and staging `.envrc` files and
  nginx configurations name `dev.<app>.com` and `staging.<app>.com` instead of
  an agency host, and the media sync scripts connect on SSH port 22. Existing
  applications are not changed; check that `check_origin` lists your own hosts.
