- **`mix brando.migrate55` lists the next steps in the order your site
  needs.** When the newest Brando migration in `priv/repo/migrations` is
  `brando_102` or older, or a Blueprint's latest snapshot still has a Villain
  field, its closing notice follows the migration guide's "Legacy snapshots"
  order: `mix brando.gen.migrations`, `mix brando.migrate` (Brando's own
  migrations, the blocks conversion among them),
  `mix brando.check.legacy_conversion`,
  `mix brando.gen.blueprint_migration --all --reconcile` against that
  database, review with a rollback and forward, `mix brando.migrate` again,
  then derived data and Gettext. It used to put the Blueprint migrations
  before `mix brando.migrate`, which a legacy site cannot do. Otherwise it
  gives the generic order with `--all`, as the guide does, and both mention
  `mix brando.migrations.check` after `mix brando.gen.migrations`.
