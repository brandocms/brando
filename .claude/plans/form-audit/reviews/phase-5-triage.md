# Phase 5 Triage — form-audit

**Source review:** `.claude/plans/form-audit/reviews/phase-5-review.md`
**Triaged:** 2026-08-06 · **8 approved, 0 skipped, 0 deferred**

Review verdict was PASS WITH WARNINGS — 0 blockers, 0 Iron Law violations, so
nothing auto-approved. Every item below is an explicit user decision.

---

## Fix Queue

### W1 — `await_proxy_exit/1` launders a timeout into a pass `[testing]`
`test/support/live_case.ex:131-142`

On timeout the function returns `:ok` whenever `Process.alive?(proxy_pid)`, on
the reasoning that a child view shares the root's proxy. A **root** view whose
proxy hangs produces the identical observation, so the two are
indistinguishable and the harness prints green for both. No current test
exercises the child branch the escape hatch exists for.

- [ ] **Decision (user): the caller declares it.** Change to
      `kill_live(view, :root | :child)`; flunk on timeout in **both** cases.
      All current call sites pass `:root`. The inference goes away entirely.

Rejected alternatives, and why they are recorded rather than silently dropped:
*monitor-the-proxy* still needs the child case handled separately when one
first appears; *keep inference + add a child test* leaves the root-hang blind
spot open, which is the actual defect.

Rationale for fixing at all, despite WARNING severity: this is the same shape
as the `trap_exit` leak Phase 5A was written to remove — an instrument that
under-reports. The phase's own standard applies to the phase's own code.

### W2 — unrelated `{:EXIT, …}` messages are matched past, never drained `[testing]`
`test/support/live_case.ex:131-142`

Non-matching EXIT tuples arriving during the `receive` stay in the test process
mailbox for the rest of the test. The comment claims the function "drains only
`view.proxy`'s pid" — true about matching, false about disposal.

- [ ] Either drain non-matching EXITs deliberately, or correct the comment to
      say what it actually does. Same function as W1 — fix together.

### W3 — `key_exists?` fails open on 403 `[security]`
`lib/brando/utils.ex:1182` · **PRE-EXISTING, outside the Phase 5 diff**

Every error collapses to "absent". On a bucket that answers HEAD-on-an-existing-key
with 403 rather than 404, the overwrite guard fails open: a presigned PUT
replaces a live asset's bytes under the old row.

- [ ] **Decision (user): fail closed — only `{:error, :not_found}` means absent.**
      Any other error must not report absence.

**Known consequence, accepted:** this changes production upload behaviour for
every non-404 error. A bucket erroring transiently now blocks an upload that
previously proceeded. That is the intended trade — a blocked upload is
recoverable, an overwritten live asset is not.

W1's new `{:error, :not_found}` contract (Phase 5B) is what makes this
expressible; before it, there was no distinction to branch on.

### W4 — the merge fix is triplicated across three uploaders `[elixir]`
`lib/brando/videos/uploaders/{mux.ex:579, bunny.ex:437, cloudflare.ex:283-287}`

`req_options/0`, `get_config/2` and the whole `api_request/3` skeleton are
copy-pasted three ways. Phase 5's W3 had to make the identical edit in all
three copies — which is how one drifts out of sync on the next change. That
drift is the bug class W3 just fixed, in these same three files.

- [ ] Extract the shared request-building path so the next change cannot land in
      two of three files.

### S1 — "nested-safe" is the wrong word `[docs]`
`test/support/live_case.ex:106-107` — `kill_live/1` calls are sequential, not
nested; Elixir cannot re-enter a synchronous function on the same process.

- [ ] Reword to what is true: capture/restore composes across *repeated* calls.

### S2 — the `mix.exs` comment's argument does not survive contact with `priv` `[docs]`
`mix.exs:75-85` justifies the removal as closing "a standing invitation for a
real key". That applies verbatim to `priv/`, which still ships
credential-shaped placeholders it *must* ship (`brando.install/deployment.cfg:8,13`,
`fabfile.py:968`, `.envrc.prod:3`).

- [ ] Narrow the claim to what it establishes: these two dirs were shipped and
      never evaluated.

### S3 — "event-driven" overstates the sending side `[testing][e2e]`
`e2e/e2e/playwright/utils.js:32-46` — `awaitBlockDebounce`/`awaitBlockShip` are
still fixed `waitForTimeout` sleeps against named constants. Defensible (the app
timers are themselves fixed-duration), but the header comment claims more than
it delivers. The *receiving* side in `block-multiuser-sync.spec.js` genuinely is
event-driven.

- [ ] Correct the header comment; leave the sleeps.

### S4 — `lockdown_test.exs` is `async: true` while mutating global env `[testing]`
`test/brando/plugs/lockdown_test.exs:2` — flagged independently by security and
testing, already recorded as deliberate in `scratchpad.md`. Latent today
(nothing else reads `:lockdown`), but it will make a *future* test flaky in a
way that looks like a bug in the new test.

- [ ] Drop to `async: false`.

---

## Skipped

None.

## Deferred

None.

---

## Also worth carrying forward (not findings)

- **Scratchpad correction, already applied.** Unit-suite stdout measured **76**
  lines, not the 89 recorded. Better than claimed, but neither number had a run
  behind it until this review — the same defect as the 108-vs-107 e2e baseline
  Phase 5 itself corrected.
- **Closed during review, no action.** "Did a real credential ever ship in
  `config/test.exs`?" — across all 84 commits touching the file, the only
  non-placeholder value is a Guardian JWT `secret_key` for issuer
  `BrandoTesting`, added 2016-11-05 (`3054445f7`), removed 2018-04-19
  (`ebbebc006`). Nothing to rotate.
- **Pre-existing, untriaged, still open:** `test/brando/html_test.exs:1197-1201`
  — `grid_debug_tag`'s second statement is a bare string literal that asserts
  nothing. Not raised for decision; recorded so it is not lost.

---

## Verification for the fix pass

Baselines to hold (measured by the review panel, not inherited):

| Gate | Baseline |
|---|---|
| `mix test` | 1265 tests + 135 doctests, 0 failures |
| `mix credo --strict` | 284 |
| `mix compile --warnings-as-errors` | clean |
| `mix format --check-formatted` | clean |
| E2E (`./test_e2e.sh --reset`) | 107 passed / 0 failed |

W3 touches a production upload path and W4 touches three provider clients —
both need their tests watched going RED against the defect, per the standard
this audit has held since Phase 3. W1's fix should be verified the way 5A was:
confirm the rewritten `await_proxy_exit` fails a test that a hung root proxy
would previously have passed.
