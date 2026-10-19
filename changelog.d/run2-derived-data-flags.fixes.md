- `mix brando.entries.resave`, `mix brando.identifiers.sync` and `mix brando.images.adopt` all
  accept `--yes` and `--force`, so `identifiers.sync --yes` runs instead of crashing, and an unknown
  option is named instead of printing a stack trace
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
