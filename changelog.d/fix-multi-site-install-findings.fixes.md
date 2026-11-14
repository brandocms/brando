- `mix brando.setup` finishes on a `:single` or `:multi` installation: its seeds create only the shared modules in `public`, and a failed seed run leaves nothing behind.

- Blocks the setup seeds create carry their module's version, so `mix brando.doctor` no longer reports them on an outdated module version.

- `mix brando.doctor` counts an incomplete identity's languages apart from its environments, and keeps a long check label apart from its summary.

- `mix brando.gen.mail` applies its changes without asking when there is no terminal, standard input on `/dev/null` included, instead of raising.

- `mix brando.install` adds `/site_assets/` to `.gitignore` with `none` or `single` tenancy, `/sites/` with `single` or `multi`, and each site's `/assets/sites/*/node_modules/` and `/assets/sites/*/dist/` with `multi`; `mix brando.setup.tenancy` adds the lines for the mode it switches to.

- The `error_html.ex` and its test that `mix brando.install` writes over phx.new's are formatted by the application's formatter.

- `mix brando.install` makes phx.new's endpoint port in `config/runtime.exs` apply in development only when `PORT` is set, so a port in `config/dev.exs` holds.
