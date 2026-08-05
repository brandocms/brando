# Test Review: Phase 2 (cfb3639fc, d852ec7ef, a3f8a7d35) — 47 new tests

## Summary

Same high bar as Phase 0/1: these drive real production code (`Form.update/2`,
`Form.handle_event/3`, `Gallery.handle_event/3`, `RenderVar.handle_event/3`,
`UploadManager.handle_event/3`, `Processing.processing_queued?/1`), not
reimplementations, and most assert on real `Repo`/changeset state rather than
apply-only shortcuts. `video_upload_target_test.exs`, `gallery_test.exs`,
`picker_current_selection_test.exs`, `deliver_topic_test.exs`, and
`drawer_close_test.exs` all pin observable, distinguishing behaviour — a
reverted fix would genuinely flip these assertions.

**One file does not clear that bar: `pending_intent_test.exs`'s three
`describe "direct_complete after the manager remounted"` tests.**

## Iron Law Violations

None new. No Mox, no mocked DB/internal modules, no `Process.sleep`
(`deliver_topic_test.exs` uses `refute_receive ..., 50` — a bounded wait on a
real broadcast, not a sleep-and-hope). `async: false` blanket across all 6
files — PERSISTENT from the Phase 0 review's note; still not per-file
justified, still matches repo-wide convention, still out of scope to change
here.

## Issues Found

### Critical

- [ ] **`test/brando/uploads/pending_intent_test.exs:191-229` — the three
  `direct_complete`-after-remount tests do not actually distinguish pre-fix
  from post-fix code.** Confirmed by reading pre-fix shape (preserved in
  `.claude/plans/form-audit/research/03-uploads.md:103-108`): the old
  `handle_event("direct_complete", ...)` case had a bare wildcard `_ ->
  {:noreply, socket}` as its catch-all for "no item found" — not a bound
  variable, so it never crashed on `nil`. Walking each test's assertions
  against both old and new code:
  - `"an unknown ref is refused without crashing the sticky manager"` —
    asserts `{:noreply, socket}` and `socket.assigns.items == %{}`. Both true
    under the OLD `_ ->` wildcard too (nothing ever touched `items`). No
    distinguishing assertion.
  - `"a known ref is recovered from its intent, and kept if finalize fails"`
    — asserts the intent row still exists after the call. Since there is no
    S3 mock boundary (correctly documented as a known gap), `finalize_item/2`
    always fails in this test env and the `rescue`/`{:error, _}` path always
    leaves the intent untouched — which is *also* exactly what the OLD
    wildcard clause did (never touched the intent at all). Same observable
    result either way.
  - `"a forged ref cannot finalize anything"` — asserts only `{:noreply,
    _socket}`, no crash. Same non-distinguishing shape as the first case.
  
  All three do exercise the new `nil -> finalize_orphaned_complete(...)`
  code path (so they're not worthless — a crash inside that path, e.g. a
  `KeyError` from `item_from_intent/1`, would be caught), but as written they
  are **regression tests for "does not raise," not for "the completion now
  reaches finalize via the persisted intent"** as the file's own comment
  claims (`pending_intent_test.exs:181-183`). The plan (D1 section) does not
  claim a pre-fix failure count for this describe block either — unlike
  every other item in Phase 0-2 — which is honest but should be stated in
  the test file itself, the way `conditional_refs_test.exs`'s known-gap case
  was flagged in the Phase 0 review. A stronger assertion (e.g. capturing the
  `Logger.warning`/`Logger.info` lines the new code path uniquely emits via
  `ExUnit.CaptureLog`, or asserting `finalize_item` was reached by checking a
  telemetry/side-effect) would make these true regression tests instead of
  crash-smoke-tests.

### Warnings

