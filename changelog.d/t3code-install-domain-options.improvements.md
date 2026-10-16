- **The unused `config/staging.exs` and nginx installer templates are
  removed.** `mix brando.install` never wrote them; staging runs the prod
  release with its own `.envrc.staging`, and Florist configures the web
  server.
