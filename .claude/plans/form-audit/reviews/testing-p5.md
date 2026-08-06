# Testing Review — Phase 5 (form-audit)

## 1. Harness trustworthiness (`live_case.ex`)

**BLOCKER** `test/support/live_case.ex:131-142` (`await_proxy_exit/1`) — the root-vs-child
disambiguation is a race, not a fact. On timeout the function does `Process.alive?(proxy_pid)`
and treats "still alive" as proof this was a *child* view (proxy shared with root, nothing to
drain). But a genuinely broken root-view shutdown — the proxy hangs instead of exiting — produces
the exact same observation: no `{:EXIT, ...}` arrived, and the proxy is still alive. The 500ms
window is a guess (comment claims exits arrive "in single-digit ms" but that's unverified under
CI load/GC pause). Under this design, a real regression in `client_proxy.ex` shutdown is
indistinguishable from a passing child-view test — the harness would print green. Every current
call site (`form_recovery_test.exs`) only kills root views, so the child-view branch is currently
untested dead code that exists purely to launder a timeout into a pass. Recommend: assert on the
call site (pass an explicit `expected: :root | :child` or require the caller to know its
proxy relationship) instead of inferring it from a race between two waits.

**WARNING** `test/support/live_case.ex:131-142` — unrelated `{:EXIT, other_pid, reason}` messages
are never drained; the doc comment ("drains only view.proxy's pid") is accurate about matching but
not about disposal — non-matching EXIT tuples that arrive during the `receive` stay queued in the
test process's mailbox for the rest of the test (harmless today since later `receive`s in this
file pin exact refs/pids, but it's a footgun for any future generic `receive`/`assert_receive`
without a tight pattern in the same test process).

**SUGGESTION** `test/support/live_case.ex:106-107` — "nested-safe" is the wrong word for what's
being described; `kill_live/1` calls in the same test are sequential, not nested (Elixir can't
re-enter a synchronous function on the same process). What's actually true and worth saying:
capture/restore composes correctly across *repeated* calls via last-in-first-out flag handoff.
Comment is misleading, not a bug.

No hang-vs-success ambiguity found in the `{:DOWN, ...}` wait (`live_case.ex:112-116`) — that one
correctly `flunk`s on timeout with no alive-check escape hatch. Only `await_proxy_exit/1` has the
gap.

## 2. Rewritten assertions — can they go RED?

All rewrites checked assert something Brando-specific and can fail:
- `partial_block_save_test.exs:73-82` (`block_errors/1`) — `:no_block_change` vs `[]` distinction
  is real; previously both collapsed to `[]`, which is the exact defect class this guards.
- `asset_orphan_test.exs:77-104` — driven through `Page.changeset/5`'s real `uri: required: true`,
  asserts the *whole* error-key list (`== [:uri]`), not `:uri in`, so a co-incidentally-passing
  weaker assertion is ruled out.
- `direct_finalize_test.exs` — HEAD response is a real Mox expectation at the `Brando.CDN.Client`
  boundary; `Client.ExAws` 404→`:not_found` translation is separately tested against a real
  `ExAws.Request.HttpClient` stub, not just the mock, closing the "mock is the only producer of
  the contract" gap the comment names.

None found that still can't fail among the files reviewed.

## 3. `put_test_env/2` (`test/support/support.ex:29-39`)

Correct for the cases exercised:
- Absent key → `fetch_env` returns `:error` → `on_exit` deletes, not sets `nil`. Fixes the
  documented `Keyword.get(nil, …)` crash.
- Nested/repeated calls to the same key in one test (e.g. multiple `put_test_env` calls, or
  `lockdown_test.exs`'s direct `Application.put_env` between two `put_test_env` calls) unwind
  correctly: each call captures env *at call time*, `on_exit` callbacks run LIFO, so the chain
  restores to the true pre-test value regardless of how many times the key was touched mid-test.
- `on_exit` ordering is standard ExUnit (runs after the test process exits, before the next test
  starts) — no observed hazard.

**Pre-existing/acknowledged, not a new bug**: `lockdown_test.exs:2` is `async: true` while
mutating `:brando, :lockdown` — flagged in the task's own WHY-CONTEXT as deliberate. Confirmed the
mid-test `Application.put_env(:brando, :lockdown, false)` at line 116 bypasses `put_test_env`
tracking but is still correctly unwound because the original `on_exit` closure restores to the
value captured before either mutation, not to a re-read at exit time.

## 4. New test quality

- `direct_finalize_test.exs` — good boundary discipline: only `Brando.CDN.Client` mocked
  (external S3 API), `verify_on_exit!` present, `async: false` because `put_test_env` touches
  `Brando.Files` app env — correct given the pattern.
- `form_recovery_test.exs` — real `live/2` mounts, no over-mocking, negative case present
  (`"a validate with no _target does not kill the form"`, line 181).
- `asset_orphan_test.exs` — deliberately corrects the plan's own premise before writing tests
  against it; control-row pattern (a stale row purged alongside the asserted-surviving one) rules
  out a no-op collector passing trivially. Good practice, no issues.
- No `Process.sleep` found in any changed Elixir test file.

## 5. Playwright changes

- `utils.js:74-80` (`goOffline`) — `conn.close(4000, ...)` reasoning is sound and documented:
  Phoenix only arms the reconnect timer for `closeCode !== 1000`, so 4000 is required, not
  cosmetic. The follow-up `expect(...).toBeHidden({timeout: 15000})` is a real polling assertion,
  deterministic.
- **SUGGESTION** `utils.js:32-46` (`awaitBlockDebounce` / `awaitBlockShip`) — despite the "replaces
  a flat waitForTimeout" framing, these are still fixed `page.waitForTimeout` sleeps (debounce +
  50ms, settle + 50ms), just against named constants instead of magic numbers. That's defensible
  because the underlying app timers (`phx-debounce`, `SHIP_SETTLE_MS`) are themselves fixed
  durations, not variable-latency I/O — but calling this "event-driven" in the header comment
  overstates it. The genuinely event-driven part is correctly isolated to the *receiving* side
  (`block-multiuser-sync.spec.js` uses `expect(...).toHaveValue(...)` retrying assertions
  throughout, e.g. lines 81-84, 164-167, 191-194) — that half is real and non-racy.

## Pre-existing issues outside the diff (one line each)

- `test/brando/html_test.exs:1197-1201` — `grid_debug_tag` test's second statement is a bare
  string literal, asserts nothing.
