# Test Review: Phase 6 (`git diff HEAD~5`)

## Summary

The six new tests are, with one exception, genuinely falsifiable — I can name a
concrete production mutation for five of them and verified the code paths by
reading `live_case.ex`, `utils.ex`, `cdn.ex`, `req_options.ex` and
`support.ex`. No BLOCKERs. The findings are: one coverage gap (the precedence
rule is pinned for Mux only, so Bunny/Cloudflare drift — the exact failure W4
exists to prevent — stays invisible), one tautological assertion, and one
safety helper whose ordering makes it a no-op.

## Iron Law Violations

None. `async: false` is correct in all four touched test files (`LiveCase` uses
a shared sandbox; `utils_test`/`provider_client_test` mutate app env;
`lockdown_test` now says so). Mox is private-mode with `verify_on_exit!`, mocks
sit at the S3 boundary behind a `@behaviour`, no `Process.sleep` in assertions.

---

## 1. Can each new test fail? (mutation per test)

| # | Test | Mutation that turns it RED | Verdict |
|---|---|---|---|
| 1 | `form_recovery_test.exs:58` root-flunks | restore `await_proxy_exit/1`'s `if Process.alive?(proxy_pid), do: :ok` escape → `kill_live` returns `:ok`, `assert_raise` fails | falsifiable |
| 2 | `form_recovery_test.exs:72` child-skips | drop the `if role == :root` guard (`live_case.ex:128`) → either flunks (current await) or burns 500ms (old await), both RED | falsifiable, **two** distinct mutations |
| 3 | `utils_test.exs:543` not_found → as-is | `key_available?` → `match?({:ok, _}, …)` (`cdn.ex:398`) → renamed, RED | falsifiable |
| 4 | `utils_test.exs:551` hit → renamed | `key_available?` → `true` / `!match?(…)` inverted → bare key, RED | falsifiable |
| 5 | `utils_test.exs:559` 403 → renamed | revert to `match?({:ok, _}, head_object(…))` → 403 is not `{:ok, _}` → bare key returned, RED. This is the exact fail-open defect W3 closed. | falsifiable, the strongest of the six |
| 6 | `provider_client_test.exs:175` precedence | flip `Keyword.merge(configured \|\| [], built_opts)` → `Keyword.merge(built_opts, configured \|\| [])` in `req_options.ex:225` → `headers:` replaces wholesale, stub decodes `hijacked:hijacked`, RED | falsifiable **for Mux only** — see W1 |

The exception is not a whole test but a line inside test 1 — see W2.

---

## Issues Found

### Critical

None.

### Warnings

- [ ] **W1 — the precedence rule is pinned in one of the three places it can
      drift.** `test/brando/videos/provider_client_test.exs:174-196`
      W4's stated risk (plan lines 211-236, 338-340) is that *one provider*
      drifts. Reverting `Bunny.api_request/3` (`bunny.ex:431`) or
      `Cloudflare.api_request/4` (`cloudflare.ex:281`) to an inline
      `Keyword.merge(get_config(:req_options) || [], built_opts)` **with the
      arguments flipped** turns nothing RED — the Bunny test at line 127
      installs its stub via `plug:`, which collides with nothing, which is
      precisely the order-insensitivity the new test was written to escape.
      The extraction is therefore verified at its one call site, not as the
      shared rule.
      *Fix (cheapest):* add a direct unit test of the owner —
      `assert ReqOptions.merge(SomeProvider, headers: [built]) == [headers: [built], plug: …]`
      with a colliding configured `headers:` — plus a Bunny mirror of the new
      Mux case (its `AccessKey` header is the same shape of collision). One
      pure-function test costs nothing and fails on any flip of the rule
      itself; the Bunny case is what catches a provider re-inlining it.

