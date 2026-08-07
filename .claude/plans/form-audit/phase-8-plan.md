# Phase 8 — Close the Phase 7 review findings

**Source:** `.claude/plans/form-audit/reviews/phase-7-review.md` (1 BLOCKER, 4 WARNINGs, 6 SUGGESTIONs)
**Slug:** `form-audit` · **Depth:** standard · **Created:** 2026-08-06

Own file, following the Phase 5–7 precedent — `plan.md`'s Phases 0–4 are
followed by shared `## Verification` / `## Sequencing` / `## Risks` sections, so
appending after those would break it.

No research agents spawned: the review findings are the research, each verified
at `file:line` during the review, and the three highest-severity ones were
re-verified independently against the vendored deps before the review was
written. Two user decisions were taken before planning and are recorded in
**Decisions** below.

---

## What this phase is actually about

Phase 7's blocker is not "three numbers are wrong". It is that **S-2 — the task
whose entire job was re-verifying those numbers — moved a correct citation to a
wrong one**, and recorded the move as a correction (`phase-7-plan.md:147`). The
audit has now produced, in successive phases:

1. a citation that said the opposite of what it was cited for (Phase 6, B1),
2. a plan correction to a finding that was itself 50% wrong (Phase 7, retro §1),
3. a verification pass that introduced the defect it was verifying against.

The pattern is stable enough to name: **re-reading a line to confirm a citation
has roughly the same error rate as writing it the first time.** Phase 8's
structural answer is not "read more carefully" — it is to stop citing interior
line numbers where a function head will do (8A), and to stop writing prose whose
only check is another read (8B).

---

## Decisions taken before planning

**1. The S-3 / B1-fix conflict → rewrite both blocks in present tense.**
Neither standard is amended. S-3's ban stands as written, and B1-fix's argument
survives — it just stops being told as history. "An earlier version took a
`:root | :child` role from the caller" becomes "there is no role argument here,
because the runtime makes no such distinction". This was chosen over deleting
the argument (which loses a real why-not-the-obvious explanation) and over
amending S-3 (which would leave the standard weaker for one hard case).

**2. The Bunny credential-forwarding path → fix it in this phase.**
Pre-existing and outside Phase 7's remit, but it is a live credential leak on
stock defaults, and the fix is one keyword in `built_opts` — which, because
`ReqOptions.merge/2` is `Keyword.merge(configured || [], built_opts)`
(`req_options.ex:58-64`), config cannot re-enable. Chosen over deferring (a
sixth recording) and over prove-first: unlike B1, the mechanism here is not a
reading of behaviour that might be wrong — it is `remove_credentials_if_untrusted/3`
(`req/steps.ex:1573-1582`) deleting exactly two things, neither of which is
`AccessKey`. There is nothing to observe that the source does not already settle.

---

## Phase 8A — The blocker, and the habit behind it `[elixir]`

Sequenced first: 8C rewrites the same `@doc` block, and doing that before the
citations are settled means touching it twice.

- [x] **B1-fix — cite function heads, not interior lines** — all five verified against vendored 1.2.8; plan's table exactly right. Now `put_view/3` (`:846`), the `handle_info({:DOWN, …}, state)` clause (`:542`), `fetch_view_by_pid/2` (`:909`), and `recursive_detect_added_or_removed_children/4` by name. `await_proxy_exit/1`'s comment converted too.
      `test/support/live_case.ex:97-100`. Three of five citations are wrong
      against the vendored `phoenix_live_view 1.2.8`:

      | Doc says | Actually |
      |---|---|
      | `:848` — `put_view/3` monitors | `:848` builds the struct; `Process.monitor(pid)` is `:849` |
      | `:856` — `state.pids` | `:856` writes `state.views` — **the wrong map**; `pids:` is `:857` |
      | `:908-912` — `fetch_view_by_pid/2` | `:908` is blank; the function is `:909-913` |
      | `:1001` — children reach `put_view/3` | correct |
      | `:542-545` — `:DOWN` → `{:stop, …}` | correct |

      Replace all five with **function heads**, which do not move when a line is
      inserted inside a function: `put_view/3` (`:846`), the
      `handle_info({:DOWN, …}, state)` clause (`:542`), `fetch_view_by_pid/2`
      (`:909`). Keep `:1001` only if the "children go through the same function"
      point needs a call site; prefer naming
      `recursive_detect_added_or_removed_children/4` instead.
      The argument does not need interior line numbers, and every one it has
      used has been wrong at least once.

