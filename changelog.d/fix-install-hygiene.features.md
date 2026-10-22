- A new `mix brando.install` adds the CMS public site when phx.new's homepage is unchanged, and
  `--no-public-site` installs the admin alone
  ([#3231](https://github.com/brandocms/brando/pull/3231)).
  `mix brando.install` no longer takes `--public-site` or `--replace-phoenix-home`; use `mix
  brando.gen.site --replace-phoenix-home` for the latter.

- A new `mix brando.install` pins Erlang, Elixir, Node.js and pnpm in a `.tool-versions`
  ([#3231](https://github.com/brandocms/brando/pull/3231)).
