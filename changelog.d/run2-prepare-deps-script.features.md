- **`scripts/prepare_055_deps.exs` makes the guide's `mix.exs` edits before
  anything resolves.** Run it with plain `elixir` from the application's root
  (`elixir /path/to/brando/scripts/prepare_055_deps.exs --brando-path PATH`
  or `--brando-ref REF`). It raises the declared Phoenix, LiveView,
  phoenix_html, Ecto, Postgrex, Gettext, Floki, Swoosh and `ex_chimp`
  requirements to the guide's, drops `only: :test` from `floki`, removes
  `timex` when `lib/` no longer calls it (or lists the calls), adds Igniter
  for dev and test, sets Elixir `~> 1.18` and the `Phoenix.CodeReloader`
  listener, and prints each change. It then lists what `mix.lock` still has
  on HTTPoison or hackney 1 and the `mix deps.unlock --all && mix deps.get`
  to run next. `--dry-run` writes nothing.
