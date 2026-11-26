- A site has one encryption secret for two-factor secrets, recovery codes, passkey handles, webhook secrets and the other values Brando encrypts, shared by its environments and apart from `secret_key_base`, so a database copied between environments stays readable: `mix brando.install` writes the same `BRANDO_ENCRYPTION_SECRET` to `.envrc.prod`, `.envrc.staging` and an untracked `config/dev.secret.exs`, and `mix brando.doctor` warns while a site has none.
  `mix brando.migrate55` and `mix brando.upgrade` make an existing site read it when set; then, in this order:
  1. Set `BRANDO_ENCRYPTION_SECRET` in `.envrc.prod` and `.envrc.staging` to production's current `SECRET_KEY_BASE`, run `florist prod env:upload` and `florist staging env:upload`, and deploy.
  2. Give production a new `SECRET_KEY_BASE`, upload it and deploy again (everyone is signed out once).
  3. Write the same value to `config/dev.secret.exs`: `config :brando, Brando.Crypto, secret: "…"`.
  Production's data stays readable; users who set two-factor authentication up on a staging or development database set it up again there, or the database is replaced by a copy of production's.
