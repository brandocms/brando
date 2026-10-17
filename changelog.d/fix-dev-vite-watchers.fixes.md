- **`mix phx.server` starts the Vite dev servers in a new application**.
  `mix brando.install` set `hmr: true` in `config/dev.exs` but left phx.new's
  `watchers: []`, so nothing started Vite: the site rendered a blank page and
  the admin an "Admin assets not reachable" notice, or, with another site's
  Vite on port 3333, loaded that site's admin. The installer now fills an
  endpoint with no watchers with two that run Vite in `assets/backend` and
  `assets/frontend`, and stop it when Phoenix stops. An endpoint with
  watchers of its own keeps them, and the installer prints the entries to
  add. Existing applications are untouched unless the installer reruns; to
  add the watchers by hand, put these in the endpoint's config in
  `config/dev.exs`, the second with `assets/frontend`:

  ```elixir
  watchers: [
    node: [
      "--import",
      "data:text/javascript,process.stdin.on('end',()=>process.kill(process.pid,'SIGTERM')).resume()",
      "node_modules/vite/bin/vite.js",
      cd: Path.expand("../assets/backend", __DIR__)
    ],
    node: [...]
  ]
  ```

  The `--import` makes Vite stop with Phoenix, which closes the watcher's
  standard input; Vite never reads it, so a plain `vite` watcher outlives
  `mix phx.server`. Both generated Vite configs set `server.strictPort`, so a
  taken port is an error in the log rather than a quiet move to a port Phoenix
  does not know; copy it into existing configs. Running two sites at once
  takes `BRANDO_VITE_ADMIN_PORT` and `BRANDO_VITE_FRONTEND_PORT`, exported
  where both Phoenix and Vite read them ("Vite dev servers" in
  `guides/generators.md`).

- **The site shows a notice in development when its Vite dev server is
  unreachable**, as the admin does, instead of a blank page.

- **A fresh admin build no longer warns that chunks are larger than 500 kB**.
  The generated admin Vite config sets `build.chunkSizeWarningLimit` to
  3072 kB: the admin is one bundle loaded once per session, and the warning
  had nothing for an application to act on.
