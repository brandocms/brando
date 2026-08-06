# Phase 7 review — `form-audit`

**Scope:** uncommitted working tree (`git diff` + untracked `test/brando/videos/uploaders/req_options_test.exs`), branch `next`
**Date:** 2026-08-06
**Panel:** elixir-reviewer · iron-law-judge · security-analyzer · testing-reviewer · verification-runner · requirements-verifier
**Prior reviews:** Phases 0–6 in `.claude/plans/form-audit/reviews/`

## Verdict: **REQUIRES CHANGES**

1 BLOCKER, 4 WARNINGs, 6 SUGGESTIONs. Every gate is green and no requirement is
UNMET. The blocker is, once again, **a citation that says something the cited
line does not** — and this time the wrong line was introduced *by the task that
existed to verify it*.

---

## Requirements Coverage

**Source:** Plan file `.claude/plans/form-audit/phase-7-plan.md` (19 tasks, all self-marked `[x]`)

**Summary: 16 MET, 2 PARTIAL, 0 UNMET, 1 UNCLEAR**

| Requirement | Task | Status | Evidence |
|---|---|---|---|
| B1-prove — real child kill stops root proxy | 7A | MET | `form_recovery_test.exs:83-114`; asserts proxy liveness, not elapsed time |
| B1-fix — collapse to `kill_live/1` | 7A | MET | `live_case.ex:117`; role arg, `:child` branch and `:child` test all gone |
| B1-callsites — all five | 7A | MET | `form_recovery_test.exs:36, 48, 187, 210, 234`, each from `live_form/2`; **zero** `kill_live(view, :root\|:child)` across `lib/ test/ e2e/` |
| W-3 — replace the vacuous assertion | 7A | MET (weak) | `form_recovery_test.exs:66`; see WARNING 4 |
| S-1 — `try/after` restores `trap_exit` | 7A | MET | `live_case.ex:128-146`; `flunk` propagates, `:ok` still returned |
| W-4 — delete `restore_trap_exit/0` | 7A | MET | helper, call and comment gone; replaced by a `trap_exit` assertion |
| S-2 — pin `phoenix_live_view 1.2.8` next to both citations | 7A | **PARTIAL** | version pinned at `live_case.ex:96` and `:139`, but **the line numbers it re-verified are wrong** — see BLOCKER |
| S-3 — retire change-narration at four sites | 7A | **PARTIAL** | `lockdown_test.exs` and `mix.exs` clean; `live_case.ex:104-115` and `form_recovery_test.exs:73-82` reintroduce it — see WARNING 3 |
| W-1 — rewrite `ReqOptions.merge/2` `@doc` | 7B | MET | `req_options.ex:15-50`; both positive claims verified exact. Completeness: WARNING 2 |
| W-2a — unit test `ReqOptions.merge/2` | 7B | MET | `req_options_test.exs`, 5 tests |
| W-2b — Bunny + Cloudflare mirrors | 7B | MET | `provider_client_test.exs:200-245`; assertions do surface (Req 0.7.2 runs `plug:` inline, no `rescue` in the uploaders) |
| W-5-investigate | 7C | MET | conclusion holds; plan's "uniquifies unconditionally" wording corrected in scratchpad |
| W-5-frame — say "downstream" in both places | 7C | MET | `utils_test.exs:520-524`, `phase-6-plan.md:196` |
| `overwrite:` short-circuit (user-approved mid-phase) | 7C | MET | `utils.ex:1182-1192`; `utils.ex`, `upload.ex:321`, `uploads.ex:427` now agree |
| W-6 — CHANGELOG names the inversion | 7D | MET | `CHANGELOG.md:5-24`, before/after snippet |
| S-5 — declined shim, reason recorded | 7D | MET | `CHANGELOG.md:26-31` |
| S-4 — document the raise on missing `:cdn` | 7D | MET (over-delivered) | `cdn.ex:407-413`, 8 lines not one — and now stale, see WARNING 1 |
| S-6 — guard the warning site | 7E | MET | `cdn.ex:123-125`; `:97, 107` sit under a head that matched `s3:` from a present `:cdn`, so `nil` cannot reach them |
| S-7 — drop `assets` from `files:` | 7E | MET | no `"assets"` entry; `links:` added; `UPGRADE.md:798-801` carries the dated note |
| Verification table — E2E 107/0 "measured this round" | — | **UNCLEAR** | no artifact of that run anywhere in the tree; all Verification-table numbers are self-reported |

