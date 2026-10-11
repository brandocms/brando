- **`mix brando.gen.blueprint_migration --reconcile` fits a plan to the
  database it will run on.** For snapshots older than their tables, it reads
  the planned tables, columns, indexes and foreign keys from the repo:
  existing storage the plan adds gets `add_if_not_exists`/
  `create_if_not_exists` and stays out of `down/0`; an existing
  `references(...)` column is left out, since PostgreSQL would add its
  constraint again; the `create table` of a table with no snapshot history
  becomes an `alter` adding only what it lacks, or just a baseline snapshot
  when nothing is missing. Columns and tables that hold data are kept, with a
  comment giving the count, and Villain columns (`data`, `html`, `*_data`) are
  never dropped. A summary lists what was reconciled per file. It works with
  `--all` and `--dry-run`, not with `--rebaseline`; accepting the plan reads
  the database again and rejects a plan the database has moved on from. The
  "Legacy snapshots" steps in the 0.53 upgrade guide now say what it does
  and what stays manual.
