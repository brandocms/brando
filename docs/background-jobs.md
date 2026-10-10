# Background jobs: Oban traps

Read before writing or changing an Oban worker, a job insert or its `unique`
options. Each trap below passed its tests here and cost a review round.

## Tenant context

Job rows live in `public` (`Brando.Repo` forces the prefix for `Oban.Job`)
and run in a new process without the request's tenant prefix. Attach the
prefix when you insert (`Brando.Tenant.Job.attach/1`) and run under it
(`Brando.Tenant.Job.run/2`); its moduledoc covers the variants for jobs
that may run outside a site.

## Uniqueness

- **Name the period.** `unique: [keys: ...]` without `:period` compares only
  with jobs inserted in the last **60 seconds**. "One waiting job per user"
  needs `period: :infinity`; a job scheduled ten minutes ago does not block a
  second one otherwise. (`unique: true` alone is `:infinity`.)
- **Key on the tenant.** Ids repeat across sites, so `keys:` includes
  `:tenant_prefix`, or one site's job swallows another's
  (`Brando.Worker.SearchIndexer` is the pattern).
- **A conflict may have inserted nothing.** When another insert holds Oban's
  advisory lock for the same key, `Oban.insert/1` returns
  `{:ok, %Oban.Job{conflict?: true, id: nil}}`: no row, and no existing job
  to point at. Code that acts on the job it got back handles `id: nil`
  (`Brando.Notifications.Digest.rest_queued/2`).
- **`:completed` in `states` holds only until the row is pruned** (below).

## Snooze

`{:snooze, seconds}` gives the attempt back (`attempt - 1`), so a job that
keeps snoozing never reaches `max_attempts` and never discards. Give it its
own bound: a deadline from the record's age (`Brando.Worker.VimeoStatus`) or
a cap on `job.meta["snoozed"]`, which Oban counts up on each snooze.

## Pruning

Completed, cancelled and discarded rows are deleted after 300 seconds (the
Pruner in Brando's default config, `Brando.Supervisor.oban_config/0`; an
application's own `config :brando, Oban` replaces it, and Oban's default is
60). Later code that looks up a finished job finds nothing: keep the outcome
in your own table.

## Transactions

`Oban.insert/1` inside a `Repo.transaction` uses that transaction: the job
commits or rolls back with it, the unique advisory lock is held until it
commits, and a failed insert aborts it. With group authorization every
generated context mutation runs in one (`Brando.Authorization.Boundary.run/4`);
in legacy mode they do not, so a job inserted from a save behaves differently
per mode. To queue from a save without risking it, see how
`Brando.ContentEvents` inserts in a savepoint.

## Tests

`config/test.exs` runs Oban with `testing: :inline`: the job runs at insert,
inside the caller's transaction, with no row, no uniqueness and no snooze.
Test uniqueness and scheduling under
`Oban.Testing.with_testing_mode(:manual, fn -> ... end)`. The lock conflict
never happens in tests (Oban takes the lock only outside testing modes), so
test its branch by passing `%Oban.Job{conflict?: true, id: nil}` to your
handler.
