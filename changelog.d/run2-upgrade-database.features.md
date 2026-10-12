- **`mix brando.upgrade.database` walks the database phase of an upgrade and
  stops at each review point.** Rerun it until it says it is done. Each run
  reads where the application stands (Brando migrations not copied yet,
  migrations not run, Blueprints behind their snapshot, derived data not
  repaired since the last migration), prints it, and runs the next steps of
  the guide's sections 3 and 4 with the existing tasks:
  `brando.gen.migrations`, then a stop to review and commit;
  `brando.migrations.check`, `brando.migrate` and
  `brando.check.legacy_conversion`; `brando.gen.blueprint_migration --all
  --reconcile`, then a stop to review, roll back and forward on a scratch
  copy, and commit; `brando.migrate` again; then `brando.entries.resave`,
  `brando.identifiers.sync`, `brando.images.adopt` (a dry run first),
  `brando.check.image_texts` and a rebuild of the search index. It asks
  before every step that changes the database (`--yes` answers for you; with
  neither a terminal nor `--yes` it stops and changes nothing), and ends with
  every step it ran, skipped and why, or left for the next run. `--dry-run`
  prints the plan only. It refuses to run in an application with named
  environments, where those steps are still done by hand.
