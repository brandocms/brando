---
name: brando-oban
description: Oban traps in Brando. Use when writing or changing an Oban worker, inserting a job (from a save or inside a transaction), setting `unique` options, snoozing, or looking up a finished job.
user-invocable: true
---

# Oban traps

Each trap below passed its tests here and cost a review round.

## Tenant context

Job rows live in `public` (`Brando.Repo` forces the prefix for `Oban.Job`)
and run in a new process without the request's tenant prefix. Attach the
prefix at insert (`Brando.Tenant.Job.attach/1`) and run under it
(`Brando.Tenant.Job.run/2`). A job that may also run outside any site (email
from the login page) pairs `attach_current/1` with `run_current/2`.

## Uniqueness

- **Name the period.** `unique: [keys: ...]` without `:period` compares only
  with jobs inserted in the last **60 seconds**, so a job scheduled ten
  minutes ago does not block a second one. "One waiting job per user" needs
  `period: :infinity`. (`unique: true` alone is `:infinity`.)
- **Key on the tenant.** Ids repeat across sites: `keys:` includes
  `:tenant_prefix`, or one site's job swallows another's
  (`Brando.Worker.SearchIndexer` is the pattern). Oban matches `keys` by
  jsonb containment, so a job queued outside any site sets
  `"tenant_prefix" => nil` explicitly; without the key it matches every
  site's job (`Brando.Notifications.Digest`, `insert_job/3`).
- **A conflict may have inserted nothing.** When another insert holds Oban's
  advisory lock for the same key, `Oban.insert/1` returns
  `{:ok, %Oban.Job{conflict?: true, id: nil}}`: no row, and no existing job
  to point at. Code acting on the returned job handles `id: nil`
  (`Brando.Notifications.Digest.rest_queued/2`).
- **`:completed` in `states` holds only until the row is pruned** (below).

## Snooze

`{:snooze, seconds}` gives the attempt back (`attempt - 1`), so a job that
keeps snoozing never reaches `max_attempts` and never discards. Give it its
own bound: a deadline from the record's age (`Brando.Worker.VimeoStatus`) or
a cap on `job.meta["snoozed"]`, which Oban increments on each snooze.

## Pruning

The Pruner deletes completed jobs by `scheduled_at`, cancelled by
`cancelled_at` and discarded by `discarded_at`, once older than 300 seconds
(Brando's default, `Brando.Supervisor.oban_config/0`; an application's own
`config :brando, Oban` replaces it, and Oban's default is 60). A job that ran
long after it was scheduled can go at the next run, seconds after it
completed. Later code that looks up a finished job may find nothing: keep the
outcome in your own table.

## Transactions

`Oban.insert/1` inside a `Repo.transaction` joins it: the job commits or
rolls back with it, the unique advisory lock is held until it ends, and a
database error in the insert aborts it. With group authorization every
generated context mutation by a user runs in one
(`Brando.Authorization.Boundary.run/4`); in legacy mode none does, so a job
inserted from a save behaves differently per mode. `Oban.insert/1` cannot run
in a savepoint, so to queue from a save safely, inside a transaction insert the
job changeset with `Repo.insert(changeset, mode: :savepoint, prefix: "public")`
(no Oban uniqueness then; Oban picks the row up after commit), as
`Brando.ContentEvents` `insert/2` does.

## Tests

`config/test.exs` runs Oban with `testing: :inline`: the job runs at insert,
inside the caller's transaction, with no row and no uniqueness; a snooze
comes back on the returned job but never runs again. Test uniqueness and
scheduling under `Oban.Testing.with_testing_mode(:manual, fn -> ... end)`.
The lock conflict never happens in tests (Oban takes the lock only outside
testing modes): test that branch by passing
`%Oban.Job{conflict?: true, id: nil}` to your handler.
