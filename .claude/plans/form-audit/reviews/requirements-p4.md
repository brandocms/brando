# Phase 4 requirements verification (`.claude/plans/form-audit/plan.md`, lines 1036-1221)

Scope: `git diff HEAD~5`. Checkmarks in the plan are self-reported (the plan was edited in the
same range), so every row below is judged against code, not prose.

## Requirements Coverage (from `.claude/plans/form-audit/plan.md` — Phase 4)

| # | Requirement | Status | Evidence |
|---|-------------|--------|----------|
| 1 | First `Phoenix.LiveViewTest.live/2` form test — mount, kill LV pid, remount, assert recovery; confirm content factory | MET | `test/support/live_case.ex:1` (`kill_live/1` at :95, traps exits; `form_params/2` :181, `recovery_params/2` :241); `test/brando_admin/live/form_recovery_test.exs` 9 tests incl. "an unsaved edit is gone after the process dies" (:45) and "replaying the captured DOM restores the edit" (:61). Endpoint wiring in `config/test.exs:60-66` (64-byte `secret_key_base`, `live_view: [signing_salt:]`), `test/test_helper.exs`. `{:lazy_html, only: :test}` at `mix.exs:165` |
| 2 | Playwright: **positive** sessionStorage-recovery assertion via hard `page.reload()` | MET-WITH-DEVIATION | Justification **verified true**: `assets/src/hooks/BlockField/index.js:53-54` `mounted()` is an explicit no-op ("No recovery on fresh mount"), capture is `disconnected()` (:61), replay is `reconnected()` (:57) — a reload runs neither, so no positive assertion exists to write. Substituted with the assertion that is meaningful: `block-recovery.spec.js:128` "a hard reload starts clean and does not replay a stale snapshot" (:148 snapshot survives, :154 not replayed). Deviation is documented in-spec at :116-127 |
| 3 | Playwright: true network partition (`context.setOffline` / CDP) vs cooperative disconnect | MET | `e2e/e2e/playwright/utils.js:65` `goOffline` (`context().setOffline(true)` + direct transport close, with the "an established websocket does not notice setOffline" rationale at :52-63), `goOnline` :73, exported :300-301. Used by `block-recovery.spec.js:81` "a real network partition does NOT recover" (:90, :102) |
| 4 | DataCase upload/asset orphan test verifying uploaded rows are cleaned up on failed/reset save | MET-WITH-DEVIATION | Justification **verified true**: `docs/UPLOADER.md` §7 "Orphan-safe delivery" ("asset creation ≠ delivery", asset persisted before any notify) and `research/03-uploads.md` §1.2 already recorded this as an *accepted-by-design orphan* ("the asset row is permanent… there is **no GC** for unreferenced assets"). The requirement as written asked for a guarantee the system does not make. `test/brando/uploads/asset_orphan_test.exs` (9 tests) pins the contract that does hold in both directions: asset survives failed save (:61), cleared field (:86), entry delete (:101); purge nilifies referrers (:118); gallery objects deleted with gallery (:171) and with the purged image (:188) |
| 5 | Behaviour + Mox boundary for the S3/Mux/Bunny clients | MET-WITH-DEVIATION | Justification **verified true on both halves**. (a) Presign exclusion: `lib/brando/uploads.ex:474` calls `ExAws.S3.presigned_url/5`, which is local HMAC signing, not a network call — excluding it is correct and documented at `lib/brando/cdn/client.ex:14-18`. (b) Two seams: behaviour `Brando.CDN.Client` (`client.ex:47-55`) + `Client.ExAws` (:68), wired at `cdn.ex:394,411`, Mox pinned in test via `config/test.exs:7` and `{:mox, "~> 1.2"}` (`mix.exs:167`); Mux/Bunny get the `Req.Test`-compatible `:req_options` seam (`mux.ex:572-576,591`, `bunny.ex:430-434,449`) matching Cloudflare's existing one. **Narrower than the wording implies**: only `head_object`/`delete_object` cross the behaviour; `upload_file/3`, `upload_image/4`, `ensure_bucket_exists/1` deliberately stay outside (`client.ex:19-23`) |
| 6 | Partial-failure multi-root block save (one root invalid, siblings valid) | MET | `test/brando/content/partial_block_save_test.exs`, 8 tests: atomicity (:84), per-root error attribution (:102), valid siblings' content preserved in the returned changeset (:121), corrected re-save (:143), invalid nested child aborts tree (:181), entry-level failure (:203), plus the uid tests (:236, :247) |
| 7 | Replace fixed `waitForTimeout` in block-recovery + multiuser-sync specs with event-driven waits | MET | `grep -c waitForTimeout` = **0** in both `block-recovery.spec.js` and `block-multiuser-sync.spec.js`. Remaining fixed waits are confined to `utils.js:32 awaitBlockDebounce` / `:43 awaitBlockShip`, which mirror the app's own client-side timers (`phx-debounce` 300ms, `SHIP_SETTLE_MS` 400ms, named at `utils.js:25`) and are each followed by an event-driven `syncLV`. Disclosed in the plan; the other 128 calls are outside the item's named files |

