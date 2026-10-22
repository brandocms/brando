- `mix brando.install` takes `--domain`, `--staging-domain` and `--origin`, and writes the
  production `check_origin`, Florist's `.envrc.prod` and `.envrc.staging`, and a `rel/env.sh.eex`
  that sources Florist's runtime environment
  ([#3198](https://github.com/brandocms/brando/pull/3198)).
  Build a Florist staging target with `set :mix_env, :prod` and give each target its own database
  user.
