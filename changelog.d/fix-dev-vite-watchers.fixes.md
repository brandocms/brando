- `mix phx.server` starts the Vite dev servers in a new application, through endpoint watchers that
  run `Brando.Vite.watch/1` ([#3227](https://github.com/brandocms/brando/pull/3227)).
  In an existing application, add the watchers to the endpoint's config in `config/dev.exs`:
  ```elixir
  watchers: [
    vite_admin: {Brando.Vite, :watch, [Path.expand("../assets/backend", __DIR__)]},
    vite_site: {Brando.Vite, :watch, [Path.expand("../assets/frontend", __DIR__)]}
  ]
  ```
  Copy `server.strictPort` from the generated Vite configs into both existing ones.
  To run two sites at once, export `BRANDO_VITE_ADMIN_PORT` and `BRANDO_VITE_FRONTEND_PORT` where
  both Phoenix and Vite read them ("Vite dev servers" in `guides/generators.md`).

- The site shows a notice in development when its Vite dev server's scripts fail to load
  ([#3227](https://github.com/brandocms/brando/pull/3227)).

- A fresh admin build no longer warns that chunks are larger than 500 kB
  ([#3227](https://github.com/brandocms/brando/pull/3227)).