**Summary**: 4 MET · 3 MET-WITH-DEVIATION · 0 PARTIAL · 0 UNMET · 0 UNCLEAR

### All three claimed justifications are TRUE

No false justification found. Each was checked against the artifact the author cited:
`docs/UPLOADER.md` §7 + `research/03-uploads.md` §1.2 (asset orphans accepted-by-design),
`assets/src/hooks/BlockField/index.js:53-61` (`mounted()` no-op / `disconnected()` capture /
`reconnected()` replay), and `lib/brando/uploads.ex:474` (`presigned_url/5` is local HMAC).
The `_target` claim behind the item-1 bug fix also checks out: `form.ex:2105` is a
`live_file_input` for `:image_editor_upload`, and the pre-fix `case` had only `[^singular | rest]`
and `[_]` clauses (`form.ex:3086` diff) — a `validate` with no `_target` raised `CaseClauseError`.

### Bundled fixes shipped under Phase 4 (not separate plan items, verified present)

| Fix | Evidence |
|---|---|
| `validate` assigns the recomputed form before the `_target` branch; catch-all clause added | `lib/brando_admin/components/form.ex:3060` (assign moved out), :3086 (`_` replaces `[_]`) |
| Sticky upload-manager queue form given an `id` so `getFormsForRecovery()` sees it | `lib/brando_admin/live/upload_manager.ex:651` |
| `uid` required-but-unenforced | `lib/brando/content/block.ex:166,208` `validate_required(:uid)`, pinned at `partial_block_save_test.exs:236` |
| Test-fixture constraint drift (asset FKs `NO ACTION`; no unique index on `content_blocks.uid`) | `priv/repo/migrations/20260806000000_nilify_asset_fks_in_test_schemas.exs`, `…20260806000001_unique_block_uid_in_test_schema.exs`; asserted at `asset_orphan_test.exs:118,136` and `partial_block_save_test.exs:247` |

### Deferred-from-Phases-0-1 E2E items (plan lines 144, 245, 364) — claimed "addressed by the harness's existence"

| Item | Assessment |
|---|---|
| B1 E2E — ref pick survives an LV process kill (`plan.md:144`) | **Defensible, partially.** `Brando.LiveCase.kill_live/1` is exactly the missing capability, and `form_recovery_test.exs:45,61` exercises the kill→replay mechanism. But no test drives a *ref pick* through it; the ref-specific coverage stays at the changeset/component level (`ref_media_test.exs`). Mechanism covered, scenario not |
| C1 E2E — root block with children, kill process, assert children return (`plan.md:364`) | **Defensible, and the Phase-4 e2e work strengthens the case.** The measurement in `block-recovery.spec.js:81` shows a real connection loss triggers a full page reload into `mounted()` (a no-op), so the C1 E2E as written would assert a behaviour the system does not currently have. Writing it now would be D2's mistake again. The gap is pinned by an explicit test rather than left silent |
| B5 E2E — conditional/looped ref regions (`plan.md:245`) | **Weakest claim; effectively scope carried forward, not addressed.** This item has nothing to do with process death or recovery, so `LiveCase`/`kill_live` give it nothing, and no test in the diff touches conditional/looped ref regions. The blanket sentence at `plan.md:1059-1062` ("addressed by the harness's existence") over-generalises from B1/C1 to B5 |

**Not silently dropped**: all three remain `- [ ]` in their own phases with explicit "deferred"
prose, so nothing is claimed as complete that is not. The only correction warranted is narrowing
the Phase-4 status note's claim so it covers B1/C1 (whose blocker really was the harness) and not
B5 (whose blocker was never the harness).
