- **`mix brando.install` takes the deployment hosts and writes the prod
  `check_origin`, Florist's environment files and the release script that
  sources them.** `--domain`, `--staging-domain` (default `staging.<domain>`)
  and a repeatable `--origin` set `PHX_HOST` in new `.envrc.prod` and
  `.envrc.staging` files, and with `--domain` fill `check_origin` for the
  endpoint in `config/prod.exs` (the domain, its subdomains, the staging host
  and each origin). The environment files use the names a Phoenix
  `config/runtime.exs` reads, a database user per target (`<app>_prod`,
  `<app>_staging`) and a per-target `RELEASE_NODE` default, and get a
  `.gitignore` entry; their secrets are filled in after the changes are
  accepted, so no diff or `--dry-run` shows them. A new `rel/env.sh.eex`
  sources Florist's `.envrc.runtime` when the release starts. Without
  `--domain` no `check_origin` is written, so Phoenix keeps checking against
  the endpoint's URL host, and the hosts are `<app>.com` placeholders;
  `--interactive` asks for them instead. Invalid hosts, IP addresses and
  wildcards over a top-level domain stop the install. An existing
  `check_origin` (including one in an imported config file), `.envrc` file or
  `rel/env.sh.eex` is never replaced. Build a Florist staging target with
  `set :mix_env, :prod` and give each target its own database user; see the
  deployment guide.
