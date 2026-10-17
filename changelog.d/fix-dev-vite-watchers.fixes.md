- **`mix phx.server` starts the Vite dev servers in a new application**
  (#3227). `mix brando.install` set `hmr: true` in `config/dev.exs` but left
  phx.new's `watchers: []`, so nothing started Vite: the site rendered a blank
  page and the admin an "Admin assets not reachable" notice, or, with another
  site's Vite on port 3333, loaded that site's admin. The installer now fills
  an endpoint with no watchers with two that run Vite in `assets/backend` and
  `assets/frontend` through the new `Brando.Vite.watch/1`. An endpoint with
  watchers of its own keeps them, and the installer prints the entries to add.
  Existing applications are untouched unless the installer reruns; to add the
  watchers by hand, put these in the endpoint's config in `config/dev.exs`:

  ```elixir
  watchers: [
    vite_admin: {Brando.Vite, :watch, [Path.expand("../assets/backend", __DIR__)]},
    vite_site: {Brando.Vite, :watch, [Path.expand("../assets/frontend", __DIR__)]}
  ]
  ```

  `Brando.Vite.watch/1` stops Vite when Phoenix stops or the VM exits; a plain
  `vite` command watcher outlives `mix phx.server`, since Vite never reads the
  standard input Phoenix closes. When Vite cannot start (a taken port, no
  `node_modules`, no `node`) it logs one error saying what to do and Phoenix
  carries on without it, where a failing command watcher restarts the
  endpoint over and over. Both generated Vite configs set `server.strictPort`,
  so a taken port is an error in the log rather than a quiet move to a port
  Phoenix does not know; copy it into existing configs. Running two sites at
  once takes `BRANDO_VITE_ADMIN_PORT` and `BRANDO_VITE_FRONTEND_PORT`,
  exported where both Phoenix and Vite read them ("Vite dev servers" in
  `guides/generators.md`).

- **The site shows a notice in development when its Vite dev server's
  scripts fail to load** (#3227), as the admin does, instead of a blank page.
  Both notices name the two causes, a dev server that is not running or a
  module it cannot compile, and both ways of running it.

- **A fresh admin build no longer warns that chunks are larger than 500 kB**
  (#3227). The generated admin Vite config sets `build.chunkSizeWarningLimit`
  to 3072 kB: the admin is one bundle loaded once per session, and the
  warning had nothing for an application to act on.
