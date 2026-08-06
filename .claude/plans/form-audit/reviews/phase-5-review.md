# Phase 5 Review — form-audit

**Verdict: PASS WITH WARNINGS**
**Diff base:** `HEAD~6` (5ed8aa885) · 29 files, 894 insertions · **Reviewed:** 2026-08-06
**Panel:** elixir · testing · security · iron-laws · verification · requirements (6 agents, one pass each)

0 blockers. All five gates green. All 15 triage items land. The findings below
are one real harness gap, one pre-existing security fail-open that this phase
made expressible, and a handful of doc-truthfulness items.

---

## Requirements Coverage

**Source:** `.claude/plans/form-audit/phase-5-plan.md`

| | Count |
|---|---|
| MET | 18 |
| PARTIAL | 1 |
| UNMET | **0** |
| UNCLEAR | 2 |

All 15 triage items (W1–W10, S1–S5) map to shipped code, verified at file:line
against the diff rather than against the plan's own `[x]` claims. The three
claims the plan flagged as "the check is the deliverable" were each
independently confirmed:

- **S1** — production really does leave `content_blocks.uid` nullable
  (`brando.install/…brando_103_create_blocks_table.exs:6`; `brando.upgrade/brando_123_blocks_uid_constraint.exs`
  adds only the unique index). Not tightening the fixture was correct.
- **S5** — there is no `IO.inspect`/`dbg`; the old code was a `Logger.error`
  interpolating `inspect(form, pretty: true)`. The plan's correction is accurate.
- **E2E baseline** — re-counted live: `Total: 107 tests in 37 files`. The
  plan's self-correction from 108 to 107 is right.

The 1 PARTIAL (W2-verify) and 2 UNCLEAR (W7b, W7-verify) are all the same
artifact: RED/GREEN mutation evidence is not visible in a diff snapshot. That
evidence *is* recorded in `scratchpad.md` §2–4. **No verdict impact** — this is a
limit of diff-based verification, not a gap in the work.

---

## Findings

### WARNING 1 — `await_proxy_exit/1` can launder a timeout into a pass
`test/support/live_case.ex:131-142` · **HIGH CONFIDENCE** (flagged by testing; I read the code and confirmed the mechanism)

On the 500 ms timeout the function checks `Process.alive?(proxy_pid)` and
returns `:ok` if the proxy is alive, on the reasoning that a *child* view shares
the root's proxy so there is nothing to drain. But a **root** view whose proxy
hangs instead of exiting produces the identical observation: no `{:EXIT, …}`
arrived, proxy still alive. The two cases are indistinguishable, and the
harness prints green for both.

Compounding it: every current call site kills a root view, so the child-view
branch this escape hatch exists to serve is **not exercised by any test today**.

**Severity note.** The testing agent called this a BLOCKER; I am recording it as
a WARNING. It is test-support code, the failure requires an upstream
`client_proxy` shutdown regression, and root-view proxies do exit in single-digit
ms in practice. But it should be fixed, because it is the *same shape* as the
`trap_exit` leak Phase 5A exists to eliminate — an instrument that under-reports.
By this phase's own standard it does not get a pass.

Suggested direction: have the caller state its proxy relationship (root vs
child) rather than inferring it from a race between two waits.

*(The iron-laws agent cleared this function. It checked the dead-proxy branch,
which does correctly `flunk`. Both agents are right about different branches;
the gap is in the alive branch.)*

### WARNING 2 — unrelated `{:EXIT, …}` messages are matched past, never drained
`test/support/live_case.ex:131-142`

The comment says the function "drains only `view.proxy`'s pid" — accurate about
*matching*, not about *disposal*. Non-matching EXIT tuples arriving during the
`receive` stay in the test process mailbox for the rest of the test. Harmless
today because later `receive`s in this file pin exact refs/pids, but it is a
footgun for any future loose `assert_receive` in the same process.

### WARNING 3 — `key_exists?` fails open, and this phase is what makes the fix expressible
`lib/brando/utils.ex:1182` · **PRE-EXISTING** (outside the diff)

`key_exists?` collapses *every* error to "absent". On a bucket that answers
HEAD-on-an-existing-key with 403 rather than 404, the overwrite guard fails
open: a presigned PUT replaces a live asset's bytes under the old row. W1's new
`{:error, :not_found}` contract is precisely the distinction needed to fix this,
which is why it is worth raising now even though the line is untouched.

The Phase 5 change itself is clean here — 403 is deliberately **not** translated,
so a permission failure is not masked as absence, and a test enforces that
pass-through rather than merely claiming it.

### WARNING 4 — the merge fix is triplicated verbatim across three uploaders
`lib/brando/videos/uploaders/{mux.ex:579, bunny.ex:437, cloudflare.ex:283-287}` · structure pre-existing

`req_options/0`, `get_config/2`, and the whole `api_request/3` skeleton are
copy-pasted three ways. Phase 5 had to make the identical edit in all three
copies — which is exactly how one of them drifts out of sync on the next change.
That drift *is* the bug class W3 just fixed, in the same three files.

