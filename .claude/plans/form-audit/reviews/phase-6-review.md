# Phase 6 review — `form-audit`

**Scope:** `git diff HEAD~5` (commits `fe64ff1c3`…`a22f8bda3`), branch `next`
**Date:** 2026-08-06
**Panel:** elixir-reviewer · iron-law-judge · security-analyzer · testing-reviewer · verification-runner · requirements-verifier
**Prior reviews:** Phases 0–5 in `.claude/plans/form-audit/reviews/`

## Verdict: **REQUIRES CHANGES**

1 BLOCKER, 6 WARNINGs, 8 SUGGESTIONs. Every gate is green and every requirement
is met — the blocker is a **false documented invariant** in new harness code,
which is the exact defect class this audit exists to close.

---

## Requirements Coverage

**Source:** Plan file `.claude/plans/form-audit/phase-6-plan.md`

**Summary: 12 MET, 0 PARTIAL, 0 UNMET, 0 UNCLEAR**

| Finding | Task | Status | Evidence |
|---|---|---|---|
| W1 harness launders timeout | 6A W1 | MET | `live_case.ex:105` no default arg, guard `role in [:root, :child]`; `:130` child skips await; `:145-150` flunks at 500ms, `Process.alive?/1` escape hatch gone |
| W1 call sites | 6A | MET | All five pass `:root`; no other caller in `lib/`+`test/` |
| W1 verify | 6A | MET | 2 harness tests; both mutations re-run independently → RED |
| W2 undrained EXITs (comment only) | 6A | MET | `live_case.ex:133-138` states the deliberate non-drain |
| W3 `key_exists?` fails open | 6B | MET | `key_available?/2` at `cdn.ex:381`; `key_exists?` = **0 hits** across `lib test e2e guides priv CHANGELOG.md` |
| W3 verify | 6B | MET | 3 cases `utils_test.exs:524-570`; reverting to `match?({:ok,_},…)` → 2 failures (re-run independently) |
| W4 uploader triplication | 6C | MET | `req_options.ex` new; `mux.ex:573`, `bunny.ex:431`, `cloudflare.ex:282`; private `req_options/0` removed from all three |
| W4 verify | 6C | MET | Flipping `ReqOptions.merge/2` → 1 failure (re-run independently) |
| S1 "nested-safe" | 6A | MET | `live_case.ex:116-117` now says "composes across *repeated* calls" |
| S2 `mix.exs` comment | 6D | MET | `mix.exs:74-85` narrowed; general secrets argument dropped |
| S3 `awaitBlockDebounce` framing | 6D | MET | `e2e/.../utils.js:29` |
| S4 `lockdown_test` async | 6D | MET | `lockdown_test.exs:2` → `async: false` |

**Scope creep:** none material. The only non-task code change is
`lib/brando/cdn/client.ex:29`, retargeting a moduledoc pointer at the function
W4 deleted — required, not creep.

---

## Verification gates — all PASS, zero drift

