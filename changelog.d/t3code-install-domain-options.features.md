- **`mix brando.install` takes the deployment hosts and writes the prod
  `check_origin` and Florist's environment files.** `--domain`,
  `--staging-domain` (default `staging.<domain>`) and a repeatable `--origin`
  fill `check_origin` for the endpoint in `config/prod.exs` (the domain, its
  subdomains, the staging host and each origin) and `PHX_HOST` in new
  `.envrc.prod` and `.envrc.staging` files, which get generated secrets and a
  `.gitignore` entry. Without `--domain` the hosts are `<app>.com`
  placeholders; `--interactive` asks for them instead. Invalid hosts or
  origins stop the install. An existing `check_origin` or `.envrc` file is
  never replaced.
