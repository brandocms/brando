# Test Review: Phase 7 (form-audit) — uncommitted test changes

Scope: `test/support/live_case.ex`, `test/brando_admin/live/form_recovery_test.exs`,
`test/brando/utils_test.exs`, `test/brando/videos/provider_client_test.exs`,
`test/brando/videos/uploaders/req_options_test.exs` (new),
`test/brando/plugs/lockdown_test.exs` (comment only).

## Summary

No BLOCKERs. The harness changes are mechanically correct: `try/after` returns
`:ok` from the body, `flunk` propagates, the `after` cannot mask a failure, and
the selective `receive`s are correctly pinned. Mox and `Req.Test` are both wired
so the new assertions really can fail.

Two findings are about the audit's own standard rather than about green/red
today: one new assertion is falsifiable **only by editing its own fixture**
(the Phase 6 class, in weaker form), and the W-2a RED claim covers one of five
new tests under the mutation the plan names.

## Iron Law check

- ASYNC: all touched files are `async: false`; each one genuinely needs it
  (`Application.put_env`, shared sandbox, `Req.Test`/Mox process ownership). No
  violation, nothing over-marked either.
- MOCK AT BOUNDARIES: `Brando.CDN.Client.Mock` is a `defmock … for:` behaviour
  (`test_helper.exs:265`) over an S3 boundary. Correct.
- NO `Process.sleep`: the new tests use `assert_receive` / `receive … after`.
  (`live_case.ex:211` polls with `Process.sleep(20)` — pre-existing, and it is a
  bounded DOM poll, not a timing guess.)
- VERIFY_ON_EXIT!: present at `utils_test.exs:548`.

## Issues Found

### Critical

None.

### Warnings

- [ ] `form_recovery_test.exs:66` — `assert Process.alive?(proxy)` is the W-3
      replacement, and it cannot go red for any change to the code under test.
      The stub proxy is an unlinked `spawn(fn -> Process.sleep(:infinity) end)`
      (`:328`) and `kill_live/1` kills only `view.pid` — nothing in
      `live_case.ex` can ever make this false. The implementer's RED came from
      mutating the *fixture* (proxy dies at 100ms), not the subject. That is
      weaker than the surrounding assertions but not vacuous in the Phase 6
      sense: the old `refute_received` was false-by-construction, this one at
      least pins the fixture's premise. Either say so in the comment (it
      documents the flunk's precondition, it is not a behavioural assertion), or
      make it behavioural — e.g. a sibling test where the proxy *does* exit and
      `kill_live/1` returns `:ok`, which the `assert_raise` at `:57` then
      contrasts against.
- [ ] `form_recovery_test.exs:83-114` — "killing a real child view stops the
      root's proxy" is not causal on its own now that the control test is
      deleted. Any other death of the root view during the 500ms window produces
      `:proxy_stopped` and the test passes for the wrong reason (the root form
      LiveView runs `start_async(:entry_load, …)` and a deferred
      `send_update_after`, so it is not an inert process). Cheap fix, keeps the
      control's value without keeping the control: assert `child.pid != view.pid`
      and `Process.alive?(view.pid)` immediately before `Process.exit/2`, and
      assert the proxy's `:DOWN` reason is the child's kill reason rather than
      just that a `:DOWN` arrived. Line `:89` asserts only proxy liveness, not
      the root view's.
- [ ] `req_options_test.exs:41-96` — the plan records W-2a as RED-verified by
      flipping `Keyword.merge/2`'s argument order. Only the first test (`:32`)
      goes red under that mutation. `:41` (passthrough) stays green — the
      configured keys collide with nothing built. `:57` and `:63` stay green —
      the configured side is empty either way. `:74` stays green — no configured
      `:headers`. Each of the four *is* falsifiable, but under different
      mutations (drop `|| []` for the nil/unset pair; swap `Keyword.merge` for a
      `Keyword.take` allowlist for the passthrough pair). In a suite whose
      standard is per-assertion RED, record the mutation each test was watched
      go red under, not one mutation for the file.
