# Phase 8 review — `form-audit`

**Scope:** `git diff HEAD~5..HEAD` on branch `next` (commits `8e26b9c26`…`d3a47fbf5`)
**Date:** 2026-08-07
**Panel:** elixir-reviewer · security-analyzer · testing-reviewer · requirements-verifier · verification-runner
**Prior reviews:** Phases 0–7 in `.claude/plans/form-audit/reviews/`

> **Resolution (2026-08-07): all 10 findings fixed in the same session.**
> Both blockers, all three warnings and all five suggestions. Each fix was
> measured rather than reasoned about — B2's replacement RED was run in both
> directions, and W3's corrected mutation was run to confirm it reddens on the
> header assertion with the stub still installed. Fixed-tree gates: 1282 tests
> + 135 doctests / 0 failures, credo 284 (exact), compile and format clean,
> output 43 / 27 / 0 (exact), E2E 107 / 0. Details in `scratchpad.md`,
> "Phase 8 review, and the fixes it produced".

## Verdict: **REQUIRES CHANGES**

2 BLOCKERs, 3 WARNINGs, 4 SUGGESTIONs. Every gate is green, every requirement
is delivered, and the security fix this phase shipped is correct and complete.

The blockers are both the same shape, and it is the shape Phase 8 existed to
eliminate: **a claim about evidence that does not hold.** One is a line citation
staled by this diff's own edit; the other is a comment asserting a RED that,
measured, is green.

---

## Requirements Coverage

**Source:** Plan file `.claude/plans/form-audit/phase-8-plan.md` (27 rows: tasks 8A–8G, the four per-task REDs, the traceability table)

**Summary: 25 MET, 1 PARTIAL, 0 UNMET, 1 UNCLEAR → reclassified below**

All 8A–8G tasks landed, including the three the plan explicitly permitted to be
answered as deviations:

| Requirement | Status | Evidence |
|---|---|---|
| 8A B1-fix — five citations → function heads | MET | `live_case.ex`; all five re-verified against vendored LV 1.2.8 (846, 849, 857, 542/545, 909, 983/1001) |
| 8A B1-record — amend `phase-7-plan.md:147` | MET | record kept, original claim quoted |
| 8A B1-guard — pin catches drift, not authorship | MET | folded into W-3a |
| 8B W-1 — drop the `Map.from_struct/1` claim | MET (defective) | `cdn.ex:425-440`; mechanism corrected, conclusion retained — **but see BLOCKER 1** |
| 8B W-2 — reachable keys reframed as open | MET | `req_options.ex:29-63`; leads with the rule, keys are examples |
| 8B W-2-test — `Req.Test` round-trip | MET | assertion is inside the stub and is reached |
| 8C W-3a / W-3b — present tense | MET | both blocks converted |
| 8D W-4a — label or replace | MET (comment overclaims) | `form_recovery_test.exs:61-76`; did both — **see WARNING 1** |
| 8D W-4b — restore causation | **UNMET** | premises landed at `:109-111`, but the reason assertion does not do the work claimed — **see BLOCKER 2** |
| 8D W-4c — per-test mutation comments | MET (one wrong) | five comments; **see WARNING 3** |
| 8E SEC-1 / -test / -note / CHANGELOG | MET | `bunny.ex:440, 443, 446`; verified independently below |
| 8F S-1…S-6 | MET (S-3 PARTIAL) | S-3's coupling is stated at the stub (`:357-364`), not beside the version assertion at `:152` — substance delivered, placement differs |
| 8G E2E — recorded with date | MET | `scratchpad.md`, 2026-08-06, 107/0, 8.8m |

**Per-task RED requirements:** W-2-test, W-4c and SEC-1-test each have a record
outside the plan (`scratchpad.md:1177-1181, 1229-1237, 1243-1248`, the last with
the observed `{:request, "evil.example.com", ["bunny-key"]}`). **W-4b has no
artifact** — and its claimed observation does not reproduce (BLOCKER 2).

**Scope creep: none.**

---

## Verification gates — all green, baseline reproduces exactly

