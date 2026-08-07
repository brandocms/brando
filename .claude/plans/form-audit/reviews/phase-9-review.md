# Phase 9 review — `form-audit`

**Scope:** `git diff HEAD~5..HEAD` on branch `next` (commits `08c371da2`…`0db0eeaab`)
**Date:** 2026-08-07
**Panel:** elixir-reviewer · security-analyzer · testing-reviewer · requirements-verifier · verification-runner
**Prior reviews:** Phases 0–8 in `.claude/plans/form-audit/reviews/`

> **Base note.** `main` is 1199 files behind `next`; diffing against it would
> review the whole branch. Scope is the five unpushed commits, which is exactly
> Phase 9. `iron-law-judge` was not spawned — no Iron Laws section is installed
> in `CLAUDE.md`/`AGENTS.md`, so it had no rubric.

## Verdict: **REQUIRES CHANGES**

1 BLOCKER, 2 WARNINGs, 5 SUGGESTIONs. Every gate is green and matches its
recorded value exactly. Requirements coverage is complete: **0 UNMET.**

The single blocker is, once again, the audit's signature shape — **a safety
claim that holds at one of the three places it needs to hold.** `form.ex:5811`
documents this exact failure mode by name, in a comment written during an
earlier phase. Phase 9 widened the set of providers that trigger it from two to
three, and did not widen the rescue.

Notably, this is the first phase where the *claims* held up under checking. 9C's
"markup only", 9D's corrected C4 premise, and 9A's bookkeeping were each verified
against source and each was true. The blocker is not a false claim — it is a
real cost the decision did not budget for.

---

## Requirements Coverage

**Source:** Plan file `.claude/plans/form-audit/phase-9-plan.md` (tasks 9A–9D)

**Summary: 11 MET, 0 PARTIAL, 0 UNMET, 8 UNCLEAR → 4 of the 8 resolved by the verification gate below; 4 remain E2E-only**

| Requirement | Status | Evidence |
|---|---|---|
| 9A — twelve stale checkboxes reclassified | MET | all twelve in `plan.md` now carry status markers matching their annotations |
| 9A — § G stale citations corrected | MET | `:6257`-past-EOF and the wrong `handle_event` range corrected **in text with measured numbers**, not silently dropped |
| 9B — Cloudflare raises, matching Mux/Bunny | MET | `cloudflare.ex:283-284` vs `mux.ex:545`, `bunny.ex:403` |
| 9B — tests pin the new contract | MET | `provider_client_test.exs:305-340`, 4 tests |
| 9B — CHANGELOG breaking entry | MET | Breaking section present |
| 9C — `Form.VideoDrawer` extracted | MET | `form.ex` 6565→6210, `video_drawer.ex` 390 lines |
| 9C — markup only, no behaviour change | MET | verified independently, see BLOCKER note below for the one real behaviour delta and why it is 9B's, not 9C's |
| 9D — false "no `push_patch` path" claim corrected | MET | `plan.md:65` now cites the counter-evidence (`form.ex:2977`) |
| 9D — C4 pinned by a real test | MET | `block-recovery.spec.js:215` |
| `mix test` 1291 + 135 doctests / 0 failures | MET | **re-measured, exact** |
| `mix credo --strict` 284 (2/118/152/12) | MET | **re-measured, exact** |
| E2E 108 / 0 in 9.0m | UNCLEAR | not run by this review; 107→108 is consistent with 9D adding one spec |

**Scope creep: none.**

---

## BLOCKER 1 — the credential raise reaches two call sites with no rescue

`lib/brando_admin/components/video_picker.ex:463`
`lib/brando_admin/components/form/transformer.ex:909`

`Brando.Videos.Uploader.initiate_upload/3` has exactly three call sites. Only
one is protected:

| Call site | Guarded? |
|---|---|
| `form.ex:5816` via `initiate_provider_upload/5` | **yes** — `rescue` at `:5823` |
| `video_picker.ex:463` | **no** — bare `case` |
| `transformer.ex:909` | **no** — bare `case` |

The comment above the one rescue, at `form.ex:5811-5815`, already states the
consequence in full:

> *"…that exception would take the whole entry form process down along with
> every unsaved change in it (the same class as A2). Found while writing the D3
> regression test, not reported by the audit."*

So the hazard is not newly discovered here — the repo named it, classified it,
and fixed it at the site where it was found. What Phase 9 changed is the
population that triggers it. Before `08c371da2`, a `:cloudflare` site with
missing credentials returned `{:error, :not_configured}` and rendered a toast at
all three sites. After it, a file pick in the video picker or the transformer
kills the parent LiveView and every unsaved change in the open form.