- `test/brando/uploads/pending_intent_test.exs` and
  `test/brando_admin/components/form/drawer_close_test.exs` both insert real
  `Oban.Job`/backdate `inserted_at` rows directly against the repo
  (`Ecto.Changeset.change(inserted_at: ...) |> Repo.update!()`). This is the
  correct way to get "stale" state under `testing: :inline`/`:manual` without
  fighting Oban's test mode, and both are scoped per-test with unique
  `Ecto.UUID.generate()` refs / factory-built images, so no leakage between
  tests was found. Flagging only because it's a repeated pattern across two
  files with near-identical `backdate/2` helpers (`pending_intent_test.exs:101-108`
  vs the inline version in `drawer_close_test.exs`'s job helper) — same
  drift risk the Phase 0 review flagged for the duplicated `socket_for/2,3`
  helpers. A shared `test/support/` helper would remove the duplication.

- Recurring bare-`%Phoenix.LiveView.Socket{}` + direct `handle_event`/`update`
  pattern, present in every file here (`gallery_test.exs`,
  `picker_current_selection_test.exs`, `video_upload_target_test.exs`,
  `deliver_topic_test.exs`, `drawer_close_test.exs`). Assessed against the
  "zero mounted-LiveView tests" gap (Phase 4 task, not re-reported as new):
  what this style cannot catch —
  - A real template referencing an assign the hand-built socket never sets
    (mount-time `assign_new`/`mount/2` defaults are skipped entirely, so a
    test can pass while a real mount would `KeyError` on first render).
  - CID/component-identity regressions (AGENTS.md's "Stable Component IDs"
    footgun) — these tests fabricate `%Phoenix.LiveComponent.CID{cid: 1}`
    once and never remount, so nothing here would catch a real re-mount
    minting a fresh CID.
  - Real DOM-driven event params (string keys/values as LiveView actually
    delivers them) vs. hand-typed maps — `picker_current_selection_test.exs`
    is careful here (`var_socket("123")` deliberately keeps a string id), but
    that carefulness is per-test-author discipline, not structurally
    enforced.
  - `%{socket | assigns: Map.put(socket.assigns, :myself, %Phoenix.LiveComponent.CID{cid: 1})}`
    (`gallery_test.exs:47`, `picker_current_selection_test.exs:36`) to set
    the reserved `:myself` key: **acceptable.** `assign/3` refusing reserved
    keys is a guard against accidental component misuse, not an invariant
    these tests are trying to violate — they need a real, stable `:myself`
    for `send_update` target matching, and both sites comment why. The only
    residual risk is `Phoenix.LiveComponent.CID`'s shape drifting (unlikely;
    it's a small public struct), not the bypass technique itself.
  This is the same risk profile the Phase 0 review already named (PERSISTENT,
  not new): correct-if-fixture-list-stays-current, degrading silently if a
  handler starts reading an assign the hand-rolled socket doesn't supply and
  that path happens to no-op rather than raise.

- `test/brando_admin/components/form/deliver_topic_test.exs:75-91` — the
  malformed-topic table includes `42` (an integer) alongside string bogus
  values, asserted through the same `Form.handle_event("set_deliver_topic",
  %{"topic" => bogus}, ...)` call — fine, since real DOM params only ever
  deliver strings, so `42` is a slightly-too-defensive addition rather than a
  realistic case, but it's harmless and does exercise
  `AssetIntent.validate_deliver_topic/1`'s non-binary guard.

### Suggestions

- `pending_intent_test.exs`'s "a bucket that refuses the delete still drops
  the row" test (`:154-173`) is good but its comment claims the target "has
  no CDN configured at all" — worth double-checking this is actually
  guaranteed by the `image:Brando.Pages.Page:meta_image` target in test
  config rather than happening to be true today; if a future test-env CDN
  default is added for Page images this test would start asserting the
  reaper's happy path instead of its error path, silently.
- Consider `ExUnit.CaptureLog` around the three `direct_complete`-after-remount
  tests (see Critical above) — cheapest fix that turns them into genuine
  regression tests without needing the Phase 4 S3/Mox boundary.

## Coverage vs Phase 2 plan

D1 (partially — see Critical), D2/deliver_topic, D3/video-target, D4+D5/gallery,
D6/picker-selection, D7/drawer-close all have tests matching what the plan
claims, with real pre/post-fix distinguishing assertions except the
`pending_intent_test.exs` gap noted above. The plan's own "not covered"
callout for a *successful* `finalize_direct/3` (no S3 mock boundary) is
accurate and correctly left as a Phase 4 item — separate from the Critical
finding above, which is about the *unsuccessful*-path assertions not
distinguishing old from new code, not about the missing success-path
coverage.