| Gate | Baseline (Phase 7) | Measured | Result |
|---|---|---|---|
| `mix compile --warnings-as-errors` | clean | clean | PASS |
| `mix format --check-formatted` | clean | clean | PASS |
| `mix credo --strict` | 284 | **284** (2 warn / 118 refactor / 152 readability / 12 design) | exact match |
| `mix test` | 1280 + 135 doctests, 0 failures | **1281 + 135, 0 failures** | PASS (+1) |
| Unit-suite output | 43 stdout / 27 non-dot / 0 stderr | **43 / 27 / 0** | exact match |
| E2E | 107 / 0 | run separately this session | see below |

**A note on the noise figure.** The verification runner reported 32 non-dot
lines against a 27 baseline and flagged a possible regression. Re-measured
directly: **27**, matching Phase 7 exactly. The extra five were a counting
difference, not output. The error-path stack trace it identified
(`video_upload_target_test.exs:173`, a deliberately raising provider client) is
inside the 27 and was inside Phase 7's 27 as well.

This is worth recording because it is the third instance in this review alone of
a *re-verification pass producing the error it was checking for* — the pattern
8A was written to name. It applied to the review panel too.

---

## BLOCKERs

### B1 — the W-1 rewrite cites a line inside its own docstring
`lib/brando/cdn/cdn.ex:434`
*From `elixir-reviewer`; verified directly.*

The new prose reads:

> The raise arrives one line later at `cdn_config.bucket` (`:429`), where
> `Map.get(field_cfg, :cdn)` returned `nil` — a `BadMapError`.

`cdn_config.bucket` is at **`:456`**, in `head_object/2`. Line `:429` is a blank
line *inside the `@doc` block that contains the citation*. It cannot be the
site, and it is not adjacent to it. "One line later" is also two lines later
(`:454` → `:456`).

What makes this a blocker rather than a typo is where it landed. Phase 8A's
entire thesis is that interior line numbers are the defect surface, and its fix
was to cite function heads instead. That fix was applied correctly to
`live_case.ex` — all five citations there now verify — and then a *new* interior
line number was written into `cdn.ex` in the same phase.

**Fix:** cite `head_object/2` by name. The argument does not need a line number,
which is the phase's own finding.

**Correct as written, and worth stating because a review agent said otherwise:**
the error name. `BadMapError` is right. `cdn_config` is a variable bound from
`Map.get/3`, so `cdn_config.bucket` on `nil` raises
`** (BadMapError) expected a map, got: nil` — measured, not read. The
`UndefinedFunctionError` reading (`nil.bucket/0`) applies to a literal atom, not
to this code. The doc's two `BadMapError` mentions (`:131` and `:435`) are both
accurate.

### B2 — W-4b's comment claims a RED that is green when run
`test/brando_admin/live/form_recovery_test.exs:124-129`
*From `testing-reviewer`; flagged UNCLEAR independently by `requirements-verifier`; measured directly.*

The comment says:

> The reason is asserted, not matched with `_`: the proxy stops by propagating
> the *child's* exit, so `:killed` is the causal link. A proxy that went down
> for any other reason — the root crashing on its own, a sandbox teardown —
> reports a different reason and reddens this line.

The plan records the matching observation: "RED confirmed: killing the root
yields `{:proxy_stopped, :shutdown}`, which `_` accepted"
(`phase-8-plan.md:195`).

**It does not.** `client_proxy.ex:542-545` propagates the monitored view's exit
reason verbatim (`{:stop, reason, state}`), so a root killed with `:kill` also
produces `:killed`. Ran the mutation — `Process.exit(view.pid, :kill)` in place
of the child, everything else unchanged:

```
1 test, 0 failures (15 excluded)
```

The assertion `outcome == {:proxy_stopped, :killed}` passes when the root is
what died. The reason pin does not distinguish the cause, and the recorded
`:shutdown` does not reproduce.

This is the same class as Phase 7's B1 — a verification step producing a false
record — inside the task whose stated job was *restoring causation to a test
that had lost it*.

Mitigating, and the reason the test is not worthless: the three premises at
`:109-111` (`child.pid != view.pid`, root alive, proxy alive) do real work and
are correct. They are what restores causation. The reason assertion is the part
that claims more than it delivers.