- [x] **B1-record — correct the plan that recorded the wrong correction** — `phase-7-plan.md:147` amended; the record is kept and the original claim quoted, measured line by line.
      `.claude/plans/form-audit/phase-7-plan.md:147` records S-2 as having
      re-verified the citations and corrected `:849` → `:848`. That is backwards.
      Amend the line to say what happened, and why it matters more than the
      typo: a verification pass produced the defect. Do not delete the record —
      it is the evidence for 8A's framing.

- [x] **B1-guard — say what the version pin does and does not catch** — folded into W-3a: the pin catches drift, not authorship.
      `form_recovery_test.exs:122` asserts `phoenix_live_view` is `1.2.8`, which
      is the mechanism S-2 added to keep the citation checkable. It did not
      catch this, and could not have: the citation was wrong **when written**,
      not stale from a bump. One sentence in the `@doc` naming that limit — the
      pin catches drift, not authorship — so the next reader does not trust it
      for more than it does. No code change.

---

## Phase 8B — Two claims that are false or under-inclusive `[elixir]`

- [x] **W-1 — the `key_available?/2` `@doc` describes a path this repo deleted** — **the review's replacement was also wrong.** Measured: the fallback *succeeds* (Config defaults `:s3` to a populated struct); the raise is `cdn_config.bucket`'s `BadMapError`. Conclusion unchanged.
      `lib/brando/cdn/cdn.ex:407-413`. The doc says a missing `:cdn` "blows up on
      `Map.from_struct/1`". S-6 added `if !s3_config do raise …` at
      `cdn.ex:123-125` — *ahead* of that call at `:129` — in the same diff. Two
      tasks in one phase wrote prose about each other's code without either
      reading the other.
      Replace the `Map.from_struct/1` clause with the config error S-6 actually
      raises. The `cdn_config.bucket` half (`:429`) and the conclusion —
      "raises before any network call, so callers on a possibly-CDN-less config
      must check first" — are correct and stay.

