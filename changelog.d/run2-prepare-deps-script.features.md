- `scripts/prepare_055_deps.exs` makes the 0.55 upgrade guide's `mix.exs` dependency edits before
  anything resolves, and lists what `mix.lock` still has on HTTPoison or hackney 1
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
  From the application's root, run `elixir /path/to/brando/scripts/prepare_055_deps.exs
  --brando-path PATH` (or `--brando-ref REF`; `--dry-run` writes nothing), then `mix deps.unlock
  --all && mix deps.get`.
