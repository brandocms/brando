- **A new `mix brando.install` adds the CMS public site.** It composes
  `mix brando.gen.site`, and CMS pages take `/` from phx.new's homepage route
  while `PageController` and its `home.html.heex` are still as `mix phx.new`
  (1.7 or 1.8) wrote them; the controller and templates stay. A homepage the
  application has changed is kept, without the site, with a notice naming
  `mix brando.gen.site --replace-phoenix-home` and `--interactive`, and
  `--interactive` asks instead. `--no-public-site` installs the admin alone,
  and a rerun never adds the site. `mix brando.install` no longer takes
  `--public-site` or `--replace-phoenix-home`.
- **`mix brando.install` pins the toolchain in a `.tool-versions`** (Erlang,
  Elixir, Node.js and pnpm, read by asdf and mise) when the application has
  neither a `.tool-versions` nor a mise configuration, so a plain `mix` or
  `pnpm` there doesn't run whatever the machine defaults to.
