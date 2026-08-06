# Requirements Coverage (from `.claude/plans/form-audit/phase-7-plan.md`)

| # | Requirement | Task | Status | Evidence |
|---|---|---|---|---|
| 1 | Prove a real child kill stops the root proxy (real child, assert proxy liveness) | B1-prove | MET | `test/brando_admin/live/form_recovery_test.exs:73-113` — `find_live_child(view, "brando-chrome")`, monitors `proxy_pid`, asserts `outcome == :proxy_stopped`; trap_exit captured/restored via `after` |
| 2 | Collapse to `kill_live/1`; delete role arg, `:child` branch, role prose, `:child` test | B1-fix | MET | `test/support/live_case.ex:117` `def kill_live(view)`; unconditional `await_proxy_exit(proxy_pid)` at `:139`; old `:child` timing test gone (see diff at `form_recovery_test.exs:52-58`) |
| 3 | Re-verify all five call sites individually; zero `:root`/`:child` args remain | B1-callsites | MET | Exactly 5 real sites — `form_recovery_test.exs:36, 48, 187, 210, 234` (all from `live_form/2`), plus one stub site at `:58`. Grep over `lib/ test/ e2e/`: **zero** `kill_live(view, …)` remaining; only one `def kill_live` (`live_case.ex:117`) |
| 4 | Replace vacuous `refute_received` with `assert Process.alive?(proxy)` | W-3 | MET | `form_recovery_test.exs:64` `assert Process.alive?(proxy)`; RED evidence is self-reported only (no artifact) |
| 5 | `try/after` restores `trap_exit` on the flunk path | S-1 | MET | `live_case.ex:133-143` — `try do … after Process.flag(:trap_exit, prior_trap?) end`; pinned by `form_recovery_test.exs:69` |
| 6 | Delete `restore_trap_exit/0`, its call, and its compensation comment | W-4 | MET | Helper + comment deleted (end of `form_recovery_test.exs`); replaced by `assert Process.info(self(), :trap_exit) == {:trap_exit, false}` at `:69` |
| 7 | Pin `phoenix_live_view 1.2.8` next to both `client_proxy.ex` citations | S-2 | MET | `live_case.ex:96` and `:158`; version assertion at `form_recovery_test.exs:122` |
| 8a | Retire narration — `lockdown_test.exs:2-7` | S-3 | MET | `test/brando/plugs/lockdown_test.exs:2-6` — "Phase 5 gave the restore…" removed; states the current reason only |
| 8b | Retire narration — `live_case.ex:136-144` | S-3 | PARTIAL | The targeted comment is clean (`live_case.ex:152-160`), but the rewritten `@doc` reintroduces narration at `:100-110`: "An earlier version took a `:root \| :child` role…", "What the Phase 5 review actually caught was…", "that is how this citation failed the first time". Directly instructed by B1-fix, so plan-internal conflict, not oversight |
| 8c | Retire narration — `mix.exs:75-88` | MET | MET | `mix.exs:75-97` — "So they were shipped and never evaluated" removed; remaining prose states what is excluded and why (the `node_modules` glob fact is durable rationale, not history) |
| 8d | Retire narration — `form_recovery_test.exs:52-58` | S-3 | PARTIAL | `form_recovery_test.exs:73-79` still narrates: "An earlier version skipped the wait for a child, on the reading that…". Same plan-internal conflict as 8b |
| 9 | Rewrite `ReqOptions.merge/2` `@doc`: what it defends / what reaches past / nil-is-not-absent | W-1 | MET | `lib/brando/videos/uploaders/req_options.ex:18-53` — three headed sections; `req/steps.ex:236, 240, 244` and `:123` cited with req 0.7.2 named. No behaviour change |
| 10 | Direct unit test of `merge/2` (built wins, passthrough, nil-absent, reachable keys) | W-2a | MET | New `test/brando/videos/uploaders/req_options_test.exs` — 5 tests across 3 describes incl. `:auth/:plug/:adapter/:params` survival at `:74` |
| 11 | Bunny **and** Cloudflare precedence mirrors | W-2b | MET | `test/brando/videos/provider_client_test.exs` — AccessKey (Bunny) and Bearer (Cloudflare) tests added; all 3 call sites now covered |
| 12 | Confirm `finalize_direct/3` bypasses no guard; record conclusion; stop if it does not hold | W-5-investigate | MET | Conclusion recorded in `.claude/plans/form-audit/scratchpad.md` and plan `:211`; wording of the plan's Correction 4 corrected (three branches, not "unconditional"). No escalation, consistent with code |
| 13 | Reframe as downstream consumer in both places | W-5-frame | MET | `test/brando/utils_test.exs:520-525` and `.claude/plans/form-audit/phase-6-plan.md:196-198` |
| 14 | `build_upload_key/2` honours `overwrite:` (user-approved mid-phase) | overwrite fix | MET | `lib/brando/utils.ex:1182-1192` — `cond` short-circuits on `Map.get(file_cfg, :overwrite, false)`; two tests at `utils_test.exs:571, 577` with no `expect` (unexpected-call assertion) |
| 15 | CHANGELOG names the removal **and** the inverted sense | W-6 | MET | `CHANGELOG.md:5-24` — new `#### Breaking`, before/after snippet, plus the error-semantics change |
| 16 | Shim declined, with reason recorded in the CHANGELOG | S-5 | MET | `CHANGELOG.md:26-31` — "No `key_exists?/2` shim is provided, on purpose", with the uninterpretable-error argument |
| 17 | `key_available?/2` `@doc` gains the no-CDN raise ("one sentence") | S-4 | MET (over-delivered) | `lib/brando/cdn/cdn.ex:406-413` — 8 lines, not one. Names **both** raise sites (`get_s3_config/2` `Map.from_struct(nil)` and `cdn_config.bucket`); the plan says the first was probed, and the guard at `:123` corroborates it. No unverified new claim |
| 18 | Fix the `Map.from_struct/1` warning at the site(s) that warn; say which | S-6 | MET | Guard at `cdn.ex:123-125` precedes the `Map.from_struct` at `:129` (the old `:119`). `:97`/`:107` sit under a head that pattern-matched `s3: s3_config` from a present `:cdn`, so `nil` cannot reach them — plan's "never fire" is plausible. `:220`/`:358` not independently re-checked here |
| 19 | Drop/narrow `assets` in `files:`; leave the reason; dated UPGRADE.md note | S-7 | MET | `mix.exs` `files:` has **no** `"assets"` entry; rationale comment at `:85-97`; `links:` added at `:78` (user-approved). `UPGRADE.md:798-801` carries the "Note, from a later version" in the historical 0.44.0 section |
| 20 | Verification: E2E 107/0 measured this round | Verification table | UNCLEAR | No artifact in the tree — no e2e log, report, or changed e2e file. `mix test` 1280+135, credo 284, output 45 lines are likewise self-reported. Cannot verify from diff |

**Summary**: 16 MET · 2 PARTIAL · 0 UNMET · 1 UNCLEAR

## Scope creep

None found. Every changed file maps to a task. The two mid-phase additions —
`build_upload_key/2`'s `overwrite:` branch and `mix.exs`'s `links:` — are
recorded as user-approved in the plan (`phase-7-plan.md:229`, `:272`) and are
excluded per instruction.

Two notes that are *not* creep but are worth the reviewer's eye:

- `cdn.ex:123-125` raises where the code previously crashed. S-6 asked to "fix
  the call"; converting a crash into a named config error is a behaviour change
  on an error path, inside a phase whose stated remit is "claims, not
  behaviour". Small and defensible, but it is behaviour.
- The S-3 PARTIALs (8b, 8d) are caused by B1-fix's own instruction to "restate
  W1's rationale in the harness doc". The plan asked for both and they conflict;
  the narration won at two of the four S-3 sites.
