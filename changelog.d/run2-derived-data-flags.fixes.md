- **`mix brando.identifiers.sync --yes` runs instead of crashing.** The task
  took no arguments at all, so the `--yes` the guide's derived-data steps pass
  to `mix brando.entries.resave` stopped it with a `FunctionClauseError`.
  `entries.resave`, `identifiers.sync` and `images.adopt` now all accept
  `--yes` (and `--force`); the two that ask nothing ignore it. An unknown
  option or an extra argument stops any of the three with a line naming it
  and the options the task takes, instead of a stack trace.