### SUGGESTION 1 — "nested-safe" is the wrong word
`test/support/live_case.ex:106-107` — `kill_live/1` calls are sequential, not
nested; Elixir cannot re-enter a synchronous function on the same process. What
is true and worth saying: capture/restore composes across *repeated* calls.

### SUGGESTION 2 — the `mix.exs` comment's argument does not survive contact with `priv`
`mix.exs:75-85` justifies the removal as closing "a standing invitation for a
real key". That reasoning applies verbatim to `priv/`, which still ships
credential-shaped placeholders it *must* ship (`brando.install/deployment.cfg:8,13`,
`fabfile.py:968`, `.envrc.prod:3`). Narrow the claim to what it establishes:
these two dirs were shipped and never evaluated.

### SUGGESTION 3 — "event-driven" overstates the sending side
`e2e/…/utils.js:32-46` — `awaitBlockDebounce`/`awaitBlockShip` are still fixed
`waitForTimeout` sleeps against named constants. Defensible (the app timers are
themselves fixed-duration), but the header comment claims more than it delivers.
The *receiving* side in `block-multiuser-sync.spec.js` is genuinely event-driven
(retrying `expect(...).toHaveValue(...)`) — that half is real.

### SUGGESTION 4 — `lockdown_test.exs:2` is `async: true` while mutating global env
Flagged independently by security and testing; already recorded as deliberate in
`scratchpad.md`. Latent today (nothing else reads `:lockdown`), but it will make
a *future* test flaky in a way that looks like a bug in the new test.

---

## Closed during review

**Did a real credential ever ship in `config/test.exs`?** The security agent had
no shell and left this open. Checked across all 84 commits touching the file:
the only non-placeholder-shaped value is a Guardian JWT `secret_key` for issuer
`"BrandoTesting"`, added 2016-11-05 (`3054445f7`) and removed 2018-04-19
(`ebbebc006`). A test-issuer signing key, gone from the tree for eight years.
**Nothing to rotate.**

---

## Verification gates

| Gate | Result | Baseline |
|---|---|---|
| `mix compile --warnings-as-errors` | clean | clean ✅ |
| `mix format --check-formatted` | clean | clean ✅ |
| `mix credo --strict` | **284** | 284 ✅ |
| `mix test` | **1265 tests + 135 doctests, 0 failures** | 1257 + 8 new ✅ |
| Unit-suite stdout | **76 lines** | claimed 89, was 579 ✅ |

E2E not run by the panel (needs a server; the user runs it). The plan records
107/0 on `--reset`.

The stdout measurement came in at 76 lines against the 89 claimed in
`scratchpad.md` — better than stated, not worse. Worth correcting the number in
the scratchpad so the next baseline is one somebody measured.

---

## Confirmed correct (checked, no finding)

- **ExAws 404 translation** matches the real error shape — `ex_aws/lib/ex_aws/request.ex`
  builds every non-2xx as `{:error, {:http_error, status, body}}`. The documented
  403-masking limitation is accurate and complete.
- **`Keyword.merge` reversal** is right in all three uploaders (right-arg-wins,
  so built auth headers now outrank `:req_options`). `:plug`/`:adapter`/timeouts
  stay overridable, so `Req.Test` still works; `:base_url` was always moot.
- **`mix.exs` `files:` drop** is safe — deps compile in `:prod`, so
  `elixirc_paths(:test)` never fires for a consumer, and dependency
  `config/*.exs` has not been evaluated for many major versions.
- **`error_translator.ex:63`** — `Forms.list_fields/1` returns blueprint DSL
  atoms, not entry data. Strictly less leaky than the old whole-struct inspect.
  Old call is gone.
- **The rewritten assertions can all go RED.** `block_errors/1` distinguishes
  `:no_block_change` from `[]`; `asset_orphan_test.exs` drives `Page.changeset/5`
  and asserts the whole error-key list (`== [:uri]`, not `:uri in`); the
  404 translation is tested against a real HTTP-client stub, not only the Mox
  boundary — closing the "the mock was the only producer of the contract" gap.
- **`put_test_env/2`** unwinds correctly across repeated and mid-test-bypassed
  mutations (LIFO `on_exit`, env captured at call time).
- **`flush_exits/0`** has no orphaned callers. `restore_env` sweep is complete —
  `ai_test.exs:107` retains a local helper by design (spans `:brando` *and*
  `:req_llm`; `put_test_env/2` is hardcoded to `:brando`).
- **`goOffline`** — `conn.close(4000, …)` is required, not cosmetic: Phoenix arms
  reconnect only for `closeCode !== 1000`.
- **Iron laws: 0 violations.**

## Pre-existing, outside the diff

- `lib/brando/utils.ex:1182` — `key_exists?` fails open on 403 (WARNING 3 above).
- `lib/brando/cdn/cdn.ex:311,354,362` — `ExAws.request` called directly, bypassing
  the `Client` seam (deliberate, documented).
- `test/brando/html_test.exs:1197-1201` — `grid_debug_tag` test's second statement
  is a bare string literal; asserts nothing.