**Why this is a blocker rather than the decision's accepted cost.** The plan
weighed option (a) as "missing credentials are a deploy-time config error, not a
runtime condition" — which is sound for the *contract*. It is not sound for the
*blast radius*, and the blast radius is what `form.ex:5811` had already
documented. Mux and Bunny exposed these two sites before this commit, so two
thirds of the exposure is pre-existing; this commit takes it to three thirds
without touching the rescue. Fixing it now closes all three at once.

**Fix:** hoist the rescue out of `form.ex` into `Brando.Videos.Uploader` and
route all three call sites through it. That is where the "three provider clients
with three failure vocabularies" comment says the seam belongs anyway.

**Not affected:** Cloudflare raises in `api_request/4` *before*
`create_video_record/4`, so there is no orphaned `:uploading` row. Verified.

---

## WARNING 1 — a fixed wait returns to the block specs

`e2e/e2e/playwright/tests/blocks/block-recovery.spec.js:235` — `page.waitForTimeout(750)`.

Commit `aeb0bce45` (`test(e2e): drop the fixed waits from the block specs`)
removed these deliberately. This reintroduces one, and it sleeps immediately
before reading `data-entry-id` — the exact value whose transition the test
exists to observe. Replace with a condition wait on `data-entry-id` becoming
numeric.

## WARNING 2 — a comment that records a commit rather than an invariant

`lib/brando/videos/uploaders/cloudflare.ex:272-282`. The block above the raise
narrates the audit decision (what it used to return, why it changed) and
duplicates the CHANGELOG's breaking-change entry. Comments that describe a
*change* go stale the moment the next change lands; comments that describe an
*invariant* do not. State the contract — "missing credentials are a config
error and raise" — and let the CHANGELOG carry the history.

---

## SUGGESTIONS

1. **`form.ex:5832` pushes `Exception.message/1` to the browser.** It matches
   the plain-string clause of `extract_video_error_message/1` (`:5741`) and is
   rendered verbatim at `:5886`, so the whole credentials heredoc reaches an
   authenticated admin's client. No secret *values* — module and env var names
   only — but the rescue is deliberately broad, so this is a standing channel
   for any future exception message. Return an opaque atom; the stacktrace is
   already logged one line above.
2. **`video_drawer.ex` lacks the `# prop` doc-comment convention** its siblings
   `meta_drawer.ex` and `scheduled_publishing_drawer.ex` use.
3. **`video_drawer.ex` receives an unused `processing` assign** from the call
   site at `form.ex:2069`.
4. **C4 is pinned on one entry's new→persisted transition**, not two
   concurrently distinct entries. Defensible — that is the only real
   `push_patch` path — but the finding is framed as *cross-entry* leakage.
5. **`VideoDrawer` and `Form` now have a mutual compile-time dependency**
   (`VideoDrawer` calls `Form.input/1`; `Form` calls `VideoDrawer.render/1`).
   Worth knowing before Phase 10 does `Chrome` and the drawer pair: the markup
   move does not by itself decouple from the large module.

---

## Verification gates — all confirmed, all exact

| Gate | Recorded | Measured | |
|---|---|---|---|
| `mix test` | 1291 + 135 doctests, 0 failures | identical | CONFIRMED |
| `mix credo --strict` | 284 (2 / 118 / 152 / 12) | identical | CONFIRMED |
| `mix compile --warnings-as-errors` | clean | clean | CONFIRMED |
| `mix format --check-formatted` | clean | clean | CONFIRMED |
| E2E 108 / 0, 9.0m | — | **not run** | unverified here |

Four for four, to the exact issue breakdown. Per `AGENTS.md`, no standalone root
`assets/` build was run — it is not a validation gate for this repo.

---

## What held up under checking

Recorded because the audit's carried lesson is about claims, and this phase's
claims survived:

- **9C "markup only" is true.** No stray callers of the six old `Form.*`
  locations; the `VideoDrawer.render` call site supplies exactly the assigns the
  module reads; all five aliases are used.
- **9D's replacement premise is true.** `form.ex:2977` really does
  `push_patch(to: update_url)` on create + save-and-continue,
  `hooks.ex:46` matches, and `block_field.ex:1478` re-renders `data-entry-id`.
  The new test exercises the path rather than arguing it away, and its
  assertions can fail on regression rather than passing vacuously.
- **9A's bookkeeping actually landed**, including correcting the stale § G
  citations in text rather than deleting them.
- **SEC-1 is not persistent.** `redirect: false` intact at `bunny.ex:440,443,446`,
  `ReqOptions` untouched, the `evil.example.com` assertion still stands.
- **The 9B migration is complete on the matching side** — no
  `{:error, :not_configured}` matchers remain in `lib/`, only comments.
- All three raise messages are **static heredocs with zero interpolation**
  (`cloudflare.ex:284`, `mux.ex:545`, `bunny.ex:403`). Test fixtures are
  obviously fake and `with_config/2` deletes rather than nils on restore.
