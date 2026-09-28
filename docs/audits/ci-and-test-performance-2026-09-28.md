# CI, E2E and unit-test performance — 28 September 2026

Inspected `main` at `ad7e60221` and the last PR's
[CI run 36405868214](https://github.com/brandocms/brando/actions/runs/36405868214)
for [PR #2875](https://github.com/brandocms/brando/pull/2875). Changes are on
`perf/ci-e2e-startup`. Local measurements use Manhattan, Elixir 1.20.3 / OTP
28.4.1, 24 schedulers, PostgreSQL and Chromium. These are individual runs,
not statistical estimates of CI performance.

## What prevented CI from finishing

Both legacy E2E jobs reached GitHub's 30-minute limit. Authorization finished
in 11m31s. Dependency installation and asset building were small compared with
cold Elixir compilation and repeated failing browser tests.

| Last CI run | Legacy 1 | Legacy 2 |
| --- | ---: | ---: |
| Setup inside `test_e2e.sh`, through Playwright test start | 237.9s | 196.0s |
| Brando's 903-file compilation alone | 62.4s | 50.9s |
| Time in retained failed attempts | 774.0s | 873.9s |
| Of that, repeat attempts after the first failure | 516.7s | 583.5s |
| Result | Job timeout | Job timeout |

Failed-attempt durations come from each retained trace's `test.trace` event
timestamps. They exclude successful tests, worker replacement and setup between
attempts. They are lower bounds on the total cost of failures. The canceled jobs
did not finish their JSON/HTML reports; successful-test durations could not be
recovered from those reports.

Several failures were deterministic test drift after the UI changes:

- `Clients`, `Categories` and `Price categories` now also appear in dashboard
  shortcuts. Unscoped link locators match two elements.
- Block-variable media actions moved into `Add` / `Change` menus. Tests still
  attempted to click closed-menu actions. Two removal tests each consumed
  about 361 seconds across three attempts.
- `META title` became `Meta title`. One drawer test spent about 182 seconds
  retrying the obsolete label.
- Gallery-variable and footnote tests also needed to open their media menus.

Increasing E2E concurrency is **not** part of the implementation. The existing
two isolated CI shards remain, each with `workers: 1`. SQL sandboxes cannot
isolate application-wide PubSub, caches and presence. A four-shard discovery
experiment preserved all 284 test IDs, but it was not an execution benchmark
and was not retained as a workflow change.

## Measured setup and failure scenarios

Setup was measured by running the old and new scripts with the same four-test
file and `--list`. That includes Playwright discovery but starts no browser or
web server. Dependencies were already compiled; each reset rebuilt its database.

| Scenario | Wall time | Outcome |
| --- | ---: | --- |
| Original `--reset` | 11.38s | Passed |
| New `--reset` | 3.43s | Passed |
| New `--check-migrations` | 4.64s | Passed, rollback and forward migration |
| New run against an existing seeded database | 1.57s | Passed |
| Missing `Configure` action, original setup/deadline | 135.58s | Failed after 120s test deadline |
| Same missing action, new setup/action deadline | 25.74s | Failed at the action after 15s |
| Four corrected image/file-variable tests | 15.9s Playwright time | All passed, no retries |

The last row is not a like-for-like benchmark against CI: the machine and scope
differ. It confirms the tests now exercise upload, configure, persistence and
removal instead of spending their budgets waiting for unavailable actions.

The new setup script compiles normally, drops only when requested, migrates,
starts the application and ensures seeds in one BEAM. It removes the first
create/migrate that used to precede a reset, the unconditional force compile,
and five extra Mix invocations. Mix tracks compile-time configuration changes;
forcing the application to recompile on every database reset is unnecessary.
Rollback validation is explicit with `--check-migrations` (which implies reset)
and still runs on CI's first legacy shard.

## Compilation and CI changes

Warm local `mix help` was 0.46–0.49s, root `mix compile` 0.40s, and E2E
`mix compile` 0.78–0.80s. Compiling changes after the pull took 9.38s in the root
and 11.00s in E2E. These are incremental measurements, not cold dependency builds.
There was no evidence here that an already compiled Mix invocation itself is
the primary local bottleneck.

The old E2E jobs had no Elixir build cache: each job compiled all dependencies
and Brando independently. The workflow now has a dedicated E2E compile job.
It saves a successful build before browser execution and seeds the default
branch cache on pushes to `main`. The browser jobs restore that build and still
run normal dependency checks and compilation. A missing cache remains a valid,
slower path.

Main-branch warming matters: GitHub scopes PR-generated caches to that PR.
Adding a cache only inside PR jobs would accelerate subsequent pushes to that
PR but leave the next PR cold. Cache keys include the commit so a newer compiled
application can be saved instead of repeatedly restoring an immutable old
lockfile-only snapshot. See
[GitHub's cache matching and scope rules](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).

The unit-test jobs also stop deleting the application with `mix clean` after
restoring `_build`. They still use `--all-warnings --warnings-as-errors`, which
replays warnings from unchanged compiled files. Source freshness is handled by
Mix's normal compiler. See
[the Elixir compiler options](https://mix.hexdocs.pm/Mix.Tasks.Compile.Elixir.html).
The previous forced CI compilations cost 45–76s per unit-test job in this run.
The actual saving on a new commit depends on which sources it invalidates.

Playwright now has a 15-second ordinary-action deadline and a 30-second
navigation deadline; individual long operations can explicitly override them.
The 25-minute suite deadline leaves time before GitHub's 30-minute deadline
to finish reporters and upload artifacts. Retry counts and trace retention
remain unchanged. A JSONL reporter writes every attempt immediately, preserving
successful-test durations even if a later test or the job is interrupted.

These workflow changes have been validated locally, not run on hosted CI yet.
No end-to-end hosted-CI speedup is claimed from local measurements.

## Targeted verification

All four variable upload/configure/removal tests and the targeted navigation,
listing-filter, price-subform, permalink, image-editor, drawer, footnote,
gallery-variable, draft-media recovery, project creation and multi-select
reordering tests passed with `--retries=0`.
The tests still assert persistence and restored media state; their selectors
now follow the actual menus and sidebar.

Without forced recompilation or database resets between mode changes, all
three site-authorization tests passed in `groups/multi` and again in
`groups/single`; switching back to legacy mode also passed the client test.
The previously flaky preview reconnect case passed in isolation, which is not
proof that its CI race is fixed.

The content-transfer case at `tests/configuration/content-transfer.spec.js:444`
still fails locally at line 459: after installing the missing definition,
`#transfer-apply` stays disabled. This pre-existing failure is recorded rather
than skipped or given extra time. The full E2E suite was not rerun while
troubleshooting individual failures.

The E2E consumer backend asset build passed. Actionlint validated the workflow;
shell syntax, JavaScript syntax, Elixir formatting and diff-whitespace checks
passed. A separate tiny Mix project confirmed that a warning from an unchanged
compiled file still makes `mix compile --all-warnings --warnings-as-errors`
exit with status 1. The new ExUnit formatter was also exercised against a real
test and produced its timing JSON.

## `mix test`: the cost is predominantly serial work

`mix test --seed 883777 --warnings-as-errors` passed all **3,030 checks** in
87.1s of ExUnit time (5.9s async, 81.1s sync), **88.41s wall time**. A second
run with an event-based timing formatter passed in 85.7s (6.0s async, 79.7s sync).
The formatter preserves normal concurrency; `--slowest` enables trace mode and
would change the workload being measured.

Largest serial modules in the second run:

| Module | Seconds |
| --- | ---: |
| `Mix.Brando.Igniter.InstallTest` | 19.67 |
| `BrandoAdmin.PreviewUpdatesTest` | 4.30 |
| `BrandoAdmin.TranslationFormTest` | 3.11 |
| `Brando.Content.ProposalsTest` | 3.07 |
| `Brando.Authorization.SiteContextTest` | 3.06 |
| `Brando.Blueprint.VerifierTest` | 3.01 |
| `BrandoAdmin.Users.GroupsLiveTest` | 2.85 |
| `Mix.Brando.Igniter.UpgradeTest` | 2.77 |
| `Mix.Tasks.Brando.Gen.Test` | 2.24 |
| `Mix.Brando.Igniter.SiteTest` | 2.10 |

The [13 September audit](test-performance-2026-09-13.md) measured 2,376 checks
in 63.4s after its optimization. The suite now has 654 additional checks
(27.5% growth). Installer work is still around twenty seconds, and the group
editor's previous optimization is still effective. Raising `--max-cases` only
affects the small async phase.

Reproduce a normal-concurrency profile:

```sh
MIX_ENV=test elixir -r scripts/test_timings.exs -S mix test \
  --seed 883777 --warnings-as-errors \
  --formatter ExUnit.CLIFormatter --formatter Brando.TestTimingsFormatter
```

Results go to `tmp/test-timings.json`, or `BRANDO_TEST_TIMINGS`. Module durations
sum individual test execution times; concurrent modules' sums are not elapsed
suite time.

## Unit process-partition experiments

These experiments concern **ExUnit**, not Playwright. Each process got its own
source checkout, application build, PostgreSQL database, media and temporary
directory. Dependency beams were shared read-only. Each relocated application
was compiled before benchmarking. Database reset, migration and seeding were
included in the timed runs; preparing and compiling the checkouts was excluded.

| Scenario | Wall time including DB setup | Checks | Outcome |
| --- | ---: | ---: | --- |
| Normal root suite, existing seeded DB | 88.41s | 3,030 | Passed |
| Two isolated processes, 12 schedulers each | 59.89s | 1,629 + 1,401 | All passed |
| Four isolated processes, 6 schedulers each | 47.21s | 696 + 814 + 933 + 587 | All passed |

The four ExUnit partition times were 19.2s, 25.2s, 44.5s and 20.6s. Mix assigns
sorted test files round-robin, not by runtime, leaving the installer-heavy
partition on the critical path. This supports investigating a duration-balanced,
isolated local runner. It does not justify changing async flags on tests that
mutate application configuration or running E2E workers against one server.
See [Mix's OS process partitioning](https://mix.hexdocs.pm/Mix.Tasks.Test.html#module-operating-system-process-partitioning).

The existing root test setup is **not** ready for simply launching four commands
in the same checkout: it clears a shared media directory, uses a common test
database by default and has shared generator scratch paths and failure manifests.
An initial relocated-build experiment also showed why precompilation matters:
an async test invokes `mix xref`; it triggered compilation of relocated beams
while other tests were loading them. That invalid run is excluded from the table.
Warm, isolated reruns passed every check.

The experiments used committed source at `ad7e60221`, separate checkouts under
`/tmp/brando-partition-bench/{1,2,3,4}`, `BRANDO_TEST_DATABASE_URL` per process,
separate `TMPDIR`s, and `MIX_TEST_PARTITION=N mix test --no-compile --partitions
TOTAL --seed 883777 --warnings-as-errors`. This branch does not change default
`mix test` execution or introduce a production partition runner. CI runners
have a different CPU budget; local 24-core results should not be extrapolated
to several processes sharing one CI runner.

## Priorities after this change

1. Measure the next hosted run using the durable per-attempt timings. Continue
   fixing failed or obsolete specs before tuning worker counts or increasing
   deadlines. The earlier run also exposed a live-preview reconnect failure
   and a disabled content-import apply button; neither is explained by Mix startup.
2. For local full-suite speed, make process isolation a supported, tested runner
   and balance file groups by duration. The experiments show a useful ceiling
   without relaxing test coverage, but their separate-checkout setup has a cost.
3. Profile and reduce repeated installer AST/config evaluation and formatting.
   Keep the real install, rerun and conflict tests. This remains the largest
   single serial module, as in the previous audit.
4. Use focused files or `mix test --stale` while editing, then the full suite
   for final verification. Neither changes the authoritative CI coverage.
