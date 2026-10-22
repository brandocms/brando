- `mix brando.migrate55` creates a Swoosh mailer, its development and test adapters, and Brando's
  `mailer:` and sender config when the application has none
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
  Then set the real sender in `config :brando, Brando.Mailer, from: …` and the production adapter in
  `config/runtime.exs`.

- `mix brando.gen.mail` scaffolds the contact form only with `--contact`; without it, it sets up the
  mailer as `mix brando.migrate55` does, and it no longer adds Swoosh or Req to `mix.exs`
  ([#3167](https://github.com/brandocms/brando/pull/3167)).

- `mix brando.doctor` names the fix for a missing mailer or sender, warns about an `example.com`
  sender or a production mailer on the local or test adapter, and suggests AI alt text only when a
  provider can describe images ([#3167](https://github.com/brandocms/brando/pull/3167)).