**Fix options, either is fine:**
1. Keep `:killed` and rewrite the comment to say what it actually pins — that
   the proxy stopped by propagation rather than by timeout or teardown — and
   name the premises at `:109-111` as the thing that establishes the child was
   the cause.
2. If a causal reason pin is wanted, kill the child with a distinguishable
   reason (`Process.exit(child.pid, :child_died)` with `trap_exit` on the
   child, or match on the child's monitor firing first) so the root's death
   genuinely produces a different value.

Either way `phase-8-plan.md:195` needs the same correction B1-record applied to
Phase 7 — the record kept, the claim amended.

---

## WARNINGs

### W1 — `req_options.ex:52` cites Bunny lines this diff moved
`lib/brando/videos/uploaders/req_options.ex:52`
*From `elixir-reviewer`; verified.*

> `:json` — Bunny's GET and DELETE build no body (`bunny.ex:422, 428`)

They are now `:440` and `:446`. SEC-1's own 18-line comment (`bunny.ex:419-436`)
pushed them down — the same commit staled the citation. `:422` and `:428` now
land inside that comment.

Third citation defect in a phase about citations, and the one with the shortest
causal chain: two tasks in the same phase, one moving lines the other points at.
**Fix:** name the `case method do` branches, or cite `build_request_opts` by
function rather than by line.

### W2 — W-4a's mutation comment names one mutation that does not redden it
`test/brando_admin/live/form_recovery_test.exs:61-64`
*From `testing-reviewer`.*

> Goes RED if the two waits are ever reordered, or if the flunk moves ahead of
> the kill

The second half is true. The first is not: `kill_live/1` runs
`Process.exit(pid, :kill)` before either wait, so reordering the waits leaves
the view dead by the time the proxy wait flunks, and
`refute Process.alive?(view.pid)` still passes. Only removing or moving the kill
reddens it.

The assertion itself is the right one and W-4a was answered well — this is the
comment overreaching by one clause. Drop the reordering clause.

### W3 — one `req_options_test.exs` mutation comment sends the suite to the network
`test/brando/videos/uploaders/req_options_test.exs:115-117`
*From `testing-reviewer`.*

The named `Keyword.take` allowlist mutation drops `:plug` along with `:auth`, so
the `Req.Test` stub is never installed and the test makes a **real HTTPS request
to `example.com`**. It does go red, but on the status assertion rather than the
header one, so it does not demonstrate what the comment says it demonstrates —
and it makes the suite network-dependent for anyone who runs the mutation.

**Fix:** add `:plug` to the allowlist in the comment's mutation. Then the stub
survives, the request is local, and the RED lands on the header assertion, which
is the claim being pinned.

The other four W-4c comments re-derive correctly, including the plan's own
mid-flight correction (dropping `|| []` reddens *both* nil tests; only the
`get_env` default mutation separates them).

---

## SUGGESTIONs

1. **`cdn.ex:292-299` — S3 credentials reach exception messages.** `PRE-EXISTING`
   (not in this diff). `get_s3_config(config, as: :keyword_list)` returns
   `%S3Config{}` through `Map.from_struct/1 |> Map.to_list/1` (`cdn.ex:145-148`),
   so `access_key_id` and `secret_access_key` are in the keyword list that
   `upload_image/4` interpolates via `inspect(s3_config, pretty: true)` into a
   `raise`. That message reaches Logger, Oban's `errors` column and Sentry.
   `s3_config.ex` is a plain `defstruct` with no `Inspect` derivation. Cheapest
   fix is `@derive {Inspect, except: [:access_key_id, :secret_access_key]}`;
   the raise itself only needs the bucket-shaped fields.
2. **Mux and Cloudflare have no construction-level immunity.** Bunny's
   `redirect: false` cannot be switched off from config; Mux and Cloudflare rely
   on Req stripping `authorization`, which a configured `redirect_trusted: true`
   disables — and `req_options.ex:40-43` now documents that key prominently.
   Consistent with the "the config author owns `runtime.exs`" decision, so this
   is a note rather than a defect: consider saying so where `redirect_trusted`
   is documented.
3. **`req` is pinned `~> 0.5 or ~> 1.0`.** The `@doc` carries eight `steps.ex`
   line citations verified against 0.7.2, with no drift signal — where the
   LiveView citations have `form_recovery_test.exs:152` asserting `1.2.8`. Same
   exposure, one has a tripwire and the other does not.
4. **S-3's placement** — the duck-typing coupling is at the stub definition
   (`form_recovery_test.exs:357-364`) and does cross-reference the version
   assertion, but the task asked for it beside that assertion at `:152`. A
   pointer in the other direction would close it.
5. **`cdn.ex:124-127`** — "Reaching this at all needs `:cdn` present" has an
   unstated subject (`Brando.Images`' `:s3`, not the field config) that reads as
   contradicting `:117` two lines above.

---

## What this phase got right

Stating it because the blockers are narrow and most of this phase is not:

* **The Bunny credential fix is correct, complete, and independently verified.**
  `remove_credentials_if_untrusted/3` (`req/steps.ex:1571-1582`) deletes exactly
  the `authorization` header and the `:auth` option — `AccessKey` survives, so
  the leak was real. `redirect: false` closes it at the source: `redirect?` is
  the first term of the `with` at `steps.ex:1465-1475`, short-circuiting ahead of
  `build_redirect_request/3`, the sole caller of the stripping step. No residual
  path via retry, `:into`, or the `:location_trusted`/`:follow_redirects`
  aliases. It is on all three branches. The precedence argument holds —
  `Keyword.merge(configured || [], built_opts)` puts `built_opts` in the winning
  position, confirmed at the call site. Config cannot re-enable it.
* **The sweep behind it was done properly.** Only four outbound-HTTP call sites
  exist in `lib/`; Mux (`mux.ex:557`) and Cloudflare (`cloudflare.ex:278`) use
  `authorization`, Cloudflare's `upload-metadata` is a base64 filename and
  carries no credential, and no provider puts credentials in a query string —
  which would have survived the fix entirely.
* **Every `req 0.7.2` claim in the rewritten `@doc` is exact**: `:auth` →
  `put_header/3` (`steps.ex:236, 240, 244`), `:form`/`:form_multipart` before
  `:json` (`486, 490` vs `497`), `put_base_url/1` inert on absolute URLs (`123`),
  `redirect_trusted` (`1571`). The `@spec` matches. The reframing from a closed
  enumeration to "the rule first, examples second" is the right shape.
* **All five `live_case.ex` citations now verify** against vendored LV 1.2.8.
  8A's own deliverable is sound; the regression is elsewhere.
* **SEC-1-test is a genuine RED.** Removing `redirect: false` reddens the
  `refute_received` with no timing race, and the observed leak
  (`{:request, "evil.example.com", ["bunny-key"]}`) is recorded in the
  scratchpad rather than asserted in a plan.
* **`await_proxy_exit/1` is sound** — pinned pid, no blanket mailbox drain,
  timeouts can only produce false failures, never false passes.
* **Baselines now reproduce.** S-5's corrections (1280 tests, 43/27/0) measure
  exactly as recorded. That is the first phase in three where the recorded
  numbers survive an independent measurement.

---

## The pattern worth carrying into Phase 9

Phase 8 named it: *re-reading a line to confirm a citation has roughly the same
error rate as writing it the first time.* This review is a fourth data point,
and it extends the claim in a direction the phase did not anticipate — the same
rate applies to **prose about evidence**, not just to line numbers:

* B1 is a line number, and 8A's own remedy (cite function heads) would have
  prevented it. The remedy works; it was not applied to the file 8B touched.
* B2 is not a line number at all. It is a recorded observation that was never
  made, in the task whose subject was an assertion that could not fail.
* W1 was staled by a sibling task in the same commit — the failure mode 8A
  predicted for interior line numbers, realised within one phase.

The generalisation of 8A's fix is not "cite function heads". It is: **a claim
whose only check is a re-read is not checked.** B2 cost one `Process.exit`
target change and a 13-second test run to settle. Three of the four RED claims
in this phase carried an artifact; the one that did not is the one that was
false.