- [ ] **W2 — `refute_received {:EXIT, ^proxy, _}` cannot fail.**
      `test/brando_admin/live/form_recovery_test.exs:65`
      The stub proxy is created with `spawn/1` (line 292), so it is neither
      linked to nor monitored by the test process, and it never dies during the
      test. No `{:EXIT, proxy, _}` can exist in that mailbox under *any*
      mutation of `kill_live/2` — the function only receives, never sends. By
      this audit's own watched-go-RED standard the line is decoration.
      *Fix:* delete it, or make it mean something — `assert Process.alive?(proxy)`
      after the rescue states the real invariant (the flunk was a timeout, not
      a death), and *is* falsifiable if the helper ever starts killing the proxy.

- [ ] **W3 — `restore_trap_exit/0` runs after the line it exists to protect.**
      `test/brando_admin/live/form_recovery_test.exs:66` and `299-302`
      The comment says the restore matters "where the flunk is deliberately
      caught". If so, the one line executing under the leaked `trap_exit: true`
      is `refute_received` at line 65 — which runs *before* the restore. And
      because the restore is the last statement, with nothing after it, and is
      skipped entirely if line 65 raises, it protects nothing at all: ExUnit
      gives each test its own process, so the flag dies with the test regardless.
      *Fix:* either move it to immediately after the `assert_raise` block (so
      the remaining assertions really do run un-trapped, which is what the
      comment claims), or drop helper and comment together. The current
      arrangement asserts a safety property it does not provide.

### Suggestions

- [ ] **S1 — `!=` is a weak assertion for the "occupied" case.**
      `test/brando/utils_test.exs:557` — the 403 sibling at line 565 asserts the
      renamed *shape* (`~r|^media/…/logo-[a-z0-9]+\.jpg$|`); this one only
      asserts "not the wanted key", which would also pass if the function
      returned `""`, an error tuple, or a key under the wrong prefix. Use the
      same regex. (`unique_filename/1`, `utils.ex:242-253`, produces exactly it.)

- [ ] **S2 — the stub helper leaks its view pid if `kill_live/2` is not reached.**
      `test/brando_admin/live/form_recovery_test.exs:291-297` — `on_exit` kills
      `proxy` but not `view_pid`; the latter is only cleaned up as a side effect
      of `kill_live/2`'s `Process.exit(pid, :kill)`. Today both tests do call it,
      so nothing leaks — but the helper reads as self-cleaning and is not.
      Kill both in the `on_exit`.

- [ ] **S3 — the 400ms threshold is a magic number detached from the 500ms it
      mirrors.** `test/brando_admin/live/form_recovery_test.exs:77` — it is
      chosen relative to `await_proxy_exit/1`'s hardcoded `500` in
      `live_case.ex:149`. Changing that timeout to 300ms silently makes the
      `:child` test unfalsifiable. Neither number is a module attribute.
      Extracting `@proxy_exit_timeout 500` in `live_case.ex` and asserting
      against it would tie them together. (The margin itself is fine: the real
      `:child` path is sub-millisecond.)

- [ ] **S4 — the two harness tests pay for a DB setup they do not use.**
      They inherit `Brando.LiveCase`'s user insert and the file's page insert,
      and neither touches a conn, a page, or the database. Not wrong — keeping
      them beside the harness they test is defensible and 5A set that precedent
      — just noting the cost.

- [ ] **S5 — a documentation gap the new test exposes but does not state.**
      `lib/brando/videos/uploaders/req_options.ex:219-226` — `Keyword.merge/2`
      *replaces* the `:headers` value rather than merging the lists, so the
      precedence rule means a configured `req_options: [headers: […]]` is
      dropped **entirely**, not just prevented from overriding auth. That is a
      stronger and more surprising claim than "built values win", and the new
      test is exactly the proof of it. Worth one sentence in the `@doc`.

---

## 2. Does the stub view test a fiction?

**No — the stub exercises the real path.** `kill_live/2` (`live_case.ex:105-131`)
reads exactly two things off `view`: `.pid` and the 3-tuple `.proxy`. Everything
after — monitor, `trap_exit` capture, `Process.exit(pid, :kill)`, the `{:DOWN, …}`
receive, the role branch, `await_proxy_exit/1`, the flag restore — is the
production harness code, unmodified, and it is the branch under test.