| Gate | Measured | Baseline | Status |
|---|---|---|---|
| `mix compile --warnings-as-errors` | clean | clean | PASS |
| `mix format --check-formatted` | clean | clean | PASS |
| `mix credo --strict` | **284** | 284 | PASS |
| `mix test` | **1271 + 135 doctests, 0 failures** (13.0s) | 1271/135/0 | PASS |
| Unit-suite stdout | **76 lines** | 76 | PASS |
| E2E `107/0` | not run | — | **UNVERIFIED** (implementer's number, ~9 min, deliberately not re-run) |

Note on the 76-line metric: it is reproducible only on **stdout+stderr combined**
(`mix test > log 2>&1`). Stdout alone is 43 lines. The difference is two
`Map.from_struct/1 with a module is deprecated` stacktraces written to stderr by
Elixir 1.20.0-rc.3, originating at `lib/brando/cdn/cdn.ex:119`
(`get_s3_config/2`, reached via `head_object/2` and `delete_object/2`).
Pre-existing, not Phase 6 drift — but record the channel so the 76 stays
meaningful.

---

## BLOCKER

### B1 — The `:child` branch's documented justification is false, and the branch follows the false claim

**`test/support/live_case.ex:102-103` (doc), `:128` (code), `:140-144` (comment)**

The moduledoc says:

> `:child` — shares the root's proxy, **which stays alive**. Nothing is in
> flight, so nothing is awaited: no race, and no pointless half-second.

The proxy does **not** stay alive. Verified directly in
`deps/phoenix_live_view/lib/phoenix_live_view/test/client_proxy.ex`:

- `put_view/3` (`:846-859`) calls `Process.monitor(pid)` and inserts the pid
  into `state.pids` for **every** view it mounts.
- Child views go through the same `put_view/3` — `:1001`, inside
  `recursive_detect_added_or_removed_children/4`.
- `handle_info({:DOWN, _ref, :process, pid, reason}, state)` (`:542-545`) looks
  the pid up via `fetch_view_by_pid/2` → `Map.fetch(state.pids, pid)` (`:909-913`)
  and, on a hit, returns `{:stop, reason, state}`.

So killing a **child** view's pid stops the root proxy exactly as killing the
root does. The proxy is `GenServer.start_link`ed from the test process
(`:69-71`), so its `:killed` exit propagates to the test.

The failure this creates in `kill_live(view, :child)`:

```elixir
if role == :root, do: await_proxy_exit(proxy_pid)   # :128 — skipped for :child
Process.flag(:trap_exit, prior_trap?)               # :129 — back to false
```

An exit signal **is** in flight. The function skips the await and restores
`trap_exit` to `false`, so the `{:EXIT, proxy, :killed}` either kills the test
process outright or — if it lands inside the trapping window — sits in the
mailbox as an unobserved proxy death, which is the precise condition W2's
comment argues a test must be able to see.

This is not a comment fix. The W1 design decision *("child skips the await
entirely, killing the race and a pointless half-second")* rests on the premise,
so the premise failing means the branch is wrong too. Either both roles await,
or the role distinction collapses — and if it collapses, W1's rationale needs
restating, because the original inference was then not the defect.

**Latency of impact:** latent today. No `:child` call site exists, and the
`:child` regression test at `form_recovery_test.exs:72` uses a **stub** proxy
(`spawn/1`, never dies), so it cannot expose this — it asserts the elapsed time,
which is exactly what the false premise predicts.

**Why it is a blocker anyway:** the deliverable of W1 was a harness that *states
its assumption*. It now states one, at three places, and the assumption is
false — cited to a `client_proxy.ex` line range that says the opposite of what
it is cited for.

---

## WARNINGs

### W-1 — `ReqOptions.merge/2`'s docstring overstates the guard `[HIGH CONFIDENCE]`
**`lib/brando/videos/uploaders/req_options.ex:18-20`**

> Built values win. The other direction lets a `:req_options` entry silently
> replace the authorization header […] a config seam that can unset credentials
> is a config seam that will.

`Keyword.merge/2` only defends the keys the built options **name**. Req reaches
the same header through a different key. Verified in `deps/req/lib/req/steps.ex`:
the `auth` step uses `Req.Request.put_header/3` — not `put_new_header` — at
`:236`, `:240` and `:244`. So `req_options: [auth: {:bearer, "…"}]` survives the
merge untouched and then **overwrites** the Basic header Mux built. Same route
for `:plug`, `:adapter`, `:params`. (`:base_url` is safe — it no-ops on absolute
URLs, `steps.ex:122`.)

Not a privilege boundary: the actor is the config author, who already owns
`runtime.exs`. The defect is the claim, in a phase whose subject is claims that
outrun code. Fix: narrow the doc to "the keys built options name", or
`Keyword.take/2` an allowlist of transport keys.

### W-2 — The precedence rule is pinned at one of three call sites `[HIGH CONFIDENCE]`
**`test/brando/videos/provider_client_test.exs:174-196`**

The new colliding-`headers:` test drives **Mux** only. Re-inlining a flipped
`Keyword.merge` at `bunny.ex:431` or `cloudflare.ex:282` turns nothing RED — the
Bunny and Cloudflare tests install their stub via `plug:`, which is precisely the
order-insensitivity the scratchpad identified and the new Mux test escaped.

The extraction reduces drift risk but does not eliminate it; a future edit to one
provider is exactly the scenario W4 was raised for. A direct unit test of
`ReqOptions.merge/2` is pure and free, and a Bunny mirror costs three lines.

### W-3 — An assertion that cannot fail, in the falsifiability test `[HIGH CONFIDENCE]`
**`test/brando_admin/live/form_recovery_test.exs:65`**

```elixir
refute_received {:EXIT, ^proxy, _}
```

The stub proxy is `spawn/1` — unlinked, unmonitored, and coded never to die — and
`kill_live/2` only ever *receives*. Nothing can put that message in the mailbox,
so the refutation holds vacuously. In a suite whose stated standard is that every
new assertion be watched go RED, this one is incapable of it.
`assert Process.alive?(proxy)` states the invariant actually intended.

### W-4 — `restore_trap_exit/0` runs after the line it protects
**`test/brando_admin/live/form_recovery_test.exs:66`**

It sits *below* line 65, the only line it could shield, and is skipped entirely
if that line raises. ExUnit's per-test process discards the flag on exit anyway,
so the helper provides nothing while its comment claims it compensates for
`kill_live/2` flunking before it restores `trap_exit`. Move it above line 65, or
delete it together with the claim.

Related: fixing `kill_live/2` with `try/after` (SUGGESTIONs below) removes the
need for the helper at all.

### W-5 — `build_upload_key/2` has no caller in this repo `[HIGH CONFIDENCE]`
**`lib/brando/utils.ex:1174`**

Repo-wide grep across `lib/ test/ e2e/ guides/ priv/` returns the definition and
the three new tests — nothing else. The live upload paths call
`Brando.CDN.head_object/2` directly (`lib/brando/uploads.ex:266,292`) with correct
`{:error, :not_found}` handling.

So `key_available?/2` currently has **zero production callers inside Brando**. The
fix is still correct for library surface — downstream apps can call
`build_upload_key/2` — but the plan's "this is a production upload path, so the
standard applies at full strength" and the test comment's framing both describe a
*downstream* caller, not this repo. Worth a deliberate answer: live library
surface, or dead code to remove.

### W-6 — Public function removed with no CHANGELOG entry
**`lib/brando/cdn/cdn.ex` / `CHANGELOG.md`**

`Brando.CDN.key_exists?/2` was a public function on a library consumed by
downstream apps. `CHANGELOG.md` has an active Unreleased section carrying prose
for smaller changes; this removal is absent from it. Low blast radius (no `@doc`,
one internal caller, no `guides/` reference — all re-verified), but consumer-visible.

---

## SUGGESTIONs

**Harness**
- `kill_live/2` leaves `trap_exit` **on** when it flunks (`live_case.ex:125,149`).
  A `try/after` around the body restores it on both paths and deletes the
  `restore_trap_exit/0` workaround entirely.
- `client_proxy.ex:542-545` is cited twice (`live_case.ex:99,141`) with no version
  pin, unlike the `view.ts` mirror elsewhere in this suite. Deps move; pin the
  `phoenix_live_view` version next to the citation. (This blocker is the argument.)
- Change-narration comments — `lockdown_test.exs:2-7`, `live_case.ex:136-144`,
  `mix.exs:82`, `form_recovery_test.exs:52-58` — describe what the code *used to*
  do. Valuable during the audit; they age into noise once the audit closes.

**CDN / uploads**
- `key_available?/2`'s `@doc` is silent on the unguarded no-CDN path (a nil `:cdn`
  raises on `cdn_config.bucket` before any presign or write). Not a regression;
  worth one sentence given the doc enumerates the other outcomes.
- Consider a deprecation shim for `key_exists?/2` rather than outright removal.
- Pre-existing: `Map.from_struct/1` deprecation at `cdn.ex:119` will harden into
  an error on a later Elixir.

**Packaging**
- Pre-existing: `mix.exs` `files:` ships `"assets"` as it exists on disk, and
  `assets/node_modules/` exists locally and is gitignored. Not touched by this
  diff (the hunk is comment-only), but worth a `mix hex.build` check.

---

## Dismissed by the anti-noise filter

- Collapsing `api_request/3` across the three providers — deliberately scoped out,
  and the scoping holds (Basic vs `AccessKey` vs Bearer, two URL shapes, arity 3
  vs 4, two answers to missing credentials).
- `ReqOptions.merge/2` using `|| []` rather than a `Keyword.get/3` default —
  load-bearing, documented, third occurrence in this audit.
- `kill_live/2` having no default arg — deliberate, argued, correct.
- `mix.exs` scaffold placeholders — they are EEx `strong_rand_bytes` calls
  evaluated at install time, i.e. fresh per-project secrets. Better than the
  comment claims, not worse.
- The Mux/Bunny-raise vs Cloudflare-`{:error, :not_configured}` disagreement —
  real, pre-existing, already recorded as out of scope.

---

## What the panel independently re-ran

Not taken on trust:

- Both W3 and W4 mutations re-applied and reverted by requirements-verifier:
  `key_available?/2` → `match?({:ok, _}, …)` produced 2 failures; flipped
  `ReqOptions.merge/2` produced 1. `git diff --stat` clean afterwards.
- `key_exists?` grep across `lib test e2e guides priv CHANGELOG.md` → 0 hits.
- The `client_proxy.ex` monitor/`:stop` chain behind B1, read line by line in
  `deps/`.
- Req's `auth` step using `put_header` (not `put_new_header`) behind W-1.
- `build_upload_key/2`'s caller set behind W-5.