**Scope creep: none.** The two behaviour changes (`build_upload_key/2`'s
`overwrite:` branch, `mix.exs`'s `links:`) were both surfaced and user-approved
mid-phase and are recorded in the plan.

---

## Verification gates — all green

| Gate | Result | Claimed baseline |
|---|---|---|
| `mix compile --warnings-as-errors` | clean, zero output | match |
| `mix format --check-formatted` | clean (whole project) | match |
| `mix credo --strict` | **284** (2 warn / 118 refactor / 152 readability / 12 design) | exact match |
| `mix test` | **1280 tests + 135 doctests, 0 failures**, 13.1s | match |
| Flake check | `form_recovery_test.exs` 3× clean (16 tests, 1.5s, no variance); `req_options_test.exs` + `provider_client_test.exs` 2× clean | — |
| E2E | not run (needs separate server, ~9m) | claimed 107/0, unverifiable from tree |

Two recorded numbers do not reproduce as written (both SUGGESTIONs below):
scratchpad says 1278 tests (actual 1280 — the plan is right, the scratchpad is
stale), and the output baseline "45 lines / 29 non-dot" measures as **43 / 27**.
The substantive Phase 7 claim — **0 lines on stderr** — holds exactly.

---

## BLOCKER

### B1 — three of five `client_proxy.ex` citations are off by one, and S-2 introduced one of them
`test/support/live_case.ex:97-100`
*Flagged independently by `iron-law-judge` and `elixir-reviewer`; verified directly against the vendored dep.*

Read against `deps/phoenix_live_view/lib/phoenix_live_view/test/client_proxy.ex`
at the pinned `1.2.8`:

| Doc claims | Line actually says |
|---|---|
| `:848` — `put_view/3` monitors | `:848` is `new_view = %{view \| module: …}`; `Process.monitor(pid)` is **`:849`** |
| `:856` — `state.pids` map | `:856` is `views: Map.put(state.views, …)` — **the wrong map**; `pids:` is **`:857`** |
| `:908-912` — `fetch_view_by_pid/2` | `:908` is blank; the function is **`:909-913`** |
| `:1001` — children reach `put_view/3` | ✅ exact |
| `:542-545` — `:DOWN` → `{:stop, …}` | ✅ exact |

Every wrong line **exists and reads plausibly**, which is the hardest class to
catch on re-read — and `:856` is worse than an off-by-one: it points at
`state.views` while the sentence is about `state.pids`.

What makes this a blocker rather than a typo: **`phase-7-plan.md:147` records
S-2 as having re-verified these lines and "corrected" `:849` → `:848`.** The
verification task moved a correct citation to a wrong one. That is precisely the
failure B1 was raised about in Phase 6, reproduced inside the fix for it, in a
phase whose stated standard is that a false citation is a defect of the same
class as a code bug.

**Suggested shape:** cite `defp put_view/3` at `:846` (the function head, stable
under insertions) rather than three interior lines, and drop the interior line
numbers entirely — the argument does not need them.

---

## WARNINGs

### W-1 — the new `key_available?/2` `@doc` describes a path this same diff deleted
`lib/brando/cdn/cdn.ex:407-413`
*`iron-law-judge` rated this BLOCKER. Demoted to WARNING here: the reader's operative takeaway is still correct — see below.*

The doc (S-4) says a missing `:cdn` "falls through `get_s3_config/2` … and
**blows up on `Map.from_struct/1`** when that is unset too". S-6, **in the same
uncommitted diff**, added `if !s3_config do raise …` at `cdn.ex:123-125` —
*ahead* of that `Map.from_struct/1` call at `:129`. That path no longer exists;
it now raises a deliberate config error with a message naming what is missing.

The second half (`cdn_config.bucket` at `:429` when `:s3` *is* set) and the
conclusion — "raises before any network call, so callers on a possibly-CDN-less
config must check first" — both still hold, which is why this is not a blocker.
But two tasks in the same phase wrote prose about each other's code without
either reading the other.

**Fix:** replace the `Map.from_struct/1` clause with the config error S-6 added.

### W-2 — "What still reaches past it" reads exhaustive and is not
`lib/brando/videos/uploaders/req_options.ex:29-45`
*HIGH CONFIDENCE — flagged by `elixir-reviewer`, `iron-law-judge` and `security-analyzer` independently, each finding different omissions.*

Both of the doc's positive claims check out exactly against req 0.7.2 (`:auth`
uses `put_header/3` at `steps.ex:236, 240, 244`; `:base_url` is inert on
absolute URLs at `steps.ex:122-125`). The problem is the enumeration, which a
reader will take as closed. Missing, in order of consequence:

* **`:redirect_trusted`** — `remove_credentials_if_untrusted(request, true, _), do: request`
  (`steps.ex:1571`). Setting it disables Req's cross-host credential stripping
  outright. This is the sharpest omission on a doc whose subject is "a config
  seam that can unset credentials".
* **`:form` / `:form_multipart`** — `encode_body/1` tests both **before** `:json`
  (`steps.ex:486, 490` vs `:497`), so a configured `form:` silently replaces the
  body all three providers build.
* **`:json`** — Bunny's GET and DELETE build no body (`bunny.ex:422, 428`), so a
  configured `json:` attaches one to requests that should not have it.
* **`:connect_options` / `:finch`** — proxy and TLS-verification control
  (`verify: :verify_none` on credentialed requests); same reach as the `:plug`
  already listed.
* `:into`, `:retry`, `:redirect`, `:decode_body`, `:receive_timeout`.

Aggravating: `req_options_test.exs:74-96` pins exactly the four keys the doc
lists, which reinforces the closed reading rather than falsifying it.

