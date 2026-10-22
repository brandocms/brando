- `mix brando.upgrade.database` runs the database phase of an upgrade with the existing tasks,
  asking before each change and stopping at each review point
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
  Rerun it until it says it is done; `--yes` answers its prompts and `--dry-run` prints the plan.
