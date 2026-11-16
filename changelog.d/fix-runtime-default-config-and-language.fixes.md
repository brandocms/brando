- A changed `default_config` under `Brando.Images`, `Brando.Videos` or `Brando.Files`, set in `config/runtime.exs` too, now reaches Brando's own assets (the user avatar, the identity logo, the SEO and page images, videos) without recompiling Brando, as it does the application's Blueprints.

- A new user's content language is now the `config :brando, :default_language` configured when the user is created, so a default changed after Brando was compiled, or set in `config/runtime.exs`, applies to new users.