**Prose fix only** — the allowlist was declined by decision and that is not
reopened here. Suggested wording: "not an allowlist, so *any* configured key the
built options do not name passes through. Among those, the ones that change
request state include: …".

### W-3 — S-3's own ban on change-narration is reintroduced by B1-fix
`test/support/live_case.ex:104-115` · `test/brando_admin/live/form_recovery_test.exs:73-82`
*Flagged by `iron-law-judge` and `requirements-verifier`.*

S-3 retired history-narrating comments at four sites; two of the four were
rewritten by B1-fix, which put narration back:

> "An earlier version took a `:root | :child` role from the caller…"
> "What the Phase 5 review actually caught was…"
> "that is how this citation failed the first time"

This is a plan-internal conflict, not implementer drift — B1-fix explicitly
ordered "restate W1's rationale", S-3 forbids exactly that. Narration won at
both sites. Worth resolving deliberately: either S-3's standard admits a
"why this shape and not the obvious alternative" exception (defensible), or
these two blocks move to the scratchpad. Right now the codebase says both.

### W-4 — three new assertions cannot go red for a change to their subject
*From `testing-reviewer`.*

The harness mechanics are sound — `try do … :ok after …` still returns `:ok`,
`flunk` propagates, `Process.flag/2` on a boolean cannot mask a failure, the
pinned `receive`s cannot be confused by the monitor at `live_case.ex:120`, and
Mox is in private mode with no global `stub_with`, so the two no-`expect`
`overwrite` tests genuinely fail on an unexpected `head_object/3`. These three
are weaker than they look:

* `form_recovery_test.exs:66` — `assert Process.alive?(proxy)` cannot fail for
  *any* change to `kill_live/1`: `kill_live` never touches the proxy, and the
  stub is an unlinked infinite sleeper. Its RED came from mutating the fixture,
  not the subject. Weaker than Phase 6's vacuity (it is a fixture premise, not a
  behavioural claim) but it should be labelled as one or replaced.
* `form_recovery_test.exs:83-114` — the B1-prove test is **not causal now that
  the control was deleted**. Any other death of the root view inside the 500ms
  window yields `:proxy_stopped`. Cheap repair: assert `child.pid != view.pid`
  and `Process.alive?(view.pid)` before the kill, and assert the `:DOWN` reason.
* `req_options_test.exs:41-96` — only the test at `:32` goes red under the
  plan's stated mutation (flipped merge order). The other four need different
  mutations (drop `|| []`; a `Keyword.take` allowlist). The per-test mutation
  should be recorded, since "watched go RED" is this audit's unit of evidence.
  `:74-96` in particular restates `Keyword.merge` rather than pinning the doc's
  actual claim — that `:auth` overwrites the built header — which a `Req.Test`
  round-trip would falsify.

---

## SUGGESTIONs

1. `lib/brando/cdn/cdn.ex:123` — the `!s3_config` guard misses the keyword-list
   config shape; `uploads.ex:385-389` proves that shape occurs, and it would
   still reach `Map.from_struct/1`.
2. `form_recovery_test.exs:96-97` — monitor refs are never demonitored; the
   500ms window at `:102` is the highest flake risk in the diff (stable over 3
   runs locally, but CI is slower).
3. `form_recovery_test.exs:327` — `stub_view_with_live_proxy/0` duck-types
   `%Phoenix.LiveViewTest.View{}`; a struct-shape change in LiveView would pass
   silently.
4. `req_options_test.exs:64` — `delete_env` without restore.
5. `scratchpad.md` — test count recorded as 1278; actual is 1280. Output
   baseline recorded as 45 lines / 29 non-dot; measures as 43 / 27. Restate both
   so Phase 8 inherits reproducible numbers.
6. `ReqOptions.merge/2` has no `@spec`.

---

## PRE-EXISTING (surfaced by this diff, not introduced by it)

* `lib/brando/videos/uploaders/bunny.ex:414` — Bunny's credential is
  `{"AccessKey", api_key}`, but Req's `remove_credentials_if_untrusted/3`
  (`steps.ex:1573-1582`) deletes only the `authorization` header and the `:auth`
  option. A cross-host 302 therefore forwards the Bunny library API key, with
  stock defaults and no config involved. Mux and Cloudflare are unaffected (both
  use `authorization`). Containable with `redirect: false` in Bunny's built opts,
  which config cannot re-enable. Not in this diff — found while verifying W-2.
* The three video uploaders still disagree on missing credentials (Mux and Bunny
  raise; Cloudflare returns `{:error, :not_configured}`, `cloudflare.ex:272-273`).
  Fifth recording.

---

## What this phase got right

Worth stating, because the blocker is narrow and the rest is not: the harness
collapse is correct and now rests on an observation rather than a reading; the
`try/after` is right; the Mox-no-expectation trick ("the test asserts the bucket
is never consulted by declining to stub it") is a genuinely strong RED and
reusable; the `overwrite:` fix brings the third of three upload paths into line
with a documented option; and the `mix hex.build` work found that the package
was **unpublishable** (`Missing metadata fields: links`) — a state no amount of
reasoning about `files:` would have surfaced. Every req 0.7.2 citation in the new
`@doc` is exact.
