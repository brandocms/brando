# Unit-test performance on Manhattan

Measured on 13 September 2026 with Elixir 1.20.3 / OTP 28.4.1 on Manhattan
(Core Ultra 9 285K, 24 physical cores, 64 GB RAM). Seed: `883777`.

## Baseline

The reported warm `mix test` run took **73.2 seconds**: 4.4 seconds async and
68.7 seconds sync. About 94% of that time is in the serial phase.

A diagnostic run with `--slowest 30 --slowest-modules 20` passed all 2,376
tests and doctests in 76.5 seconds (5.7 async, 70.7 sync). The largest modules
were:

| Module | Seconds |
| --- | ---: |
| `Mix.Brando.Igniter.InstallTest` | 20.90 |
| `BrandoAdmin.Users.GroupsLiveTest` | 14.10 |
| `Brando.Blueprint.VerifierTest` | 3.11 |
| `Mix.Brando.Igniter.UpgradeTest` | 2.67 |
| `Brando.Authorization.SiteContextTest` | 2.51 |
| `Mix.Tasks.Brando.Gen.Test` | 1.98 |
| `Mix.Brando.Igniter.SiteTest` | 1.97 |

These timings include per-test setup. They are individual measurements, not
benchmark averages. The profiling flags enable trace mode, which forces
`max_cases: 1` in Elixir 1.20.3 even if `--max-cases 48` is supplied. Use the
profile to locate expensive modules, then use a normal run for everyday timing.
See the [Mix test documentation](https://mix.hexdocs.pm/Mix.Tasks.Test.html).

## Implemented: reuse group-edit authority during rendering

The permission matrix called `Engine.can?/3` for each checkbox's disabled state,
tooltip, and row selection. Each call reaches `Catalog.get/2`, which discovers
Blueprint modules and checks for conflicting permission keys. A `tprof` run of
the Norwegian editing test counted **5,842,134 calls to `Catalog.blueprint?/1`**.

[GroupsLive](../../lib/brando_admin/live/users/groups_live.ex) now computes the
editable permission keys once per render and once per relevant form event.
Checkboxes and row controls use that set. The set is derived from the current
presentation snapshot, and write operations continue through their existing
authorization checks. There is no global authorization cache.

All 17 group-editor LiveView tests pass. Their combined module time fell from
14.10 seconds in the baseline profile to **2.68 seconds** in a focused profile.
Coverage includes delegated grants, locked resources, hidden search selections,
stale submissions, membership edits, and removal of access from a mounted view.

In the complete post-change profile, the group module took 2.65 seconds and the
suite took **65.0 seconds** (5.8 async, 59.2 sync), with all 2,376 checks passing
under `--warnings-as-errors`. Against the baseline profile, that is 11.5 seconds
saved, or about 15%. Both diagnostic runs used trace mode with one async worker.
The installer remained at 21.35 seconds, consistent with the baseline.

A final normal run, `mix test --seed 883777 --warnings-as-errors`, confirmed
**63.4 seconds** (4.4 async, 58.9 sync), `max_cases: 48`, and **2,376 passing
checks**. That is 9.8 seconds below the user's reported warm run; the paired
diagnostic runs above provide the more controlled comparison. Formatting and
`git diff --check` also passed.

## Remaining opportunities, in priority order

1. **Installer planning and formatting.** Installation alone costs about 21
   seconds; related upgrade and site tests add another 4.6 seconds. A narrow
   `tprof` profile of one successful install observed 502 `Igniter.update_source/5`
   calls and 236 invocations of `Igniter.with_evaled_configs/2`. Config evaluation,
   formatting, and AST updates are measurable costs. Investigate unnecessary
   repeat parsing and configuration evaluation, including upstream Igniter/Rewrite
   improvements. Preserve actual install, rerun, conflict, and composition tests;
   their source-plan checks catch different failures. Skipping formatting would
   change what those tests validate.
2. **Run independent partitions in separate BEAM processes.** This is the larger
   opportunity to use Manhattan's spare cores while retaining serial tests within
   each process. Start by benchmarking four partitions. First provide a separate
   test database and writable media/temp paths per partition. Today
   [test configuration](../../config/test.exs) selects one database, and
   [test_helper](../../test/test_helper.exs) deletes a shared media directory at
   startup. Merely launching several `mix test` processes would not isolate those
   resources. Keep migration-heavy tests and database ownership in this audit.
   Mix documents [OS process partitioning](https://mix.hexdocs.pm/Mix.Tasks.Test.html#module-operating-system-process-partitioning).
3. **Audit individual serial modules for async eligibility.** The primary and
   secondary Blueprint verifier modules account for about 3.9 seconds of serial
   work and generate unique module names. They are candidates for an isolation
   audit, not evidence that all compiler tests can immediately run async. Many
   other serial tests change application configuration, caches, Mix shell, or the
   working directory. LiveView tests use a shared SQL sandbox; its current
   [LiveCase contract](../../test/support/live_case.ex) requires serial execution.
   [Ecto's sandbox documentation](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.Sandbox.html)
   explains the distinction between shared ownership and explicit allowances.

Increasing `--max-cases` cannot accelerate the serial phase. The existing default
of 48 already applies to the async phase. `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=12`
controls dependency compilation, not test execution. The usual password-hashing
optimization is already present: test Bcrypt uses `log_rounds: 1`, and the factory
reuses a precomputed hash.

For the edit/test loop, `mix test path/to/relevant_test.exs` or `mix test --stale`
can shorten feedback while the complete suite remains the final verification.
