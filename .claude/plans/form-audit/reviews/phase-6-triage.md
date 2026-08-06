# Phase 6 triage

**Source review:** `.claude/plans/form-audit/reviews/phase-6-review.md`
**Slug:** `form-audit` · **Date:** 2026-08-06
**Outcome: 14 approved, 0 skipped, 0 deferred**

Everything in the review was approved. Three items carry a user decision that
changes the shape of the work — recorded inline rather than left to the
implementer.

---

## Fix queue

### B1 — the `:child` branch rests on a false premise `[BLOCKER, auto-approved: Iron Law]`
`test/support/live_case.ex:102-103` (doc) · `:128` (code) · `:140-144` (comment)

**Decision (user): prove it with a real child view before fixing.**

The finding rests on reading `deps/phoenix_live_view/.../client_proxy.ex`
(`put_view/3` monitors every view `:846-859`; children go through it `:1001`;
`{:DOWN, …}` → `{:stop, …}` `:542-545` via `state.pids` `:909`) — not on an
observed failure. This audit has twice shipped, or nearly shipped, an agent
finding that turned out to be a hypothesis with a `file:line` attached. The
check is the deliverable.

- [ ] **B1-prove** `[testing]` — mount a **real** nested `live_render` child,
      kill its pid, and observe whether the root proxy actually dies. Assert on
      proxy liveness, not on elapsed time — elapsed time is what the false
      premise predicts, which is why the existing `:child` test cannot see this.
      A stub proxy will not do here; the whole question is what the real one does.

- [ ] **B1-fix** — follows what B1-prove shows:
      - **Proxy dies on a child kill** (expected) → the role distinction is not
        real. Collapse toward `kill_live/1` that always awaits and flunks, and
        restate W1's rationale in the plan: the flunk was the fix, the inference
        was not the defect.
      - **Proxy survives** → the doc is right and B1 is withdrawn. Say so
        explicitly, and pin the `phoenix_live_view` version next to the citation
        so the claim stays checkable.

- [ ] **B1-callsites** — whatever B1-fix decides, re-verify all five sites in
      `form_recovery_test.exs` rather than trusting the previous verification.

---

### W-1 — `ReqOptions.merge/2`'s doc overstates its own guard `[WARNING]`
`lib/brando/videos/uploaders/req_options.ex:18-20`

**Decision (user): narrow the doc. No behaviour change.**

`Keyword.merge/2` defends only the keys built options *name*. Req's `auth` step
uses `Req.Request.put_header/3`, not `put_new_header` (`deps/req/lib/req/steps.ex:236,240,244`),
so `req_options: [auth: {:bearer, "…"}]` survives the merge and then overwrites
the built credential. Same route for `:plug`, `:adapter`, `:params`.
`:base_url` is safe (no-ops on absolute URLs, `steps.ex:122`).

A `Keyword.take/2` allowlist was offered and **declined** — it is a
library-visible behaviour change, and the actor is the config author, who already
owns `runtime.exs`. The defect is the claim, which is this phase's remit.

- [ ] Rewrite the `@doc` to state what the merge actually defends (the keys built
      options name) and name the keys that reach past it. Keep the "a config seam
      that can unset credentials is a config seam that will" reasoning — it is
      still the argument for the merge order, just not for a total guarantee.

---

### W-2 — precedence pinned at 1 of 3 call sites `[WARNING]`
`test/brando/videos/provider_client_test.exs:174-196`

- [ ] Add a direct unit test of `ReqOptions.merge/2` — pure, no stub, free.
- [ ] Add a Bunny mirror of the colliding-`headers:` test, so a re-inlined flip at
      `bunny.ex:431` or `cloudflare.ex:282` goes RED. Today it stays green,
      because those tests install their stub via `plug:` — the exact
      order-insensitivity the Mux test escaped.

---

### W-3 — an assertion that cannot fail `[WARNING]`
`test/brando_admin/live/form_recovery_test.exs:65`

- [ ] Replace `refute_received {:EXIT, ^proxy, _}` with `assert Process.alive?(proxy)`.
      The stub proxy is `spawn/1` — unlinked, never dies — and `kill_live/2` only
      receives, so nothing can put that message in the mailbox. Vacuous, inside
      the suite whose standard is that every assertion be watched go RED.

---

### W-4 — `restore_trap_exit/0` is inert `[WARNING]`
`test/brando_admin/live/form_recovery_test.exs:66`

