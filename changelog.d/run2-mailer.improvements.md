- **`mix brando.migrate55` creates the mailer an application lacks.** Brando
  sends its own email (password resets, form notifications) through the
  application's Swoosh mailer. When the application has none and Brando's
  `:mailer` is unset, the task now writes `MyApp.Mailer`, the local adapter in
  `config/dev.exs` and the test adapter in `config/test.exs`,
  `mailer: MyApp.Mailer` in Brando's config, and a placeholder sender,
  `config :brando, Brando.Mailer, from: {"MyApp", "noreply@example.com"}`, with
  a warning to set the real address and the production adapter in
  `config/runtime.exs`. You no longer run `mix brando.gen.mail` and delete its
  contact form afterwards.

- **`mix brando.gen.mail` scaffolds the contact form only with `--contact`.**
  Without it the task creates or reuses the mailer, its adapters and Brando's
  settings, as `mix brando.migrate55` does. It no longer adds Swoosh or Req to
  `mix.exs`, which come with Brando, so it runs no `mix deps.get` and prints no
  list of dependencies.

- **`mix brando.doctor` names the fix for a missing mailer or sender**: run
  `mix brando.gen.mail`, then set `config :brando, Brando.Mailer, from: …` and
  the mailer's production adapter, instead of pointing at the guides. The Alt
  text check suggests drafting alt text with AI only when an AI provider can
  describe images; otherwise it says to write it on each image marked "No alt
  text" under Images, and links there.
