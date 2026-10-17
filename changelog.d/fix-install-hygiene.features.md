- **A new `mix brando.install` adds the CMS public site.** It composes
  `mix brando.gen.site`, and CMS pages take `/` from phx.new's homepage route
  while `PageController` and its `home.html.heex` are still as `mix phx.new`
  (1.7 or 1.8) wrote them; the controller and templates stay. A homepage the
  application has changed is kept, without the site, with a notice naming
  `mix brando.gen.site --replace-phoenix-home` and `--interactive`, and
  `--interactive` asks instead. A router the site can't be added to (another
  homepage such as a LiveView at `/`, a catch-all, a route whose first segment
  is a parameter, or no `:browser` pipeline) keeps its routes and gets the
  admin alone, with a notice naming the routes and the `mix brando.gen.site`
  command to run once they are resolved. `--no-public-site` installs the admin
  alone, and a rerun never adds the site. `mix brando.install` no longer takes
  `--public-site` or `--replace-phoenix-home`, and `mix brando.gen.site` stops
  on a router without a `:browser` pipeline instead of writing routes that
  don't compile.
- **A new `mix brando.install` pins the toolchain in a `.tool-versions`**
  (Erlang, Elixir, Node.js and pnpm, read by asdf and mise), so a plain `mix`
  or `pnpm` there doesn't run whatever the machine defaults to. It writes the
  file only when the install runs the pinned Erlang and Elixir, so asdf can't
  stop the install's own `mix` tasks, and when neither the application nor a
  folder above it pins a toolchain (`.tool-versions`, mise configuration,
  `.nvmrc`, `.node-version`); otherwise a notice shows the contents to add.
