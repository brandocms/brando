- **`mix brando.migrate54` updates configuration Phoenix 1.8 and current
  Elixir expect.** An application that depends on Phoenix gets
  `listeners: [Phoenix.CodeReloader]` in `project/0` of `mix.exs` (Phoenix
  1.8's code reloader warns at boot without it), `use Mix.Config` in
  `config/*.exs` becomes `import Config`, and Logger's deprecated `:warn`
  level becomes `:warning` in `config :logger` calls (`level:`, and
  `config :logger, :console, level: …`).