- [x] **W-2 — reframe `ReqOptions.merge/2`'s reachable-keys list as open** — leads with the rule, keys are examples. All citations re-verified against req 0.7.2.
      `lib/brando/videos/uploaders/req_options.ex:29-45`. Both positive claims
      verified exact (`:auth` uses `put_header/3` at `steps.ex:236, 240, 244`;
      `:base_url` inert on absolute URLs at `:122-125`) — the defect is that the
      enumeration reads closed. Lead with the general rule ("not an allowlist,
      so *any* configured key the built options do not name passes through"),
      then give the consequential ones as examples rather than a set:

      * `:redirect_trusted` — `remove_credentials_if_untrusted(request, true, _), do: request`
        (`req/steps.ex:1571`); disables cross-host credential stripping outright.
        The sharpest omission on a doc about credential-unsetting config seams.
      * `:form` / `:form_multipart` — `encode_body/1` tests both **before**
        `:json` (`steps.ex:486, 490` vs `:497`), so a configured `form:` replaces
        the body all three providers build.
      * `:json` — Bunny's GET and DELETE build no body (`bunny.ex:422, 428`), so
        a configured `json:` attaches one where there should be none.
      * `:connect_options` / `:finch` — proxy and TLS verification; same reach as
        the `:plug` already listed.
      * `:into`, `:retry`, `:redirect`, `:decode_body`, `:receive_timeout`.

      No behaviour change. The allowlist stays declined — that decision is not
      reopened.

- [x] **W-2-test — make the doc's claim falsifiable instead of restated** — `Req.Test` round trip; stub asserts `Bearer hijacked` on the wire. RED via `Keyword.take` allowlist, confirmed.
      `test/brando/videos/uploaders/req_options_test.exs:74-96` currently pins
      the four listed keys by restating `Keyword.merge`, which reinforces the
      closed reading the doc is being fixed for. Replace with a `Req.Test`
      round-trip that asserts the doc's *actual* claim: a configured
      `auth: {:bearer, "hijacked"}` **does** reach the wire and overwrite a
      provider-built `authorization` header. That is the sentence worth pinning,
      because it is the one a reader would not believe without a test.
      **RED:** the test should fail if Req ever switches `:auth` to
      `put_new_header/3` — which is exactly the drift the doc is exposed to.

---

## Phase 8C — Narration, in the present tense `[testing]`

Per Decision 1. Keep every argument; drop every past-tense reference to earlier
versions, to Phase 5, and to prior failures. Sequenced after 8A because both
sites are inside blocks 8A rewrites.

- [x] **W-3a — `test/support/live_case.ex:104-115`** — both blocks present tense; B1-guard folded in.
      Two blocks to convert. "An earlier version took a `:root | :child` role
      from the caller and skipped the wait for a child…" → state that there is
      no role argument because the runtime makes no such distinction, and that
      a real sticky child's death stops the root's proxy (naming the test that
      shows it). "The version is pinned because that is how this citation failed
      the first time…" → state what the pin is for, present tense. Fold in
      B1-guard's sentence about what it does not catch.

- [x] **W-3b — `test/brando_admin/live/form_recovery_test.exs:74-82`** — present tense; stub-proxy claim kept.
      Same treatment. "An earlier version skipped the wait for a child, on the
      reading that a child shares a proxy that outlives it" → say what the test
      establishes and why it asserts on proxy liveness rather than elapsed time.
      Keep "a stub proxy cannot see this at all" — that is a present-tense claim
      about the fixture, not history.

---

## Phase 8D — Three assertions that cannot go red `[testing]`

The harness mechanics are sound and are **not** in scope: `try do … :ok after …`
returns `:ok`, `flunk` propagates, `Process.flag/2` on a boolean cannot mask a
failure, the pinned `receive`s cannot be confused by the monitor at
`live_case.ex:120`, and Mox's private mode makes the two no-`expect` `overwrite`
tests genuinely fail on an unexpected `head_object/3`. Only these three are weak.

- [x] **W-4a — label or replace the fixture-premise assertion** — **did both, and said why**: added `refute Process.alive?(view.pid)` as a real subject assertion, kept the proxy line explicitly labelled a fixture premise.
      `form_recovery_test.exs:66`: `assert Process.alive?(proxy)` cannot fail for
      *any* change to `kill_live/1` — `kill_live` never touches the proxy, and
      the stub is an unlinked infinite sleeper. Its RED came from mutating the
      fixture, not the subject.
      This is weaker than Phase 6's vacuity rather than a repeat of it: it is a
      true statement about the fixture, asserted in the right place. Either
      label it as a fixture premise in one line, or replace it with something
      about the subject. **Decide which, and say why in the comment** — an
      assertion whose RED comes from the fixture is a category this suite will
      meet again.

- [x] **W-4b — restore causation to B1-prove** — three premises asserted, and the reason pinned. **The first version of this record was false, and is kept here rather than replaced:** it read *"RED confirmed: killing the root yields `{:proxy_stopped, :shutdown}`, which `_` accepted."* It does not. `client_proxy.ex`'s `handle_info({:DOWN, …}, state)` clause propagates the monitored view's reason verbatim, so a root killed with `:kill` also reports `:killed` and the assertion passed with the child uninvolved — measured by the Phase 8 review, which ran the mutation. Fixed by killing the child with a *distinguishable* reason (`:child_died`) instead of `:kill`; the RED was then measured both ways (root → `{:proxy_stopped, :killed}`, fails; proxy survives → `:proxy_survived`, fails). **Third instance of the audit's most durable lesson, and the first where the false claim was about an observation rather than a citation.**
      `form_recovery_test.exs:83-114`. The control test (mount, find child, kill
      nothing, assert the proxy survives 500ms) was deleted after it did its job,
      which leaves the shipped test satisfied by any other death of the root view
      inside the window. Cheap repair, no second test:
      `assert child.pid != view.pid` and `assert Process.alive?(view.pid)`
      before the kill, and assert the `:DOWN` reason rather than matching `_`.
      **RED:** confirm the reason assertion fails if the root is what died.

- [x] **W-4c — record the per-test mutation for each `req_options_test.exs` case** — five mutations named and each run. Found an error in my own comment: dropping `|| []` reddens both nil tests; only the `get_env` default mutation distinguishes them.
      Only the test at `:32` goes red under the mutation the Phase 7 plan states
      (flipped merge order). The other four need different ones — drop the
      `|| []`, or impose a `Keyword.take` allowlist. Since "watched go RED" is
      this audit's unit of evidence, a single blanket mutation claim covering
      five tests is the claim that needs narrowing. One comment per test naming
      its mutation; run each.

---

## Phase 8E — Bunny forwards its credential across hosts `[security]`

Per Decision 2. Pre-existing (`bunny.ex:414` is not in the Phase 7 diff);
surfaced while verifying W-2.

- [x] **SEC-1 — `redirect: false` in Bunny's built options** — all three branches. Checked first: all three are JSON REST calls against a fixed `@base_url`, none follows redirects.
      `lib/brando/videos/uploaders/bunny.ex:419-429`. Req's
      `remove_credentials_if_untrusted/3` (`req/steps.ex:1573-1582`) deletes only
      the `authorization` header and the `:auth` option on a cross-host redirect.
      Bunny's credential is `{"AccessKey", api_key}` (`:414`), so a 302 to
      another host forwards the library API key — stock defaults, no config
      involved. Mux and Cloudflare are unaffected; both use `authorization`.
      Add `redirect: false` to all three `request_opts` branches (`:422`, `:425`,
      `:428`). Because `ReqOptions.merge/2` is
      `Keyword.merge(configured || [], built_opts)`, a built value outranks
      config — so this cannot be switched back on from `runtime.exs`, which is
      the property that makes it worth doing in `built_opts` rather than as a
      documented default.
      **Check before writing:** confirm no current Bunny call depends on
      following a redirect (the three methods are JSON API calls against
      `video.bunnycdn.com`, so this should be a no-op on the happy path —
      verify, do not assume).

- [x] **SEC-1-test — pin it** — RED measured: without it the stub receives `{:request, "evil.example.com", ["bunny-key"]}`. Log captured to hold the output baseline.
      `test/brando/videos/provider_client_test.exs`. A `Req.Test` stub that
      answers 302 to a different host, asserting the follow-up request either
      does not happen (`redirect: false` → the 302 is returned as-is) or carries
      no `accesskey` header.
      **RED:** remove `redirect: false`, watch the credential appear on the
      second request, revert. This is the mutation that matters — it is the
      defect itself.

- [x] **SEC-1-note — say why the other two are safe** — in `bunny.ex` next to the change, plus the CHANGELOG entry.
      One line in the Bunny module or in `ReqOptions`' doc: Mux and Cloudflare
      need no equivalent because Req strips `authorization` itself. Without it,
      the next reader either adds `redirect: false` to all three as cargo, or
      removes it from Bunny as inconsistency.

- [x] **CHANGELOG — under Fixes**, consumer-visible on a library: name the
      leak, the stock-default condition, and that config cannot re-enable it.
      — added above the `overwrite:` entry: names the leak, that it needed no
      configuration to reach, that all three Bunny calls are unaffected by
      `redirect: false`, that config cannot re-enable it, and why Mux and
      Cloudflare need no equivalent.

---

## Phase 8F — Small corrections `[elixir]`

Grouped because none of them individually justifies a phase; all are from the
review's SUGGESTION tier.

- [x] **S-1 — `cdn.ex:123`'s guard misses the keyword-list config shape.** — **not reachable as stated; said so.** The cited proof is about the CDN config, not `:s3`; a keyword-list CDN config raises in `config/2` before this guard. Comment, no behaviour change.
      `!s3_config` catches `nil`, but `uploads.ex:385-389` proves a keyword-list
      config occurs, and that shape still reaches `Map.from_struct/1` at `:129`.
      Widen the guard or narrow the clause. **Check whether this is reachable in
      practice before changing behaviour** — if it is not, say so in the comment
      instead of guarding it.
- [x] **S-2 — `form_recovery_test.exs:96-97`**: monitor refs are never — both refs demonitored with `[:flush]`.
      demonitored. Add `Process.demonitor(ref, [:flush])`.
- [x] **S-3 — `form_recovery_test.exs:327`**: `stub_view_with_live_proxy/0` — coupling stated next to the version assertion.
      duck-types `%Phoenix.LiveViewTest.View{}`. A struct-shape change in
      LiveView passes silently. One line stating the coupling, next to the
      version assertion that already exists for the same reason.
- [x] **S-4 — `req_options_test.exs:64`**: `delete_env` without restore. — `fetch_env` + `on_exit` restore.
- [x] **S-5 — restate the two baselines the review could not reproduce.** — scratchpad corrected to 1280 tests and 43/27/0; both re-measured this phase.
      `scratchpad.md` says 1278 tests; actual is 1280 (the Phase 7 plan is
      right, the scratchpad is stale). Output baseline recorded as 45 lines / 29
      non-dot; measures as **43 / 27**. The substantive claim — 0 lines on
      stderr — holds exactly. Fix both so Phase 9 inherits reproducible numbers,
      and use non-dot as the headline figure per Phase 7's own note.
- [x] **S-6 — `@spec` on `ReqOptions.merge/2`.** — added.

---

## Phase 8G — Measure what Phase 7 asserted `[testing]`

- [x] **E2E — run it, and record the run.** — **measured 2026-08-06: 107 passed / 0 failed, 8.8m**, full `--reset`, against this phase's tree (includes the Bunny transport change). Recorded in `scratchpad.md` with its date, not only in the table.
      Phase 7's verification table claims 107 / 0 measured on a full `--reset`,
      but no artifact of that run exists in the tree, so the review marked it
      UNCLEAR. Nothing in Phase 8 touches E2E surface either — but this is the
      second phase in a row to carry a number whose evidence is a sentence in a
      plan. Run `cd e2e && source .envrc && ./test_e2e.sh --reset`, and record
      the pass count **and the date** in the scratchpad, not only in a table.

---

## Verification

Baselines are Phase 7's, **as measured by that review's verification runner**,
not as recorded by the Phase 7 plan (the two disagree; see S-5):

| Gate | Baseline | Phase 8 expectation |
|---|---|---|
| `mix test` | 1280 tests + 135 doctests, 0 failures | ≥ baseline, 0 failures (8B/8D/8E add ~3–4) |
| `mix credo --strict` | 284 | ≤ 284 |
| `mix compile --warnings-as-errors` | clean | clean |
| `mix format --check-formatted` | clean | clean |
| Unit-suite output | 43 lines stdout / **27 non-dot** / 0 stderr | ≤ baseline; use the non-dot figure |
| E2E | 107 / 0, **unverified two phases running** | measured this round (8G) |

**Per-task RED requirement**, unchanged from Phase 7:
- W-2-test: assert the configured `:auth` reaches the wire; red if Req switches
  to `put_new_header/3`.
- W-4b: assert the `:DOWN` reason; red if the root is what died.
- W-4c: one named mutation per test, each run.
- SEC-1-test: remove `redirect: false`, watch the credential appear, revert.

Doc-only tasks (B1-fix, B1-record, B1-guard, W-1, W-2, W-3a, W-3b, S-3, S-5,
SEC-1-note) have no RED. Saying so is the correct answer for them.

---

## Sequencing

```
8A  Blocker + habit    B1-fix → B1-record → B1-guard
      ↓ (8C rewrites the same @doc block)
8C  Narration          W-3a ∥ W-3b
      ↓
8D  Assertions         W-4a ∥ W-4b ∥ W-4c

8B  Prose claims       W-1 ∥ (W-2 → W-2-test)     ┐
8E  Bunny credential   SEC-1 → SEC-1-test → note  ├─ independent of 8A/8C/8D
8F  Small corrections  S-1 … S-6                  ┘
      ↓
8G  E2E                run last, after everything has landed
```

**8A → 8C is the only hard ordering**, and it exists because both touch
`live_case.ex`'s `@doc`. 8B, 8E and 8F are mutually independent and independent
of the 8A chain. 8G last, so the measurement describes the shipped tree.

---

## Risks

**What is this plan most likely to get wrong?** The same thing Phases 6 and 7
did: a citation. 8A replaces five interior line numbers with function heads
specifically to shrink that surface — but B1-fix, W-1 and W-2 all still assert
things about vendored code, and the audit's measured error rate on that class is
not low. Every one of those three should be checked by opening the file, not by
re-reading the prose.

**Where could this phase quietly grow?** 8E. `redirect: false` is a transport
behaviour change on a provider integration, and "confirm no current Bunny call
depends on following a redirect" is the kind of check that either takes two
minutes or turns into a question about Bunny's API contract. If it becomes the
latter, ship SEC-1-note and the CHANGELOG entry as a documented finding and ask
before changing the transport.

**What is being assumed without checking?** That 8F's S-1 is worth fixing at
all. The review's own suggestion says `uploads.ex:385-389` proves a keyword-list
config occurs, but not that it ever reaches `get_s3_config/2`'s fallback clause.
The task is written to permit "not reachable, said so" as a complete answer.

---

## Traceability — every finding has a task

| Review finding | Severity | Task(s) | Phase |
|---|---|---|---|
| B1 — three wrong `client_proxy.ex` citations | BLOCKER | B1-fix, B1-record, B1-guard | 8A |
| W-1 — stale `Map.from_struct/1` claim | WARNING | W-1 | 8B |
| W-2 — reachable-keys list reads closed | WARNING | W-2, W-2-test | 8B |
| W-3 — S-3 narration reintroduced | WARNING | W-3a, W-3b | 8C |
| W-4 — three assertions cannot go red | WARNING | W-4a, W-4b, W-4c | 8D |
| S-1 — guard misses keyword-list shape | SUGGESTION | S-1 | 8F |
| S-2 — undemonitored refs | SUGGESTION | S-2 | 8F |
| S-3 — duck-typed view stub | SUGGESTION | S-3 | 8F |
| S-4 — `delete_env` without restore | SUGGESTION | S-4 | 8F |
| S-5 — two unreproducible baselines | SUGGESTION | S-5 | 8F |
| S-6 — missing `@spec` | SUGGESTION | S-6 | 8F |
| PRE-EXISTING — Bunny `AccessKey` on redirect | — | SEC-1, SEC-1-test, SEC-1-note, CHANGELOG | 8E |
| UNCLEAR — E2E 107/0 unverified | — | E2E | 8G |

Skipped: none. Deferred: one, below.

**Deferred, and recorded for the sixth time:** the three video uploaders
disagree on missing credentials. Mux and Bunny **raise**; Cloudflare returns
`{:error, :not_configured}` (`cloudflare.ex:272-273`). A caller cannot handle
both with one branch. Pre-existing; no review finding has ever asked for it.
Six recordings is enough evidence that it will not arrive via a finding — if it
is to be fixed, it needs to be chosen deliberately, and Phase 9 is the place to
either do that or stop recording it.
