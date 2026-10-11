- **`mix brando.gen.blueprint_migration --reconcile` fits a plan to the
  database it will run on.** For snapshots older than their tables, it reads
  the planned tables, columns, indexes and foreign keys from the repo:
  existing storage the plan adds gets `add_if_not_exists`/
  `create_if_not_exists` and stays out of `down/0`; an existing
  `references(...)` column is left out, since PostgreSQL would add its
  constraint again; the `create table` of a table with no snapshot history
  becomes an `alter` adding only what it lacks, or just a baseline snapshot
  when nothing is missing. A change or rename of a column the database lacks
  becomes an add or is left out. Only storage a generated migration in the
  Blueprint's history created is ever dropped, and only when empty; columns
  and tables that hold data or predate those migrations are kept, with a
  comment, and lose a `NOT NULL` the schema would no longer satisfy. Villain
  columns (`data`, `html`, `*_data`) are never dropped. Each migration names
  the database it was read from, and a summary lists what was reconciled per
  file. It works with `--all` and `--dry-run`, not with `--rebaseline`, and
  is refused in an application with named environments. Accepting the plan
  reads the database again and rejects it if what the migration does has
  changed. The "Legacy snapshots" steps in the 0.53 upgrade guide now say
  what it does and what stays manual.