Two honest caveats, neither a defect:

1. The stub proxy is **not linked** to the test process, whereas `live/2` links
   the real one. That makes the simulation *stricter*, not weaker: no `{:EXIT, …}`
   can arrive by accident, so the timeout branch is reached deterministically.
   It also means the stub can never exercise the *success* branch of
   `await_proxy_exit/1` — but the three real-view tests at lines 31, 44 and 145
   already do.
2. Passing a bare map couples the tests to `kill_live/2`'s current field access.
   If the harness ever pattern-matches `%Phoenix.LiveViewTest.View{}` these two
   tests break loudly (a FunctionClauseError, not a silent pass), which is the
   acceptable failure mode.

## 3. Stray processes / trapped exits / mailbox residue

Clean, with the caveats already filed as W3 and S2:

- **Processes:** `view_pid` is killed inside `kill_live/2` before the flunk (the
  `Process.exit/2` precedes the await), so both tests leave it dead. `proxy` is
  reaped by `on_exit`. Nothing survives the file.
- **trap_exit:** ExUnit runs each test in its own process; a leaked flag cannot
  reach a later test. The only in-test exposure is line 65 (W3).
- **Mailbox:** the `{:DOWN, ref, …}` is consumed by the selective receive; the
  monitor is not demonitored but its target is already dead, so no late `:DOWN`
  can arrive. The stub proxy sends nothing. No residue.

## 4. `lockdown_test.exs` → `async: false`

**Correct, and complete.** The restore is already right: `put_test_env/2`
(`test/support/support.ex:29-39`) captures with `fetch_env/2` and restores via
`delete_env/2` when the key was absent, which is the distinction that matters
here (`Brando.config(:lockdown)` at `lockdown.ex:38`). The raw
`Application.put_env(:brando, :lockdown, false)` at `lockdown_test.exs:122` is
*not* an unrestored mutation — the `put_test_env(:lockdown, true)` at line 106
already registered an `on_exit` that captured the pre-test state, and it runs
after. `:lockdown_password` and `:lockdown_until` go through `put_test_env/2`
in every test that sets them.

So the remaining hole really was concurrency, and `async: false` closes it:
ExUnit runs all async modules first and sync modules serially afterwards, so a
sync module cannot overlap an async one. No further `put_test_env/2` work needed.

## 5. Is the `utils_test.exs` Client mock isolated?

**Yes.** `Brando.CDN.Client.Mock` is defined once at `test_helper.exs:265`
(`Mox.defmock(…, for: Brando.CDN.Client)` — a real behaviour, Iron Law 4) and
wired globally via `config/test.exs:18` `config :brando, :cdn_client,
Brando.CDN.Client.Mock`, read at call time by `Brando.CDN.Client.impl/0`
(`client.ex:65`). That is a *static* config value, not per-test state, so there
is no bleed to restore.

Isolation comes from Mox's default **private mode**: expectations are owned by
the setting process, and `build_upload_key/2` → `key_available?/2` →
`head_object/2` → `impl().head_object/3` all run synchronously in the test
process, so no allowance is needed. `setup :verify_on_exit!` at
`utils_test.exs:541` makes an un-called `expect` a failure. Nothing sets
`set_mox_global/0`. The module is `async: false` anyway (line 2).

One structural note, not a defect: because the mock is the default `impl` for
the whole suite, any test that reaches an enabled-CDN path without an `expect`
fails loudly with a Mox "no expectation" error rather than hitting S3 — which
is the right failure direction.

---

## Pre-existing, outside the diff (one line, as asked)

`Brando.CDN.key_available?/2` is called unconditionally from
`build_upload_key/2` (`utils.ex:1182`), and `head_object/2` does
`Map.get(field_cfg, :cdn).bucket` (`cdn.ex:410-411`) — so a `file_cfg` without
a `:cdn` key raises rather than short-circuiting; pre-existing (`key_exists?/2`
had the same shape) and untouched by Phase 6.
