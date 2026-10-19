- `mix brando.gen.blueprint_migration --reconcile` fits Blueprint migrations on legacy snapshots to
  the database they will run on, adding only missing storage and dropping only empty storage a
  generated migration created ([#3161](https://github.com/brandocms/brando/pull/3161)).