- [ ] `req_options_test.exs:74-96` — the "documented reachable keys" test does
      not pin the doc's claim. The doc says `:auth` **overwrites** the built
      `authorization` header because Req uses `put_header/3` not
      `put_new_header/3` (`req/steps.ex:236,240,244`), and that `:params` is
      appended and `:plug`/`:adapter` replace the transport. The test asserts
      only that those keys survive `Keyword.merge/2` — which is true of any
      keyword merge and stays true if Req reverses the behaviour the doc cites.
      The falsifiable version is a `Req.Test` round-trip in
      `provider_client_test.exs`: configure `req_options: [auth: {:bearer,
      "hijacked"}]` against Mux and assert the stub sees `Bearer hijacked`, i.e.
      the doc's warning is real. As written this is closer to restating the doc
      than to testing it — the exact failure mode the module's own moduledoc
      (`:6-9`) says it exists to prevent.

### Suggestions

- [ ] `form_recovery_test.exs:96-97` — `proxy_ref` and `child_ref` are never
      demonitored; the second `:DOWN` and the linked `{:EXIT, proxy, _}` are left
      in the mailbox. Harmless at test end (nothing later in this test selects on
      them), but `Process.demonitor(ref, [:flush])` after each wait keeps the
      "any other `{:EXIT, _, _}` stays in the mailbox deliberately" contract that
      `live_case.ex:152-156` states for the harness.
- [ ] `form_recovery_test.exs:102-108` — the 500ms window is described as "the
      same window `await_proxy_exit/1` allows", but the claim under test is
      *that* the proxy stops, not that it stops fast. Under CI load this is the
      most flake-prone line in the file. Widening to 2_000 costs nothing on the
      passing path and does not weaken the assertion.
- [ ] `form_recovery_test.exs:327-333` — `stub_view_with_live_proxy/0` returns a
      bare map that duck-types `%Phoenix.LiveViewTest.View{}`. It matches
      `kill_live/1` today (`view.pid` + a 3-tuple `view.proxy`), so this is
      correct now; the risk is silent — if `kill_live/1` ever gains a
      `%Phoenix.LiveViewTest.View{}` pattern the stub fails as a
      FunctionClauseError rather than as the flunk this test is about. A
      one-line comment naming the two fields it must keep mirroring would do; a
      struct literal would do better.
- [ ] `req_options_test.exs:63-67` — the "unset provider" test calls
      `Application.delete_env/2` with no `on_exit` restore, unlike every other
      test in the file. Safe today (`@provider` is the test module and nothing
      configures it), but it is the one path that does not follow the file's own
      restore discipline.

## Verified, no action

- `live_case.ex:136-149` — `try do … :ok after … end` returns `:ok` (the `after`
  value is discarded), so `form_recovery_test.exs:36`'s `== :ok` still holds.
  `flunk` inside `try` propagates after the `after` runs. `Process.flag/2` on a
  boolean cannot raise, so the `after` cannot mask a failure.
- `live_case.ex:161-167` — the `{:EXIT, ^proxy_pid, _}` selective `receive`
  cannot be confused by the `Process.monitor/1` at `:120`: that ref is consumed
  by the `:DOWN` receive above, and both messages are pinned. A repeated
  `kill_live/1` in one test composes because `prior_trap?` is captured, not
  assumed `false`.
- `utils_test.exs:566-581` — Mox is in private mode with no global
  `stub_with` anywhere in the suite, `build_upload_key/2` runs in the test
  process, so an unexpected `head_object/3` raises `Mox.UnexpectedCallError`
  there and fails the test. "No expectation is the assertion" is sound here.
- `provider_client_test.exs:202-245` — Req 0.7.2 runs `plug:` inline in the
  calling process (`Req.Plug`, no Task/spawn), which is the test process, and no
  uploader `rescue`s. Assertions inside the stub therefore surface as test
  failures, matching the Mux test at `:176-196`. Both new tests also require the
  stub's response to reach `{:ok, _}`, so they cannot pass with the stub
  unrun. `Req.Test` ownership needs no `allow/3` at `async: false`.

## Pre-existing

- `live_case.ex:211` — `Process.sleep(20)` in `do_await_selector/3`; bounded DOM
  poll, deliberate, documented at `:190-194`.