- [ ] Dissolve it via the `try/after` in S-1 below, rather than moving it. It sits
      under the only line it could protect, is skipped if that line raises, and
      ExUnit discards the flag on test-process exit anyway — so it provides
      nothing while its comment claims it compensates for `kill_live/2` flunking
      before restore. Delete the helper **and** the claim.

---

### W-5 — `build_upload_key/2` has no caller in this repo `[WARNING]`
`lib/brando/utils.ex:1174`

**Decision (user): investigate first, then decide. Do not remove yet.**

The open question is not "is this dead code" but **"is `uploads.ex` bypassing a
guard it should be using?"**

- [ ] **W-5-investigate** — determine whether the non-direct upload path should
      route through `build_upload_key/2`. `finalize_direct/3` calls
      `Brando.CDN.head_object/2` directly at `uploads.ex:266` and `:292` with its
      own `{:error, :not_found}` handling; if the collision-avoidance rename that
      `build_upload_key/2` exists to perform is missing there, W-5 is a *live
      upload defect*, not dead surface, and belongs in its own phase.
- [ ] **W-5-frame** — whatever the investigation shows, correct the framing.
      The plan's "this is a production upload path, so the standard applies at
      full strength" and the test comment both describe a downstream consumer,
      not this tree. Say downstream.

Removal was offered and **declined for now** — it would undo most of 6B.

---

### W-6 — public function removed with no CHANGELOG entry `[WARNING]`
`CHANGELOG.md`

- [ ] Add `Brando.CDN.key_exists?/2` removal to the Unreleased section, with the
      replacement (`key_available?/2`, inverted sense) named. Consumer-visible on
      a library; the Unreleased section already carries prose for smaller changes.

---

### Suggestions — all 7 approved

**Harness**
- [ ] **S-1** `try/after` around `kill_live/2`'s body so `trap_exit` is restored on
      the flunk path too (`live_case.ex:125,149`). This is what dissolves W-4.
- [ ] **S-2** Pin the `phoenix_live_view` version next to both `client_proxy.ex:542-545`
      citations (`live_case.ex:99,141`), as the `view.ts` mirror elsewhere in this
      suite already does. **B1 is the argument for this** — a citation to a
      moving dep that says the opposite of what it is cited for.
- [ ] **S-3** Retire the change-narration comments. **Decision (user): now, not in
      a final sweep.** `lockdown_test.exs:2-7`, `live_case.ex:136-144`,
      `mix.exs:82`, `form_recovery_test.exs:52-58` — state what the code does, not
      what it used to do. Sequence after B1 and W-3/W-4, which rewrite two of
      those four sites anyway.

**CDN / docs**
- [ ] **S-4** `key_available?/2`'s `@doc` gains a sentence on the unguarded no-CDN
      path (a nil `:cdn` raises on `cdn_config.bucket` before any presign or
      write). The doc enumerates the other outcomes; this is the gap.
- [ ] **S-5** Consider a deprecation shim for `key_exists?/2` rather than outright
      removal. Pairs with W-6.
- [ ] **S-6** Pre-existing: `Map.from_struct/1` deprecation at `cdn.ex:119`
      (`get_s3_config/2`). Warns on Elixir 1.20.0-rc.3 via stderr — it is two of
      the 76 baseline lines — and will harden into an error.

**Packaging**
- [ ] **S-7** Pre-existing: `mix.exs` `files:` ships `"assets"` as it exists on
      disk, and `assets/node_modules/` exists locally and is gitignored. Run
      `mix hex.build` and check what actually lands in the tarball.

---

## Skipped

None.

## Deferred

None.

---

## Carried forward, not triaged here

Already recorded as out of scope in the Phase 6 plan and re-confirmed by this
review's panel — listed so it is not lost a third time:

- The three video uploaders disagree on missing credentials: Mux and Bunny
  **raise**, Cloudflare returns `{:error, :not_configured}`. A caller cannot
  handle both with one branch. Pre-existing; no finding has asked for it.

## Baselines Phase 7 must hold

Measured by this review's verification runner, not inherited:

| Gate | Baseline |
|---|---|
| `mix test` | 1271 tests + 135 doctests, 0 failures |
| `mix credo --strict` | 284 |
| `mix compile --warnings-as-errors` | clean |
| `mix format --check-formatted` | clean |
| Unit-suite output | 76 lines **on stdout+stderr combined** (43 on stdout alone) |
| E2E | 107 / 0 — **unverified this round**, carried from the implementer |
