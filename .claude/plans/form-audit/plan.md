# Form logic audit — remediation plan

**Date:** 2026-08-05
**Branch:** `next`
**Research:** `.claude/plans/form-audit/research/01..06-*.md` (six specialist reports)
**Stack:** Phoenix 1.8.9, phoenix_live_view 1.2.8, Ecto 3.14

> **Rebased on `683ef6944` (2026-08-05).** A session working the *sibling* plan,
> `.claude/plans/block-editor-architecture/plan.md` (Phases 2–3), landed changes in
> `form.ex`, `block.ex`, `block/render.ex` and `block_field.ex` — the same four files most
> of this plan's findings sit in. Every `file.ex:NNN` reference below has been shifted to
> match, mechanically, from that commit's diff hunks; the shift preserves whatever each
> reference pointed at before, and nothing beyond the shift was re-audited. **One finding
> changed in substance, not just position: C5** — see the **↻ 683ef6944** note there.
>
> Function signatures that moved in those files, in case a finding you pick up sits on one:
>
> | before | after |
> |---|---|
> | `Render.can_paste?/2` (private) | deleted — `root`/`container` paste visibility is CSS off `data-paste-allow`; `Render.paste_allow/1` + `Render.multi_paste_context/2` |
> | `Block.register_block_wanting_entry/2` | `/3` — takes the entry fields the module reads |
> | `Form.send_updated_entry_field_to_blocks/3` | `/4` — takes the changed field |
> | `@blocks_wanting_entry` (list of refs) | map of `block_ref => fields \| :all` |
> | `Render.hidden_block_fields/1` took `block_form` | takes a precomputed `fields` list from `Block.assign_hidden_block_fields/1` |
>
> The two plans overlap by file, not by scope.

---

## START HERE — audit status (updated 2026-08-07)

**Phases 0–9 are complete.** Phase 8's review is closed: 2 BLOCKERs, 3 WARNINGs,
5 SUGGESTIONs, all fixed and measured. Four commits on `next`, **not pushed**:
`a5dac0331` (review fixes + 9A), `08c371da2` (9B — breaking), `7c1b4fd3e`
(9C — breaking, six public functions moved off `Form`), `4247636ce` (9D +
bookkeeping).

**Nothing is open that has been decided-and-not-done.** What remains is the two
**deferred** extractions (`ImageDrawer`/`FileDrawer`, `Chrome`), and Phase 9C
changed how they should be approached — see the note under `## G` below and
9C-3's cost table. The short version: **section G's "the seams are clean" premise
is false as written**, the markup half of each extraction is cheap and the
stateful half is not, and the two must be estimated separately.

Phases 5–9 live in their own files (`phase-5-plan.md` … `phase-9-plan.md`),
because this file's Phases 0–4 are followed by shared `## Verification` /
`## Sequencing` / `## Risks` sections and appending after those would break it.

### Do not read the checkboxes below as a to-do list

Twelve `- [ ]` boxes stood here before 9A. **Nine of them will never be ticked**
— they are decisions, reverts, rejections, or work resolved by other means, and
each already carries the annotation saying so. 9A converted those nine to inline
status markers, leaving three; **9C then ticked one, so two remain**, and both
are the deliberate Phase 10 deferrals in the table below. The full
classification is the table in `phase-9-plan.md`.

**Genuinely open work, in full:**

| What | Where | Note |
|---|---|---|
| ~~`Form.VideoDrawer` extraction~~ | `## G` below | **DONE 2026-08-07 (9C), markup only** — 354 lines out, `form.ex` 6565 → 6211 |
| `Form.ImageDrawer` / `FileDrawer` extraction | `## G` below | deferred to Phase 10 — **ungated now**: 9C's cost is measured, see 9C-3 |
| `Form.Chrome` extraction | `## G` below | same; on its face ~35 pure function components, so likely the **cheapest** of the three despite being listed last |
| ~~Cross-entry snapshot leak~~ | finding **C4** | **CLOSED 2026-08-07 (9D) — not a leak**, and the reason the audit had been giving for it was wrong about its fact |

That is the whole list. The video-uploader credential disagreement, carried
unresolved through Phases 4–8, was **closed on 2026-08-07** (`08c371da2`,
decided (a): all three raise) and is no longer tracked anywhere.

### Where the knowledge is

* **`scratchpad.md`** — the retros. This is the file to read if you are picking
  the audit up cold; the lessons are there, not here.
* **`reviews/phase-N-review.md`** — one panel review per phase, Phases 0–8.
  **Phase 9 has no review yet.**
* **Baselines**, measured on the committed tree after Phase 9 (2026-08-07):
  `mix test` **1291 + 135 doctests / 0 failures** · `mix credo --strict` **284** ·
  compile and format clean · unit-suite output **43 stdout / 27 non-dot / 0
  stderr** · E2E **108 / 0** (was 107; 9D added one recovery spec).
  The 27 is a **warm-build** number — a `mix test` that also recompiles adds two
  lines (`Compiling N files`, `Generated brando app`). That artefact caused a
  false regression report in Phase 8's review; re-run warm before believing a
  change.

### The audit's own recurring lesson

Recorded across Phases 5–8 and worth carrying into any work here: **a claim
whose only check is a re-read is not checked.** It has applied to line
citations, to prose about vendored library behaviour, to recorded test
observations that were never made, to two of Phase 9's own premises (see the
9C+9D retro), and — in Phase 8's review — to the review
panel itself, twice. Measuring is cheap; the last instance cost one edit and a
13-second test run to settle.

---

## Executive summary

The recovery architecture is **healthier than it looks from the outside**, and the audit's
first pass got it wrong before correcting itself. Worth stating up front so we don't rebuild
working machinery:

- The main entry form (`form.ex:2053-2060`) and every block form (`block/render.ex:377`)
  carry a stable `id` + `phx-change`, so they receive **LiveView's default form recovery** —
  on reconnect LV replays the DOM params through `validate` / `validate_block`, which rebase
  on a freshly DB-loaded changeset. Absence of `phx-auto-recover` means *default* recovery,
  not *no* recovery (verified in `deps/phoenix_live_view/assets/js/phoenix_live_view/view.ts:2525-2603`).
- The bespoke `recover_blocks` mechanism is correctly scoped to the one thing default
  recovery structurally cannot reach: brand-new, never-persisted root blocks.
- Orphan-safe upload delivery is implemented for the server transport, and `docs/UPLOADER.md`
  phases 1-6 have all landed.

**The real problem is not reconnect. It is that several kinds of state are held only in
changeset `changes` with no DOM backing, so they are lost by the next ordinary keystroke —
no network event required.** Recovery then can't restore them either, because there is
nothing in the DOM to replay. The user's stated scenario (image set in a picker, connection
drops before it is "closed") is a real bug, but it reproduces offline-free.

Findings are ranked by that lens: **steady-state data loss first, crashes alongside it,
recovery gaps second, robustness/cleanup after.**

### Honesty notes

- Retracted during the audit: "plain fields have zero recovery" and "existing block edits
  always silently revert" — both wrong; see `research/02-recovery.md` Corrections.
- `B1`, `A1`, `B4`, `B6` were verified by direct reading in the main session.
- `B2`, `B3` were verified by the block auditor with runtime probes.
- `B5`, `C4`, `D2` are **inferred** and carry an explicit verification step before any fix.

---

## Phase 0 — Crashes and silent data loss (steady state)

These need no disconnect to bite. Highest priority.

> **STATUS: COMPLETE (2026-08-05).** All of A1, A2, B1-B7 shipped. Gates: `mix test` 1090 pass
> / 0 fail (27 new tests, +19 net over the 1071 baseline), `mix format --check-formatted` clean,
> `mix compile --warnings-as-errors` clean, `mix credo --strict` back to its pre-existing
> baseline on every touched file. **E2E full suite: 105 passed / 0 failed** (`./test_e2e.sh
> --reset`, 8.9m — includes all 71 block specs). Every fix was verified to FAIL before the
> change by temporarily reverting it. Four corrections to this plan's own analysis are recorded
> inline below and in `scratchpad.md`.

### A1. `get_embed`/`put_embed` used on a `has_many` association → LiveView crash `[liveview][ecto]`

`refs` is `relation :refs, :has_many` (`lib/brando/content/block.ex:111`), but the ref events
drive it with embed APIs at `block/events.ex:252,254,271,274,311,313,330,333,366,369`.
`Changeset.get_embed/2` raises `expected refs to be an embed, got: assoc`. Reachable from
three live buttons (`block/render.ex:1050,1059,1062`), taking the editor LiveView down and
discarding all unsaved work in that process.

- [x] Replace `get_embed(:refs)` → `get_assoc(:refs)` and `put_embed(:refs, …)` → `put_assoc(:refs, …)` at all ten sites — reads route through the file's existing `get_assoc_list/2` (`events.ex:1007`), which the vars path already used; it absorbs `NotLoaded`/`nil`
- [x] Confirm the `:struct` vs changeset arity matches each call site's expectation (`get_assoc/3`) — all four reads want changesets (they `Enum.reject(&(&1.action == :replace))` and `get_field/2` each element), so 2-arity is correct; no `:struct` call needed
- [x] Add a regression test driving `fetch_missing_refs` / the two sibling handlers — `test/brando_admin/components/form/block/ref_events_test.exs`, 9 tests over root+child × all three handlers, plus a save round-trip. Verified failing (9/9, `Ecto.Changeset.relation!/4`) against the pre-fix code
- [x] Grep the tree for any other embed API applied to `refs`, `vars`, `children`, `table_rows` — none. Remaining `get_embed`/`put_embed` sites target real embeds (`Var.options` is `embeds_many`, block `:data` is a polymorphic embed) or dispatch on relation type (`page_vars.ex:165`, `subform.ex:338`, `multi_select.ex:1445`)

### A2. Hard `{:ok, video} =` match kills the form LiveView `[liveview]`

`components/form/input/video.ex:64,74,90,117` pattern-match `{:ok, video} = Brando.Videos.get_video(...)`.
A deleted-but-referenced video — or the `nil` `video_id` path at `:90` — raises `MatchError`
and destroys the entry form process with everything unsaved in it.
`input/image.ex:147` already handles this defensively with `case`.

- [x] Mirror the `input/image.ex:147` `case` pattern at all four sites — extracted `fetch_video/2` covering the three lookup branches; the fourth (the not-ready reload) keeps the currently-loaded video on `{:error, _}` since it is only a refresh. Probed `get_video/1` — returns `{:error, {:video, :not_found}}`, never raises
- [x] Decide the nil/missing render (empty picker state, matching the image input) — already present in `video_preview/1`: `video_placeholder` + "No video associated with field" + "Add video". No markup change needed
- [x] Test: entry referencing a hard-deleted video renders instead of crashing — `test/brando_admin/components/form/input/video_test.exs`, 4 tests (deleted / nil / present / render)

### B1. Media picked on a **persisted** ref is dropped by the next keystroke `[liveview][ecto]` ⭐

**This is the user's reported scenario, and it is not disconnect-dependent.**

The chain, verified end to end:

1. `Block.commit_ref_data/2` (`block.ex:2422-2432`) is a pure `send_update` — in-memory only,
   no DB write.
2. `update_ref_data` writes the FK into the ref changeset's **changes** (`block.ex:~748-756`,
   `put_change_if_key_exists(:image_id, params)` and siblings).
3. `render.ex:1245-1253` deliberately suppresses the `image_id` / `video_id` / `gallery_id` /
   `file_id` hidden inputs once the ref has a primary key (perf commit `6ee6e93a2`, "carry only
   ref identity once a ref is persisted"). So the FK has **no DOM representation**.
4. On the next `validate_block`, `block_for_changeset` is built from `original_data` — the DB
   refs (`block/events.ex:816`, and `:809-814` only blanks refs when the block is *unsaved*).
   `applied_block` is computed at `:781` and its own comment at `:786-788` claims it exists to
   "preserve any programmatic changes from applied_block that aren't covered by params (like
   image_id set via drawer)" — **but it is only ever used at `:793` as a NotLoaded fallback.**
   The code does not do what its comment says.
5. Result: the picked image silently reverts to the DB value.

The `render.ex` payload optimization is sound *in isolation* (`cast_assoc` leaves unmentioned
fields alone); it is the missing `applied_block` merge that makes the pair lossy.

- [x] Choose the fix — shipped **(a) + (b)**, but (a) is implemented differently than planned.
      **The plan's (a) as written would not have worked.** Merging the FK onto
      `block_for_changeset` (the base struct) makes `apply_changes` look right, so the UI shows
      the picked image — but it produces no entry in `changeset.changes`, and
      `Ops.block_diff_params` → `changes_to_params` reads `changes`. The save would silently
      drop the pick. Caught by the save round-trip test, which failed on the first attempt.
      Shipped instead: `restore_programmatic_ref_media/2` feeds the four FKs back through
      **params** before the cast, so the cast emits a real change that reaches both
      `apply_changes` and the op-store diff. Params always win when present (DOM is newer).
      Applied to both `validate_block` clauses — the child clause bases on `applied_block`, so
      it had the same save-path hole even though its steady state looked fine.
- [x] **(b)** — the four FK inputs moved out of the `if ref_form[:id].value in [nil, ""]` branch
      in `render.ex`; identity fields (`uid`/`name`/`description`) stay suppressed
- [x] Delete or correct the misleading comment at `events.ex:786-788` — both it and the
      `applied_block` comment above now describe what the code actually does
- [x] Regression test: `test/brando_admin/components/form/block/ref_media_test.exs` — 7 tests
      (pick survives keystroke, clear survives, untouched ref keeps DB value, params win over
      merge, pick survives a save, FK inputs render, identity stays suppressed). Verified 4/7
      failing pre-fix; the 3 that pass pre-fix are the controls
- **[RESOLVED ELSEWHERE]** E2E: same flow, then kill the LV process, assert the pick survives
      — **not a pending task.** Phase 4's harness (`Brando.LiveCase`, `kill_live/1`) is what this
      needed, and it kills the process for real where the E2E spec only disconnects cooperatively.
      See Phase 4's status block. Left unticked deliberately: no E2E spec was written.
      — **deferred, Phase 4 is out of this run's scope**

**Payload cost of (b), measured** (the plan's Risks section asked for this): 4 hidden inputs =
**444 bytes per persisted ref**, against 1089 bytes of total ref markup. This is mount-only —
LiveView diffs don't resend static markup, so per-edit cost is unchanged. At ~100 refs that is
~44KB on a 6.27MB mount (~0.7%), which does not meaningfully move the known mount bottleneck.

### B2. Persisted **child** blocks retain only their last edited field `[ecto]`

`block/events.ex:717` rebases the child changeset on `apply_changes(changeset)`, so
`Ops.block_diff_params` (`ops.ex:604` → `changes_to_params`) emits only the newest field, and
`{:update, …}` replaces the stored diff wholesale (`ops.ex:187`, asserted by `ops_test.exs:54`).
Probe-verified: edit `description` → `%{"description" => "abc"}`; then edit `anchor` →
`%{"anchor" => "z"}` — description gone. Edit two fields of a multi/container child and save,
and the first reverts. Roots are safe (they rebase on `changeset.data`, `events.ex:779`).

- [x] Fix: merge diffs on `:update` — **but only for children.** Merging unconditionally would
      have introduced the mirror-image bug: a root's diff is cumulative vs. `changeset.data`, so
      a field the user edits and then reverts to its stored value emits *no change at all*, and
      a merge would resurrect the superseded value from the previous diff. `{:update, …}` now
      branches on root-vs-child and deep-merges only the child (delta-shaped) diffs. Maps merge
      recursively so a diff touching ref 1 can't wipe one touching ref 0; lists (order-bearing)
      are still replaced wholesale
- [x] ~~Update `ops_test.exs:54`, which currently asserts the buggy replace semantics~~ —
      **the plan was wrong here.** That test uses a ROOT uid, where replace is the correct
      semantic; it passes unchanged. Renamed to say ROOT explicitly and added four child-side
      tests (merge, overwrite-same-key, deep merge, list replacement)
- [x] Correct the DOC-DRIFT at `ops.ex:26-28` — the moduledoc now states both semantics and why
      getting either backwards loses data
- [x] Test: edit two distinct fields on a persisted child, save, assert both persist —
      `test/brando_admin/components/form/block/child_diff_test.exs`. Drives the real child
      `validate_block` and captures the ops it emits through `send_update` (which outside a
      LiveView process is just a message to self()), then replays them through a real save.
      **Bug reproduced before fixing**; 4 tests fail pre-fix, including the save round-trip

### B3. Outline cross-parent move ships the mount seed, wiping child edits `[liveview]`

`block.ex:199-219` reads `children_forms`, which is a mount-time seed map by design
(`block.ex:1703`). The move target re-registers that stale diff (`block.ex:157` → `ops.ex:177`),
discarding the child's accumulated edits.
`test/brando/content/blocks_cross_parent_move_test.exs:118` currently assumes the opposite.

- [x] Ship the child's *current* op-store state on move, not the mount seed — `extract_child`
      now sends only the `child_uid`, and **BlockField** rebuilds the changeset from the store
      (new `Ops.materialize_child/2`, the child twin of `materialize_root/2`) cast over the
      persisted row found by walking the entry-block tree. Rebuilding in BlockField rather than
      the source parent is deliberate: the store is the only holder of current child state.
      The child's own live_component can't supply it either — its id embeds the parent's id
      (`"#{@id}-child-#{uid}"`), so a cross-parent move destroys it and mints a new CID.
      An unknown uid now logs and leaves the block under its original parent instead of
      relaying a `nil` changeset
- [x] Correct the assertion in `blocks_cross_parent_move_test.exs:118` — the assertion there is
      fine (`child.uid == "childC"`); the stale claim was the **comment** above the diff, which
      asserted the extract path "ships the child's current content" when it shipped the mount
      seed. That is now true, and the comment points at the new test
- [x] Test: edit a child, move it to another parent via the outline, save, assert edits survive
      — added to `blocks_cross_parent_move_test.exs`, plus a `materialize_child/2` contract test
      (rejects roots and unknown uids)

### B4. `@var_attrs` cannot carry video/gallery/config-target var values `[ecto]`

`lib/brando/content/block.ex:37-66` lists `image_id` and `file_id` but **not** `video_id`,
`gallery_id`, `config_target`, or the `gallery_*` fields — although the editor renders and
commits them (`render_var.ex:836,870`, `block.ex:1068`). Verified by direct read. Any such var
value is silently dropped by the cast.

- [x] Add the missing attrs to `@var_attrs` — `video_id`, `gallery_id`, `config_target`,
      `gallery_image_config_target`, `gallery_video_config_target`, `gallery_allowed_types`,
      grouped with comments so the next omission is harder to make
- [x] Audit `@block_attrs` / `@ref_attrs` for the same class of omission — **found one more.**
      `ref_changeset/3` cast `image_id`/`video_id`/`file_id` but not `gallery_id`, so a gallery
      picked on a ref was dropped exactly the same way. Fixed. (Casting the FK next to
      `cast_assoc(:gallery, …)` is safe here: params carry one or the other, and the relation is
      `on_replace: :nilify`.) `@block_attrs` is complete — its three absences (`datasource`,
      `rendered_html`, `rendered_at`) are all deliberate: `datasource` is derived from the
      module, and the render artifacts are stamped via `put_change` and dropped at materialization
- [x] Test: set a video var and a gallery var, save, reload, assert both persist —
      `test/brando/content/block_media_attrs_test.exs`, 4 tests covering all four var FKs, the
      config targets, all four ref FKs, and a `var_attrs/0` completeness guard. All 4 fail pre-fix

### B5. Refs inside `{% if %}` / `{% for %}` may be deleted on first keystroke `[ecto]` — **verify first**

`liquid_strip_logic` (`block.ex:2246`) removes those regions, so no ref inputs are rendered
(`render.ex:1208-1256`), and `cast_assoc` with `on_replace: :delete_if_exists` (`content/block.ex:111`)
would then delete them. **Inferred, not probe-verified.**

- [x] **Verify with a repro before fixing** — **CONFIRMED, with one important qualifier.**
      `test/brando/content/conditional_refs_test.exs` drives the real `block_changeset/3`:
      - params omitting `"refs"` entirely → `cast/3` skips absent keys, `cast_assoc` never runs,
        all refs survive. So a module where *every* ref is inside stripped logic is **safe**.
      - params listing a subset → the unlisted ref is marked `:replace` and deleted. So the bug
        needs at least one ref outside the logic and one inside. That is the common shape
      (this narrowing matters: the plan called it "possibly the single worst bug in the audit",
      and it is real, but it is not "any module with a conditional ref")
- [x] If confirmed: render suppressed refs as hidden inputs — new `Render.carried_refs/1`,
      the ref-side counterpart of the existing `carried_var/1`, rendered after the liquid
      splits. It emits `id` + `_persistent_id` for any ref whose name isn't in `@liquid_splits`.
      Identity alone is sufficient and verified: `cast_assoc` matches on the primary key and
      leaves unmentioned fields alone (asserted directly — `description` and `uid` survive)
- **[RESOLVED ELSEWHERE]** E2E regression covering conditional/looped ref regions
      — **not a pending task**; see Phase 4's status block. Covered at the
      changeset + component level instead; E2E belongs with the Phase 4 harness

> **Known gap, documented in `carried_refs/1`:** an *unsaved* ref inside a stripped region is
> still dropped. Identity-only carrying cannot rescue it — with no primary key to match on, Ecto
> rebuilds from params alone and blanks every field, which is exactly why `module_config/1`
> already refuses this shortcut for unsaved vars. Carrying it in full isn't possible either:
> `data` is a polymorphic embed whose shape is the entire nested block editor. Reachable by
> putting a ref inside `{% if %}` and running "fetch missing refs" on a saved block. Test
> asserts the current behaviour so a future fix is visible.

### B6. Subform add/delete/reorder flattens pending nested input `[ecto]`

`input/subform_helpers.ex:18,39` and `input/vars.ex` build the replacement list with
`Ecto.Changeset.get_field/3`, which returns **applied structs** — collapsing nested changesets
and discarding pending-but-uncommitted input on sibling rows. `put_change/3` on a relation is
mechanically fine (it routes through `Relation.change/3`, `deps/ecto/lib/ecto/changeset.ex:1968-1982`),
so the bug is the `get_field` read, not the write.

AGENTS.md prescribes the Append Changeset pattern: `get_assoc` (returns changesets) → append →
`put_assoc`. `subform.ex`'s `add_subentry` already follows it correctly — these three sites do not.

- [x] Convert `subform_helpers.ex:18,39` and the `vars.ex` site to `get_assoc` → `put_assoc` —
      done, via two new shared helpers (`current_entries/2`, `put_entries/3`) that dispatch on
      the schema (`__schema__(:association, name)`) instead of on a `embeds?`/`relations` assign,
      so the same code serves assoc- and embed-backed subforms
- [x] **The plan's claim that `subform.ex`'s `add_subentry` "already follows it correctly" is
      wrong** — it dispatches assoc-vs-embed correctly on the *write* but still reads with
      `get_field`, so it had the identical bug. Fixed there too, along with `update_subentry`
      and `remove_subentry`, plus both sites in `page_vars.ex`. Nine sites total, not three.
      (`subform.ex`'s `sequenced_subform` was genuinely safe: `get_change_or_field/2` prefers
      `get_change`, which returns changesets, and only falls back when there is no pending
      change to lose)
- [x] Test: type into subform row 1 without blurring, add row 2, assert row 1's text survives —
      `test/brando_admin/components/form/input/subform_helpers_test.exs`, 5 tests covering
      append/remove/reorder with a real `Repo.update` round-trip, plus one that pins the old
      `get_field` behaviour so the defect is unambiguous

**Mechanism correction:** the plan said `get_field/3` "discards pending-but-uncommitted input".
Measured, it is subtler and worth recording: `get_field/3` *does* carry the pending value (it
returns applied structs). What is lost is the **change** — writing structs back yields child
changesets with empty `changes`, the struct merely becomes the new `data`, and Ecto emits no
UPDATE. Probed directly:

| path | resulting child changesets | persisted |
|---|---|---|
| `get_field` → `put_change` | `[{"one", %{}}]` | `"orig1"` ❌ |
| `get_assoc` → `put_assoc` | `[{"one", %{value: "PENDING"}}]` | `"PENDING"` ✅ |

Same root cause as B1 — a value in `data` rather than `changes` never reaches SQL.

### B7. Picker *select* and *upload* have different durability `[liveview]`

Upload commits the FK immediately (`form.ex:1171` `commit_entry_field_asset`). **Select** only
assigns `edit_image` / `image_changeset` (`input/image.ex:305` → `form.ex:217`); the FK reaches
the changeset solely via drawer submit, which is wired to the close button (`form.ex:2914`
`close_image`). Dismissing the drawer any other way (Esc, backdrop, navigation) loses the pick.

- [x] Route `select_image` / `select_video` / `select_file` through `commit_entry_field_asset/4`
      — via a new `commit_selected_asset/3` guard on the three `:update_edit_*` clauses that
      carry a bare asset (the select path). Block-level picks are excluded: they arrive with a
      `block_target` and a nil `field`, and commit through `Block.commit_ref_data/2` instead
- [x] Verify picker reopen then marks the newly-selected asset — **already correct, no change
      needed.** All three entry-field inputs already push `selected_images`/`selected_files`/
      `selected_videos` back to their picker on select (`image.ex:314`, `file.ex:194`,
      `video.ex:258`), satisfying the skill's "selection means current editing state" contract
- [x] Test each dismissal path (close button, Esc, backdrop) preserves the selection —
      `test/brando_admin/components/form/picker_select_test.exs`. Esc/backdrop are client-side,
      so the test asserts the invariant that makes all three safe: the select itself commits the
      FK **as a change** (not merely applied into `data`), verified through a real `Repo.update`.
      Plus the two negative cases (block-level pick, nil field). 2 of 4 fail pre-fix

---

## Phase 1 — Recovery gaps

With the corrected picture, these are the genuine holes.

> **STATUS: COMPLETE (2026-08-05).** C1–C6 all shipped. Gates: `mix test` **1141 pass / 0 fail**
> (32 new tests, +42 net over the 1099 Phase-0 baseline), `mix format --check-formatted` clean,
> `mix compile --warnings-as-errors` clean, `mix credo --strict` **644 findings with and without
> the diff** — no new findings. **E2E full suite: 105 passed / 0 failed** (`./test_e2e.sh
> --reset`, 9.0m, assets rebuilt for the hook change). Every fix was verified to fail before the
> change by temporarily reverting it; the exact pre-fix failure counts are recorded per finding.
>
> Two things were found by the work rather than by the reports, and one plan line reference had
> drifted — all three are recorded inline below. Two checkboxes remain open on purpose: the C4
> repro (not reproducible by static reading; the fix shipped regardless, as the plan directed)
> and C1's E2E (needs the Phase 4 harness).

### C1. Children of a new unsaved root block are never recovered `[liveview]`

`assets/src/hooks/BlockField/index.js:74` captures all forms including `child_block_form-*`,
but the recovery filter at `:110-118` only matches `entry_block_form-${uid}`, and the server
rebuild hardcodes `children: []` (`block_field.ex:1164-1172`). It also calls the 3-arity
changeset, which is non-recursive — no `cast_assoc(:children)` — while the save path documents
`recursive?: true` as load-bearing (`block_field.ex:394`).

- [x] Capture and forward `child_block_form-*` payloads keyed to their parent uid — the hook now
      also captures `childOrder`, a parent-uid → **ordered** child-uid map read off the
      `data-parent_uid` wrappers that `block/render.ex:87` already emitted. Order, not just
      parentage, is required: a block's sequence is derived from its position in the children
      list at materialization, so a set would silently reshuffle the user's blocks. Recovery
      forwards each missing root plus every descendant, at any depth
- [x] Rebuild children server-side via the recursive changeset — `put_recovered_children/4`
      grafts the subtree onto the block params, and the cast switched to
      `block_module.changeset(…, user_id, true)`. Both halves were needed: with the 3-arity cast
      the assembled params are dropped silently (no `cast_assoc(:children)`), which is the same
      trap the save path documents at `block_field.ex:418`
- [x] Correct `.claude/skills/brando-blocks/SKILL.md` §9 — "preserves ALL form field values" is false
      — rewritten. §9 now leads with the mechanism's actual *scope* (never-persisted roots only;
      everything else rides LiveView's default recovery) and states the corollary that recovery
      replays the DOM, so state living only in `changes` or assigns is out of reach. §13's hook
      summary updated to match (key format, TTL, reply-gated delete, `mounted()` is a no-op)
- [x] Test: `test/brando_admin/components/form/block/recover_children_test.exs` — 6 tests
      (children recovered, order preserved, grandchildren, no-children control, unknown uid
      skipped, and a real `Repo.insert` round-trip materialized from the op store). 5 of 6 fail
      pre-fix; the no-children case is the control. Existing `block-recovery.spec.js` re-run
      green after the JS change (2/2, assets rebuilt)
- **[RESOLVED ELSEWHERE]** E2E: add a root block with children, kill the process, assert children
      return — **not a pending task**; see Phase 4's status block.
      **deferred, needs the Phase 4 harness.** Today's spec does a cooperative
      `liveSocket.disconnect()/connect()`, so the server process never dies and this path is
      not exercised end to end

### C2. Drawer field edits are lost while the drawer is open `[liveview]`

The drawer's edit form (`form.ex:2381-2495`, `id="image-drawer-form"`) is `:if={@image_changeset}`-gated,
so it exists in neither the old nor the new DOM when LV's recovery diff runs — a chicken-and-egg
problem, not missing plumbing. `recover_drawer_state` restores the *selection*; the title/credits/alt
edits inside are lost. Note `form.ex:4102-4104` silently no-ops when `resource_id` is empty.

- [x] Extend the always-rendered `#{@id}-drawer-recovery` form to carry the in-progress drawer
      field values as hidden inputs — one `drawer[changes]` input carrying the changeset's
      *pending changes*, JSON-encoded, narrowed to each drawer's editable field set
      (image: `title`/`credits`/`alt`, video: `source_url`/`type`, file: `title`). Computed in
      `assign_drawer_recovery_state/1`, which every drawer mutation already funnels through, so
      no new call sites
- [x] Replay them in `recover_drawer_state` when rebuilding `image_changeset` — all three
      `restore_*_drawer` functions, via `replay_drawer_changes/3`. Uses `cast/3`, not `change/2`:
      the values come back as strings from a hidden input, and a video's `type` is an enum that
      `change/2` would store unconverted. `cast/3` also makes the whitelist enforceable, which
      matters because the payload is hand-editable before submit
- [x] Remove the silent no-op at `form.ex:4102-4104`, or log it — **the plan's line reference had
      drifted**: `:4102-4104` is now the paramless `save_video` clause. The actual silent drop is
      the `_ ->` fallthrough in `recover_drawer_state`. Split it: a drawer that was open but
      carries no `resource_id` now logs a warning naming what was lost, while the ordinary "no
      drawer was open" case stays silent, which it should — that clause fires on every reconnect
- [x] Test: `test/brando_admin/components/form/drawer_recovery_test.exs` — 6 tests (edits
      replayed *as changes* not merely applied into `data`, no-pending-edits control, four
      malformed payload shapes, non-drawer fields rejected, the warning, and silence when no
      drawer was open). 3 of 6 fail pre-fix; the other 3 are controls

### C3. Recovery snapshot deleted before the push is confirmed `[liveview]`

`BlockField/index.js:98` calls `sessionStorage.removeItem(key)` before `pushEventTo`. Any
downstream throw, or a push that never lands, loses the snapshot permanently.

- [x] Move `removeItem` to after a server-confirmed recovery (ack event or a reply handler) —
      used the `pushEventTo/4` reply callback. This required the server side to actually reply:
      all three `recover_blocks` return paths now emit `{:reply, %{recovered: uids}, socket}`
      instead of `{:noreply, …}` (verified `{:reply, …}` is supported from a **LiveComponent**
      `handle_event` — `deps/phoenix_live_view/lib/phoenix_live_view/channel.ex:804`). If no
      reply arrives the snapshot survives to the next reconnect rather than being destroyed
- [x] Add a TTL/generation stamp so stale snapshots self-expire — `savedAt` stamped on capture,
      1h TTL checked before read. The two other paths that can safely drop the key without a
      server round-trip (nothing missing, unparseable snapshot) do so explicitly, so the deferral
      is scoped to the one case where data could be lost

### C4. Recovery key is schema-scoped, not entry-scoped `[liveview]` — **verify first**

The key is `STORAGE_PREFIX + this.el.id`, and `@id` is `"#{singular}_form"` with no `entry_id`.
In principle a stale snapshot from entry A could inject blocks into entry B. The exact trigger
path via `push_navigate` is **unconfirmed**.

- **[CLOSED — NOT A LEAK, 2026-08-07 (Phase 9D)]** Reproduce: create unsaved
      blocks on entry A, navigate to entry B without saving, reconnect
      — ~~**not reproduced, and the static read says it is hard to reach.** The snapshot is only
      written by `disconnected()`, and only `reconnected()` reads it — a hook that *mounts* after
      the reconnect runs `mounted()`, which is deliberately a no-op. So the leak needs the same
      hook element to survive an entry change, i.e. a `push_patch` within one LiveView rather
      than the `push_navigate` used between entries.~~ Recorded as unconfirmed, not as absent:
      this is a reading of the hook lifecycle, not a runtime probe.
      **AMENDED — the struck sentence is wrong about its fact.** That `push_patch` path exists:
      `form.ex`'s save-and-continue on a *create* does `push_patch(to: update_url)` after
      `assign(:entry_id, entry.id)` with no remount, and `live_view/form/hooks.ex` says so
      outright (*"create + save-and-continue push_patches to the update route without
      remounting"*). The `mounted()` barrier does not apply there.
      **The leak is still absent, for the other barrier — the one the checkbox below shipped.**
      `data-entry-id` re-renders with the patch, so `storageKey()` moves *forward* with the
      entry; the `new` bucket is orphaned, not served to a persisted entry, and orphans are
      TTL-bounded and unreachable (another create form requires navigation, which remounts).
      Now pinned by `block-recovery.spec.js`, *"the recovery key follows the entry across
      save-and-continue"*. **RED:** `data-entry-id={nil}` reddens exactly that test — **and
      leaves the other four recovery specs green**, which is how a barrier fixed in Phase 3
      went eight phases without ever being exercised
- [x] Regardless of repro, include `entry_id` in the storage key (cheap, strictly correct) —
      key is now `brando:block-recovery:<entry_id>:<el.id>`, fed by a new `data-entry-id` on the
      hook element. Unsaved entries share a `new` bucket, which is still strictly narrower than
      the previous behaviour where every entry of a schema collided

### C5. `recover_blocks` trusts client-supplied params `[security][liveview]`

`block_field.ex:1175` forces only `entry_id`. `blueprint.ex:318` casts `block_id` (letting a
client attach another entry's block row), and `@block_attrs` casts `parent_id`, `creator_id`,
`module_id`, `source` — enabling cross-entry child injection and creator spoofing. The recovered
uid is taken from params rather than from the server-checked `missingUids`.

**↻ 683ef6944** — `parent_id`, `creator_id` and `source` are three of the nine identity inputs
that now render from `Block.assign_hidden_block_fields/1` rather than straight off the block
form. The DOM surface and the submitted params are byte-identical, so the vulnerability is
unchanged; what moved is *where* the markup is produced. Any whitelist added here must not
assume those inputs are still emitted by `Render.hidden_block_fields/1` reading `@block_form`.

- [x] Whitelist recoverable fields; reject client-supplied `block_id`, `parent_id`, `creator_id`, `source`
      — `sanitize_recovered_params/4`. The entry_block level is whitelisted (dropping `block_id`,
      which `entry_id` alone never protected); the block level is whitelisted from `@block_attrs`
      minus the server-authority fields; nested relations are scrubbed recursively of
      `id`/`block_id`/`parent_id`/`creator_id`/`source`/`entry_id`/`page_id`. `module_id`,
      `container_id`, `palette_id` and `fragment_id` stay castable — every admin can already pick
      any of them from the pickers, so they are not a boundary. **The `683ef6944` note above held:**
      the whitelist is applied to the params, not to whatever emits the markup, so it is
      indifferent to `hidden_block_fields/1` having moved
- [x] Force `creator_id` from `current_user` — forced on the root, and on every child, since the
      grafted subtree was initially bypassing the sanitizer entirely
- [x] Accept only uids the server itself determined to be missing — `recoverable_uids/2`. The
      client decides what *looks* missing by diffing the DOM; the server is the only side that
      knows what it actually holds, so any uid already in `block_ops.order` or `seed_forms` is
      refused. The recovered form is also keyed by the vetted uid rather than one read back out
      of the client's params, which could otherwise land under a uid that was never checked
- [x] Test: forged `recover_blocks` payload referencing another entry's block is rejected —
      `test/brando_admin/components/form/block/recover_blocks_security_test.exs`, 10 tests
      (forged `block_id`, `creator_id`, `parent_id`, `source`, uid divergence, uid already held,
      uid already seeded, nested var scrubbing, children smuggled outside `childOrder`, children
      via `childOrder` sanitized). **All 10 fail pre-fix**
- [x] **W3 from the Phase 0 review, deferred here on purpose** — `carried_var/1` round-tripped an
      unsaved var's *whole* cast surface through hidden inputs, so all 38 `@var_attrs` were
      hand-editable before submit, `config_target` and the five owner FKs included. Now driven off
      a new `carried_var_attrs/0` (= `var_attrs/0` minus `creator_id` and the owner FKs), and
      `var_changeset/3,4` derives `creator_id` server-side instead of ignoring the user argument it
      was already being handed — which closes creator spoofing on *every* path, not just this DOM
      surface. Scoped deliberately: a client-sent `creator_id` is always discarded, but it is only
      *set* when absent, so an existing var keeps its original creator rather than flipping to
      whoever edited last. 4 further tests
- [x] **Fixed while here (AGENTS.md violation, pre-existing):** the carried-field list was called
      as a function directly in HEEx (`ContentBlock.var_attrs()`), which LiveView cannot
      change-track — it re-evaluates and re-sends the whole comprehension on every diff. Now a
      compile-time `@carried_var_fields` module attribute assigned into the template. Only such
      site in `brando_admin/`

### C6. Root config actions rebuild the form with `uid = nil`, breaking recovery keying `[liveview]`

`block/events.ex:242,295,353,390,443,480,536` read `:uid` off the **entry_block** changeset,
which has no such field (probe: `nil`). The form id becomes `entry_block_form-`, the DOM node is
re-created, and the JS hook — which keys on `entry_block_form-${uid}` — can no longer recover
that block.

- [x] Use `socket.assigns.uid` at all seven sites — all seven read the identical line, replaced
      wholesale, with one comment above the first handler explaining why the changeset is the
      wrong source. Confirmed child blocks were never affected (their changeset *is* the block
      changeset), so the bug was root-only
- [x] Assert non-nil form ids in a block component test —
      `test/brando_admin/components/form/block/config_event_uid_test.exs`, 14 tests (7 handlers ×
      root/child). All 7 root cases fail pre-fix with `"entry_block_form-"`
- [x] **Found while writing that test: a second, unrelated crash in the same file.**
      `var_struct_to_map/1` (`events.ex:980`) hand-pruned `Var`'s associations, and the list
      predates the `:video` and `:gallery` relations added by `46485e5fc` — so both reached
      `put_assoc(:vars, …)` as `%Ecto.Association.NotLoaded{}`, raising
      `UndefinedFunctionError` on `__changeset__/0` and killing the editor LiveView with every
      unsaved change in it. Reachable from the "reset var" / "reset vars" buttons
      (`render.ex:1027,1069`) on **any** module with vars, not just media ones. Pre-existing, same
      class as A1/A2. Fixed by deriving the drop list from `Var.__schema__(:associations)` so the
      next relation can't reintroduce it; `:options` is an embed and is deliberately kept.
      Covered by 2 further tests in the same file

---

## Phase 2 — Upload and delivery robustness

> **STATUS: 7 of 8 findings shipped; D2 REVERTED; the e2e regression is FIXED (2026-08-05).**
>
> Shipped and verified: **D1, D3, D4, D5, D6, D7, D-dup**, plus all 15 findings from the
> `/phx:review` pass (dispositions in `reviews/phase-2-review.md`).
>
> **Reverted: D2's stable-topic fix** (`6da10b844`) — it broke multi-user block sync. See D2 below.
>
> **Closed: `tests/projects/projects.spec.js:4`** — see **D5-tie** below. Causation was
> established first this time (the step the handoff said had been skipped twice): the spec
> **passes at `65e90b831`** and **fails on `next`**, so it was ours. Root cause measured, not
> inferred — see D5-tie for the probe output.
>
> Gates: `mix test` **1198 pass / 0 fail**, `mix format --check-formatted` clean, `mix compile
> --warnings-as-errors` clean, `mix credo --strict` **identical to baseline in every category**
> (2 / 118 / 152 / 12). **e2e: 105 passed / 0 failed.**
>
> **Three findings were wrong as written** — D6 assumed `video_block` knew the image id, D-dup
> assumed `gallery_objects.ex` shared D4's bug, D7's "re-queues on every drawer close" was already
> guarded (but wrong in the *other* direction). Details inline.
>
> **A recurring shape worth naming: library clients raise, they don't only return.** Three
> instances this phase — `Mux.api_request/3` (D3), `CDN.get_s3_config/2` via `finalize_direct/3`
> (D1), `ConfigTarget.serialize/1` (D3) — each able to kill a long-lived process holding unsaved
> work. Same class as Phase 0's A2. Worth a sweep of its own.

### D1. Direct-S3 completion after a manager remount is silently dropped `[liveview]`

`upload_manager.ex:145` is a bare `_ -> {:noreply, socket}` catch-all, and `mount` hard-assigns
`items: %{}` (`:41`). A `direct_complete` arriving after the sticky manager remounts leaves an
object in the bucket with no `File` row, no log, and no reaper — videos have
`workers/video_upload_reaper.ex`; files and images do not.

- [x] Log the unmatched `direct_complete` instead of swallowing it — the bare `_ ->` split into an
      explicit `nil ->` (no item: the manager remounted mid-transfer, which is the case that loses
      the object) and a wrong-transport clause. The log names the consequence, and says outright
      that the object will not be reaped, so it is diagnosable from production logs today
- [x] Persist pending-direct intents so they survive a manager remount — new
      `Brando.Uploads.PendingIntent` + `uploads_pending_intents` table. UPLOADER.md recorded the
      "intent channel and orphan-marking never built" (line 123), so this is the channel. Written at
      presign, removed on finalize / `direct_error` / `cancel_item`. A `direct_complete` with no
      matching item now rehydrates the intent into the same shape a live item has and runs the same
      `finalize_item/2`, so a recovered completion cannot drift from an in-process one. Both
      transports keep the rule that finalize trusts **only** server-side key + target
- [x] Add an S3 sweeper mirroring `VideoUploadReaper` `[oban]` — `Brando.Worker.UploadIntentReaper`,
      cron `45 4 * * *`, 24h cutoff (well clear of the 10-minute presign lifetime, so a slow transfer
      is never reaped out from under itself). **Deliberately unlike `VideoUploadReaper`, it deletes
      for real** — in the bucket via new `Brando.CDN.delete_object/2`, and the row. That reaper only
      marks `:errored` because a provider webhook can still arrive for a row it reaped; here the only
      actor that could still complete the upload is a browser holding an expired URL. A bucket that
      refuses the delete still drops the row, or the sweep retries the same failure nightly forever
- [x] **Chosen over the alternative on purpose:** creating the asset row up front and reaping what
      stays pending (the VideoUploadReaper pattern) would need a `status` on `Brando.Files.File`
      plus relaxing its required `filesize`/`filename` — which changes asset semantics everywhere,
      since every list and query would then have to exclude pending rows. A dedicated intents table
      keeps transport bookkeeping out of the content schemas
- [x] **Found while testing: `finalize_direct/3` raises, it doesn't only return.**
      `Brando.CDN.get_s3_config/2` blows up on a missing/malformed CDN config, and this runs in the
      **sticky** manager — one misconfigured target would take every other in-flight upload down
      with it. The module already has a catch-all `handle_event/3` for exactly this reason; the
      finalize path now honours it too. Third instance of this shape in Phase 2 (see D3's Mux note)
- [x] Test: `test/brando/uploads/pending_intent_test.exs`, 15 tests — round-trip incl. the whole
      delivery target, ref uniqueness, required key/target, **malformed ref returns nil rather than
      raising `Ecto.Query.CastError`** (the ref is client-supplied), idempotent delete, the staleness
      window from both sides, the reaper, and three `direct_complete`-after-remount cases driving the
      real `UploadManager.handle_event/3` with `items: %{}`
- [x] Migration in both places, per repo convention: `priv/repo/migrations/20260805000000_*` (the
      monolithic test migration is for the original schema; recent changes are dated files, and
      `e2e/priv/repo/migrations` symlinks here) and
      `priv/templates/brando.upgrade/migrations/brando_157_*` for consuming applications

> **Not covered, and it is the honest limit here:** no test drives a *successful* finalize, because
> there is no S3 mock boundary in the repo — that is Phase 4's "behaviour + Mox boundary for the
> S3/Mux/Bunny clients". What the tests do pin is the part that was broken: the completion now
> reaches finalize through the persisted intent instead of hitting a silent `_ -> {:noreply}`.

### D2. Delivery has no ACK and the topic is remount-scoped `[liveview]` — **verify first**

`upload_manager.ex:428` broadcasts without acknowledgement, and a form remount mints a fresh
`deliver_topic` (`form.ex:59`), so an asset delivered to a dead form vanishes with only a
`:debug` log. Interaction with mid-upload reconnect is **unverified**.

- [x] Verify the reconnect behaviour empirically before designing the fix — **DONE (2026-08-05, e2e).**
      Two successive mounts of a project form yielded `form:a852c2d1-…` and `form:dae79cd2-…`:
      the topic is per-mount, as read straight off `data-deliver-topic` (`form.ex:1897`) — no logs
      needed. A delivery in the same session logged
      `delivering asset #40 to form:dae79cd2-…`, i.e. the *current* form's topic, which is the happy
      path (no navigation mid-upload). **The mismatch itself was not observed and does not need to
      be:** the topic being per-mount is measured, `put_intake_item/6` capturing `deliver_topic` at
      intake and never updating it is certain from code, and the manager is `sticky: true`
      (`layouts/live.html.heex:3`) so it keeps transferring while the form is destroyed. Those three
      compose to the bug.
- [x] **The repro's first trigger was wrong and is corrected in `d2-repro.md`:** `liveSocket.disconnect()`
      tears down the whole LiveView tree *including sticky children*, so it kills the upload and lands
      in D1's territory rather than D2's. **Live navigation** is the trigger — manager alive, form
      replaced — and is also the realistic user story
- [x] **Correction to the finding, from reading the code:** the audit says a delivery to a dead form
      "vanishes with only a `:debug` log". It vanishes with **no log at all** — `deliver/2`'s debug
      line only fires for an item carrying *no* `deliver_topic`; a broadcast to a live-but-unlistened
      topic returns `:ok` silently. Both sides now log their topic (`UploadManager: delivering asset
      #N to <topic>` / `Form: listening for asset delivery on <topic>`), which is what makes the
      repro conclusive and is worth keeping in production regardless of the fix
- **[REVERTED]** Make `deliver_topic` stable across remount — **BUILT, THEN REVERTED (`6da10b844`).**
      The client owned the topic in `sessionStorage` (per tab, per entry) and replayed it via
      `pushEventTo('set_deliver_topic')`; the server validated and resubscribed. It verified
      correctly in the browser — project 1 → `form:a50aa0e4…`, project 2 → `form:3c0b7a58…`, back
      to project 1 → `form:a50aa0e4…` — **and still broke `block-multiuser-sync.spec.js:245`**
      (a late joiner saw the seed content instead of the edit already made).
      Bisected, one variable per run: full handshake → 1 failed; no `claimDeliverTopic()` → 9/9;
      sticky `setAttribute` but no `pushEventTo` → 9/9. **The sticky DOM write is innocent; the
      round trip is the cause.** Moving the claim to a non-rendered assign did NOT fix it, so the
      re-render is not the whole story — handling *any* event on the Form LiveComponent during its
      two-phase block mount (`blocks_ready?` is deferred by `send_update_after`) disturbs block
      sync, and the mechanism is still unknown.
      **Re-land it away from the Form's mount path** — most likely the sticky `UploadManager`
      owning the entry→topic mapping, since it already survives navigation and has no block tree
      to disturb. That is a design change, not a patch, and needs its own e2e pass.
- [x] **Kept from the reverted work**, all harmless and useful when it is re-landed:
      `data-entry-id` on the form element; `AssetIntent.validate_deliver_topic/1` made public
      (the subscribe side must apply the same rule intake does); and **truncated topic logging** —
      a topic is a bearer token, and logging it whole put a replayable credential into every log
      aggregator. `test/brando_admin/components/form/deliver_topic_test.exs` was removed with the
      handler it tested
- [x] Add an ACK + bounded retry; surface an editor-visible error when delivery finally fails —
      **WON'T DO. The premise is wrong.** `docs/UPLOADER.md:176-178` states the contract this would
      be fighting: *"Delivery is orphan-safe: the asset record is always created and stored;
      notifying the originating block/field is a best-effort PubSub broadcast. Navigate away
      mid-upload → the upload still finishes, the asset still exists, we just skip the (now-gone) UI
      update."* Delivery landing while no form is mounted is the design working, not a gap.
      An ACK has nothing to retry *to* when there is no subscriber, and an "editor-visible error"
      has no editor to appear in.
      **The actual defect was narrower than the finding stated:** a form that *was* mounted and
      *was* the right form still missed its delivery, because the topic changed underneath it
      between intake and completion. That is the remount case, and it is fixed above.
      *(Caught by the user pushing back on this being framed as a gap — worth recording that the
      audit's D2 wording implied a delivery guarantee the system never claimed.)*

### D3. Video config target hand-built with the wrong schema `[liveview]`

`form.ex:385` builds `"video:#{inspect(schema)}:#{field}"` from the **entry** schema, while the
sibling trigger at `form.ex:2779` correctly uses `edit_video.schema` + `ConfigTarget.serialize/1`.
Provider (Mux/Bunny/Cloudflare) upload is therefore broken for nested video fields, and this
violates the "use the canonical boundaries" contract in the uploads skill.

- [x] Use `Brando.Assets.ConfigTarget.serialize/1` at `form.ex:385` — **confirmed** (the line had
      drifted to `:389`). New `video_config_target/2` prefers `edit_video.schema` over the entry
      schema, exactly as the sibling trigger does, and serializes through the constructor. The
      handler body moved to `start_provider_video_upload/3` so the new failure branch didn't
      re-indent 60 lines. **`nil` is an atom**, so `serialize/1` accepted a nil field and emitted a
      trailing-colon target resolving to nothing — guarded explicitly rather than via the rescue
- [x] Grep for any remaining hand-built target strings and route them through the constructor —
      two found. `video_picker.ex:1121` had a second, divergent tuple stringifier
      (`normalize_video_config_target/1`); `videos.ex:233` rebuilt the target for the config
      normalizer from the raw caller spelling. Both now call `serialize/1`, which also canonicalizes
      `"Elixir.MyApp.Page"` → `"MyApp.Page"`. `gallery_block.ex:198-200` only prefix-matches, so it
      stays
- [x] Test: `test/brando_admin/components/form/video_upload_target_test.exs`, 4 tests. Two blueprints
      whose configs fail intake with *distinct* deterministic messages make the resolved target
      observable with no provider call. 2 of 4 fail with only the schema source reverted; the other
      two failed outright before the guards existed (see below)
- [x] **Found while writing that test: provider clients raise, they don't all return.**
      `Mux.api_request/3` raises a bare `RuntimeError` when the site has no Mux credentials, so an
      unconfigured site lost the entire entry form process — and every unsaved change in it — on any
      Mux video upload attempt. Same class as A2. `initiate_provider_upload/5` now rescues, logs the
      formatted stacktrace (so a real bug stays diagnosable) and converts to the existing error push.
      The rescue is deliberately broad: three provider clients with three failure vocabularies sit
      behind that one call

### D4. Nested gallery pickers silently no-op `[liveview]`

`input/gallery.ex:863-866` derives `form_id` from `changeset.data.__struct__`, which for a nested
gallery names a component that does not exist, so picker selections go nowhere. The upload path
gets this right via `path` (`form.ex:1201`). Same defect duplicated in `gallery_objects.ex`.

- [x] Derive the target from `path`, as the upload path does — **and the id from `@form_id`, which
      turned out to already be threaded.** `Form.input/1` passes `form_id={@id}` (the entry form
      component's own id) down through `Fieldset` → `Field` → the input's `live_component`, so no
      derivation is needed at all; the component was simply ignoring it. Fallback for a gallery
      rendered outside that pipeline reads the ROOT of the form name (`"page[items][0]"` → `"page"`),
      which is the entry's and never the owner's
- [x] Fix the payload too, not just the target — the component was shipping a replacement changeset
      for the *nested* record via `:update_changeset`. Had the id ever matched, that would have
      overwritten the entry changeset with a subrecord's. New `Form.update(%{action: :put_gallery,
      path:, key:, gallery:})` writes at the path instead, and `append_gallery_object/5` (the upload
      path that never had the bug) was refactored onto the same `put_gallery_at/4`, so there is now
      one write point
- [x] Fix both copies — **the plan's "same defect duplicated in `gallery_objects.ex`" does not hold.**
      That component only ever renders inside the `Gallery` blueprint's own form
      (`galleries/gallery.ex:63`, `component :gallery_objects`), so its changeset *is* the entry
      changeset and `"gallery_form"` was correct. De-hardcoded the id anyway so a second mounting
      context can't silently address a component that isn't there
- [x] Test: `test/brando_admin/components/form/input/gallery_test.exs` (shared with D5), 4 D4 tests.
      10 of the file's 11 fail against the pre-fix code

> **Worth knowing for any future "derive the form id" code:** a schema's form *name*
> (`Phoenix.Naming.resource_name/1`, e.g. `"project_update1"`) and its blueprint
> `__naming__().singular` (`"project"`) are **not** always the same. They coincide for real
> schemas, which is why the old derivation looked right. `@form_id` is the only authoritative
> source — it is the id the live view actually mounted the component under.

### D5. Gallery objects and selections are never re-derived from the changeset `[liveview]`

`input/gallery.ex:149-155` and `gallery_objects.ex:38-42` use `assign_new` for state that must
track the changeset, so it goes stale after any external mutation.

- [x] Move to `update/2`-derived assigns — all three assigns (`gallery_objects`, `selected_images`,
      `selected_videos`) now re-derive from the changeset on every update, in both components
- [x] **A straight `assign_new` → `assign` swap would have broken the UI, and that is the whole
      reason the cache existed.** The objects only carry a preloaded `:image`/`:video` while they
      come straight from the DB; `slim_gallery_object/1` strips the associations the moment anything
      writes the list back through `put_assoc`. Deriving alone blanks every thumbnail. New
      `Brando.Galleries.merge_loaded_media/2` lets the changeset decide *membership* while an object
      arriving without its media borrows it from the previous list by media id — no extra query
- [x] Test: mutate the gallery outside the component, assert the UI reflects it —
      `test/brando_admin/components/form/input/gallery_test.exs`, 5 `merge_loaded_media/2` cases
      (including "a removed object does not linger", which is the whole point) plus 2 component
      cases: an externally added object appears on the next update, and a slimmed object keeps the
      media the component had already loaded

### D5-tie. `merge_loaded_media/2` discarded the refresh it was written to protect `[liveview]`

**The open e2e failure handed off from the previous session.** `tests/projects/projects.spec.js:123`
uploads two images to `project_gallery` and expects two `.gallery-object img`; only one rendered.

- [x] Establish causation against `65e90b831` **before** assuming it was ours — spec **passes**
      at the pre-Phase-2 commit, **fails on `next`** (both attempts, and in isolation). Confirmed
      a Phase 2 regression. No asset or spec changes between the two commits, so the comparison is
      clean
- [x] Measure the mechanism rather than infer it — probes on all three writers. **My first
      hypothesis (`append_unique_media/2` skipping the delivery's loaded media) was wrong**: both
      objects reach the assign carrying their media. The probe:

      update_image  id=3 status=processed          → after= 3:processed@21:19:29
      assign_value  changeset= 3:unprocessed@21:19:29 | 4:unprocessed@21:19:29
                    previous = 3:processed@21:19:29
                    result   = 3:unprocessed@21:19:29 | 4:unprocessed@21:19:29   ← refresh gone
      update_image  id=4 status=processed          → after= 3:unprocessed | 4:processed@21:19:30

- [x] Root cause: **`updated_at` is second-precise.** `Ecto.Schema.timestamps()` defaults to
      `:naive_datetime`, and upload → process → refresh completes well inside one second, so the
      refreshed image and the changeset's snapshot of it compare **equal**. `fresher?/2` required a
      strict `:gt`, so image 3's `:processed` refresh was thrown away the moment image 4 was
      delivered. `Thumb` then renders the spinner placeholder instead of an `<img>` — the object was
      never lost, only its *refresh*. Not a lost object, which is what the handoff's three candidate
      call sites were all chasing
- [x] Fix: the tie now keeps the **previously-loaded** copy (`!= :lt`). That is the only side that
      receives in-place refreshes; a tie is no evidence the changeset snapshot is newer. The
      property the old tie-break claimed to protect survives — when both sides hold the same media,
      keeping the cached one writes back an equal term, so it still cannot churn the assign
- [x] Test: `gallery_test.exs` — replaced *"equal timestamps keep the changeset's copy"*, which
      pinned exactly this bug, with the second-precision case (verified failing against the old
      `== :gt`) plus a no-churn case that keeps the old test's intent. **e2e spec now passes**
- [x] **Found while verifying, and fixed — do not read "the test passes" as "this is fine".** The
      passing run emitted `found duplicate primary keys for association/embed :gallery_objects`,
      which the passing pre-Phase-2 run did not. Traced through Ecto rather than waved off:
      `gallery_at/3` reads the **applied** gallery, so unsaved objects sit in `data` with `id: nil`;
      `process_current/3` (`deps/ecto/lib/ecto/changeset/relation.ex:540`) keys that data by primary
      key, and every nil-id object keys on `[nil]`, so all but the last shadow each other. Each
      nil-id param is then matched against whichever object survived
      (`map_changes/9` → `pop_current/2` → `Changeset.change(that_struct, params)`), i.e. **image A's
      params were being applied on top of image B's struct.**
      It came out right only because `slim_gallery_object/1` pins every writable field, so the
      mismatched base contributed nothing — an accident of the param shape, not a guarantee. Fixed
      by `forget_unsaved_objects/1`: an unsaved object has no identity to match on, so it is dropped
      from the base and stays the plain insert it already is. Objects with a real id still match and
      still update rather than duplicate
- [x] Test: 3 tests in `gallery_test.exs`. Two fail pre-fix — one reproduces the warning verbatim,
      one asserts each delivery builds on a blank struct (`data.image_id` nil) instead of a
      sibling's. **The log assertion needed the test env's `config :logger, level: :error` lowered
      for its duration, or it silently asserts nothing** — worth knowing for any future
      `capture_log` here. The persisted-object case is the control. No unit-test schema owns a
      migrated gallery FK, so the save round trip stays in e2e

### D6. Two pickers ignore current editing state `[liveview]`

`render_var.ex:1366` and `video_block.ex:534` open the picker with `selected_images: []` despite
knowing the current id — violating the skill's "selection means current editing state". Entry-field
pickers all read the changeset correctly (`image.ex:71`, `file.ex:52`, `video.ex:52`).

- [x] Pass the current id at both sites — `render_var` now sends
      `List.wrap(socket.assigns.image_id)`, matching its own `set_file_target` sibling one function
      below. **`video_block` did not in fact know the id**, contrary to the finding: its
      `cover_image` assign is either the video's preloaded `thumbnail` (an `Image`, which has one)
      or the stripped `picture_data` map built by `select_image`, which does not. Added a
      `cover_image_id` assign tracked alongside it — set on select, derived from the thumbnail on
      mount, cleared by both reset paths — so the picker marks the cover the editor is showing
      whether or not it was just picked
- [x] Test: `test/brando_admin/components/form/block/picker_current_selection_test.exs`, 4 tests.
      `send_update/2` outside a LiveView process is a message to `self()`, so the picker payload is
      directly assertable. 2 of 4 fail pre-fix; the empty-selection case and the `set_file_target`
      reference implementation are the controls

> **Adjacent defect found while verifying video_block's half — NOT fixed here, needs its own scope.**
> `@picture_fields_to_take` (`video_block.ex:45-64`) takes 17 fields off the selected `Image` and
> casts them into `cover_image`, an `embeds_one Brando.Villain.Blocks.PictureBlock.Data`. Verified
> at runtime: only `formats` and `fetchpriority` exist on *both* sides. `PictureBlock.Data` carries
> override fields only — no `path`, `width`, `height`, `sizes`, `cdn`, `dominant_color`, `focal`,
> and no id — because a real picture block keeps its image as an FK on the *ref*, not in the embed.
> So picking a cover image on a video block stores essentially nothing durable; the current session
> looks correct only because the template renders the pre-cast `@cover_image` assign. Same class as
> B4 (a cast silently dropping media fields). Fixing it means either giving `Data` an image FK or
> moving the cover to a ref — a schema decision, not a Phase 2 line edit.

### D7. Drawer close re-queues image processing; upload-complete defeats drawer recovery `[oban][liveview]`

`form.ex:3945` re-queues Oban image processing on **every** drawer close, and `form.ex:604` clears
`editing_image?` on upload-complete, undermining the `recover_drawer_state` form.

- [x] Queue processing only when the image actually changed — **the "every drawer close" claim was
      already false**: a `status !== :processed` guard was in place. But that gate is wrong in *both*
      directions, which the plan missed:
      - it **misses** a focal-point change on an already-processed image. The drawer renders
        `FocalPoint` bound to the same form (`form.ex:2409-2415`), so `:focal` arrives in these
        params — and no re-queue meant every crop stayed stale;
      - it **over-fires** on an unprocessed image the user only retitled, and
        `queue_processing/4` *deletes* matching jobs before inserting, so closing the drawer while
        the first pass is executing discards that job's row and starts a second pass over the same
        derivative files.
      Now gated on `@processing_inputs` (`:focal`, `:path`, `:formats`, `:config_target`) actually
      changing, falling back to "unprocessed **and** nothing already in flight" via new
      `Brando.Images.Processing.processing_queued?/1` — which keeps the drawer's recover-a-stuck-
      upload role without the restart
- [x] Stop clearing `editing_image?` on upload-complete — done for image, video and file. An upload
      started *inside* a drawer leaves that drawer open, and `assign_drawer_recovery_state/1` gates
      on exactly these flags, so clearing one dropped the recovery snapshot mid-edit *and* let a save
      through while the image was still processing. All three clauses now call
      `assign_drawer_recovery_state/1` instead, so the snapshot follows the newly uploaded asset
- [x] **The in-code comment claiming the clear was mandatory turned out to be a workaround for a
      different bug.** `reset_image_field` and `reset_file_field` close their drawer (`toggle_drawer`)
      without clearing the flag, so "Reset image field" stranded the entry behind *"close the image
      drawer before saving"* with no drawer left to close — permanently, until reload.
      `reset_video_field` always did it correctly, which is what made the asymmetry look deliberate.
      Both now clear the flag and refresh the recovery state, so `editing_*?` is finally truthful in
      both directions and the upload-complete clear is no longer load-bearing
- [x] Test: `test/brando_admin/components/form/drawer_close_test.exs`, 9 tests. **All 9 fail against
      the pre-fix code.** Oban runs `testing: :inline`, so the `processing_queued?/1` cases insert the
      job row directly — otherwise `queue_processing/4` executes it and there is nothing to detect

### D-dup. Collapse the duplicated gallery components `[refactor]`

`input/gallery.ex` and `input/gallery_objects.ex` are near-duplicates carrying identical bugs
(D4, D5). Also: 3× entry-field delivery clauses, 3× folder→upload-path helpers.

- [x] Extract the shared gallery logic after D4/D5 land (fix first, then dedupe) — two new modules:
      `Gallery.Media` (add/remove/slim/sequence/fetch/id+assoc+selection keys/notify_picker/parse_id)
      and `Gallery.Thumb` (the grid thumbnail, which was byte-identical in both). Each component
      keeps only its own *write*, which is the one thing that genuinely differs: `Input.Gallery` has
      to reach an entry form that owns the gallery at a path, `Input.GalleryObjects` edits the entry
      changeset directly. **878 → 733** and **318 → 198** lines; 1196 → 1122 including both new
      modules and their docs
- [x] **The dedupe surfaced a third instance of the D4/D5 pattern.** The two thumbnail lookups were
      not quite identical: `Input.GalleryObjects` matched on truthiness where `Input.Gallery` guarded
      with `present?/1`, so an empty-string `image_id` compared equal to a nil one
      (`to_string(nil) == to_string("")`) and could render a *different* object's thumbnail. The
      shared `Thumb.find/1` uses the guarded version. This is exactly the cost the finding named —
      a fix landing in one copy saying nothing about the other
- [x] **Deleted the dead `handle_event("delete_selected", …)`** (`gallery.ex`), as Phase 3's F section
      flagged. Re-confirmed dead: the only `delete_selected` in a template is `content/list.ex:1212`,
      which targets the listing hook (`live_view/listing/hooks.ex:111`). It also carried the broken
      `__naming__().singular` form id, the B6 `get_field` bug, and the last unguarded `put_embed` on
      a dynamic field name — deleting it closed all three
- [x] Collapse the delivery clauses — the three single-asset `entry_field_upload_complete` clauses
      differed only in which pair of assigns they wrote, and that duplication is precisely what let
      the `editing_*?` handling drift apart between them (D7). Now one
      `deliver_entry_field_asset/5`. The two gallery clauses stay separate: they append to an assoc
      rather than setting an FK, which is a different operation, not a different spelling
- **[REJECTED AS WRITTEN]** Path helpers — **not collapsed, and the finding's "3×" is really 2×.** `file_picker`'s
      `file_upload_root/1` and `video_picker`'s `video_upload_root/1` share only the
      normalize-then-typed-default *shape*; they resolve config through different APIs
      (`Uploads.resolve_file_config/1` returning a tuple vs `Videos.get_config_for/1` returning
      `{:ok, cfg}`, plus target normalization). `image_picker` has no equivalent at all — it takes
      `assign_new(:upload_root, fn -> "images/default" end)`. Unifying means moving `video_picker`
      onto `Uploads.resolve_video_config/1`, which is a change to config *resolution*, not to
      duplication — worth doing, but it belongs with a check that the two agree, not bundled here

---

## Phase 3 — Efficiency, idioms, dead code

### E. Performance

> **STATUS: COMPLETE (2026-08-06)**, with E6 partially deferred and its reason recorded.
>
> **REVIEWED 2026-08-06** — see `reviews/phase-3-review.md`. Verdict PASS WITH WARNINGS;
> all findings now fixed and dispositioned. Two claims in the entries below were wrong and
> have been corrected in place: the container/palette scoping premise (E2) and the count of
> form-side image subscribes (nine, not eight). Gates after the fixes: 1222 tests / 0
> failures, credo at baseline, e2e 105/105.

- [x] `assign_addon_statuses/1` → `assign_new` — done, with **two exceptions that would have been
      bugs.** `has_meta?` is seeded `false` by `mount/1` (the async-load branch returns before this
      pipeline runs, so the loading render needs it), and `assign_new` would have pinned it to
      `false` forever; `has_alternates?` reads `entry.id`, which is nil until a create form saves.
      Both stay plain assigns — each is a single generated `has_trait/1` call, so neither is the cost.
      **Found while doing it:** `all_transformers_received?` and `transformer_changesets` are *state*
      owned by `reset_transformer_changesets/1`, and re-initialising them here discarded any
      changeset a transformer had already reported if a re-render landed mid-collection. Same
      "an unrelated update reverts your work" shape as Phase 0. Split into
      `assign_transformer_statuses/1`, which initialises once
- [x] Test: `test/brando_admin/components/form/addon_statuses_test.exs`, 4 tests — the transformer
      case fails pre-fix. `Form.mount/1` turns out to be callable on a bare socket, which makes the
      generic `update/2` path reachable in ExUnit without the Phase 4 harness
- [x] `block.ex` container/fragment/palette copies — scoped. Each list is an ETS read, and an ETS
      read copies the term onto the reading process's heap, so this was one copy per block component
      inside the single LiveView process. `@fragments` loads only for fragment blocks;
      `@containers` and `@palette_options` only for **container blocks**.
      **CORRECTED 2026-08-06 by the Phase 3 review — the original entry here was wrong.** It read
      "container blocks and roots — verified against the templates: `container_config` is rendered
      by every root block (`render.ex:528`)". That is false, and it was recorded as a *verified*
      fact. `container_config` (`render.ex:526`) sits inside `container/1` (`:451`), whose only
      caller is `render(%{type: :container})` (`:197,200`) — so container blocks and nothing else.
      The `or belongs_to == :root` disjunct was redundant, and every root module block was still
      copying both lists, i.e. the item delivered almost none of its intended win until the review
      caught it. Now `type == :container` alone, pinned by
      `test/brando_admin/components/form/block/container_scoping_test.exs`.
      *Lesson: "verified against the templates" meant reading the template that renders the assign,
      not the call chain that reaches that template.*
- [x] `ComponentResolver.resolve/1` moved to `Dsl.transform_form/1` — resolved once at Blueprint
      compile time instead of per field per diff. **Verified the property the token existed for is
      intact**: `mix xref graph --sink .../input/vars.ex --label compile` lists nothing, so no
      Blueprint compile-depends on an admin component. An unknown token is now a compile-time raise
- [x] Test: `test/brando/blueprint/forms/component_resolution_test.exs`, plus
      `form_component_resolver_test.exs`'s third test **rewritten** — it asserted the stored value is
      still the `:vars` token, which is exactly what this changes. It now asserts the resolved module
      and records the xref check that shows the no-dependency property survived
- [x] `:languages` / `:admin_languages` → one shared `Input.Options.expand/1`, replacing three
      byte-identical `case` arms. Deliberately **not** memoized: `Brando.RuntimeConfig` can change
      the lists at runtime, so a cache would go stale — pinned by a test that mutates the config
- [x] `block_field.ex` PubSub gated on `connected?` — both the subscribe and, more importantly,
      `request_blocks_sync/1`: from the dead render that asked every *other* connected editor to
      gather and broadcast its unsaved op-store state, for a listener discarded microseconds later.
      The expensive half landed in other processes
- [x] `image_picker.ex` no longer retains the whole config-target library in
      `socket.assigns.images` — one copy of every image row per connected admin, for the session,
      walked by change tracking on every diff, when the only consumer is `assign_folder_state/2` and
      the rendered list is **already a stream**. Renamed `assign_images/1` → `assign_config_target/1`
      since it no longer assigns images. **Tradeoff stated in the code**: folder navigation used to
      filter that cached list and now re-queries — the same query the picker already runs on open
- **[REJECTED AS WRITTEN]** `image_picker` / `video_picker`: bound the query itself — **NOT done, and the two are not the
      same case.** `VideoPicker`'s `:videos` assign *is* a real cache: `assign_folder_state/2` is
      reached from a dozen call sites there that do not reload, so dropping it would add queries
      rather than remove them. Real pagination needs the folder tree to stop being derived from the
      entries (`FolderBrowser.folders_from_entries/2`), which is a design change, not a line edit
- [x] Form-side `"brando:image:<id>"` subscriptions now unsubscribe — on `[:image, :error]`, and on
      `[:image, :updated]` **only when the image is `:processed`**. That distinction is load-bearing:
      `ImageUploader` also broadcasts `:updated`, for the freshly uploaded and still-unprocessed
      image, and unsubscribing there would drop the notification the form is waiting for. Safe
      because all eight form-side subscribes sit immediately before a processing round is queued, so
      a later round re-subscribes itself. No unit test — process-level PubSub state inside a
      LiveView is Phase 4 harness territory

### F. Dead code and drift

> **STATUS: 7 of 8 shipped (2026-08-06); the `form/tab.ex` item was attempted and reverted —
> see its entry for the evidence.**

- [x] Deleted `lib/brando/blueprint/forms/legacy.ex` and its `imports:` entry in `dsl.ex`. Verified
      with a full `mix compile --force --warnings-as-errors` (600 files) — the no-op `fieldset/2`
      it exported was shadowed by Spark's own entity macro anyway. Note for consumers: an app still
      calling the deprecated 2-arity form now gets a compile error instead of silently losing a
      fieldset, which is the better failure
- [x] The dead `handle_event("delete_selected", ...)` in `input/gallery.ex` — **already deleted in
      Phase 2's D-dup**, which re-confirmed it dead and noted it closed three defects at once
- [x] Removed the dead `mark_as_deleted` typo in `blocks.ex`. **Deleted rather than fixed, and the
      premise was checked**: `ChangesetRunner.run_pipeline/2` rewrites `marked_as_deleted: true` to
      `action: :delete` (or `:ignore`, which `put_assoc` skips) before `reject_deleted/2` runs, so
      the first clause already covers the real case. The typo'd clause was dead *and* redundant
- [x] Dropped the forced `Map.put(:action, :validate)` from `assign_form/1`,
      `assign_refreshed_form/1` and `refresh_entry`. **The premise was verified, not assumed**:
      `Phoenix.Component.used_input?/1` reads `form.params` and nothing else
      (`phoenix_component.ex:1753`), so no field of an empty-params form can surface an error with
      or without an action. Checked that nothing branches on the top-level action either — every
      `.action` read in the tree is on nested changesets testing `:replace`/`:delete`
- [x] Test: `test/brando_admin/components/form/empty_params_errors_test.exs`, 5 tests. Written
      because **there is no e2e coverage of validation-error display at all**, so the suites could
      not have caught a regression here. Includes the control: a field the user *did* touch still
      surfaces its error
- [x] Replaced the seven inline `<svg>` in the form toolbar with `<.icon>`. All seven target classes
      were checked against `assets/css/heroicons.css` before use, and the mask sets
      `background-color: currentColor`, so the live-preview toggle's `.active` colour now follows
      the button automatically — the `svg path:nth-of-type(2)` fill override in `Form.css` went dead
      and was removed. **The icon set changed, since heroicons has no equivalent for two of them:**
      Meta `tag`, Revisions `clock` (was a git-branch), Scheduled publishing `calendar-days`,
      Alternates `language`, Live preview `eye`, Share `arrow-top-right-on-square`, Save
      `arrow-down-tray` (was a floppy disk). Functionally exercised by e2e (meta, revisions and save
      are all clicked); **not visually verified — flag any of the seven and it is a one-line swap**
- [x] SKILL.md drift — §9 (C1) and `ops.ex:26-28` (B2) were fixed in their own phases. §10's
      "Position Response Tracker" is now corrected: that machinery no longer exists anywhere in
      `lib/` or `assets/src/`, because reorder under the single-owner op store is one store mutation
      with no per-block confirmations to await
- **[REVERTED]** `form/tab.ex`'s `:if` on the video drawer's Upload/External-URL sub-tabs — **ATTEMPTED, then
      REVERTED. The finding is real; its proposed fix is not a line edit, and the plan's "narrow
      blast radius: 2 fields" is wrong.**
      Switching those panels to a class toggle (matching `Form.form_tabs/1`) broke
      `e2e tests/projects/projects.spec.js:290`: after uploading a local video, no "Edit video"
      button appeared. Causation established both ways — the change in, spec fails on both attempts;
      the change out, spec passes.
      The mechanism found by reading: **the two panels bind the same field.** The upload panel
      carries a hidden `video[type]` of `:upload`; the external panel binds `video[type]` to a
      Vimeo/YouTube select. Mount both and two inputs share that name. But wrapping the inactive
      panel in a `<fieldset disabled>` — which excludes its inputs from submission while keeping
      their DOM values, and would have delivered the finding's intent exactly — **did not fix it
      either**, so duplicate-name serialization is at most part of the story and the rest is
      unidentified.
      Left as `:if`, with the reasoning and the failing spec line recorded in a comment above
      `tab_content/1` so the next reader does not repeat it. A real fix means the drawer modelling
      upload-vs-external as one `type` decision rather than two widgets for one field — its own
      scope, and it needs the e2e video path to verify
- [x] The `polymorphic_embed` / `put_change/3` question — **resolved, no change needed, and two of
      its three sites no longer exist.** B6 already replaced `subform_helpers.ex` and `vars.ex` with
      `current_entries/2` / `put_entries/3`. The one remaining site, `link.ex`, writes
      `Menu.Item.link` — a plain `has_one` to `Brando.Content.Var` (`navigation/item.ex:35`), not a
      polymorphic embed — so `put_change/3` routes through `Relation.change/3` and handles the
      changeset correctly. The only polymorphic embeds in the tree are block `:data` and the
      `CastPolymorphicEmbeds` trait. The finding's "consistent 3-site pattern" was never about
      polymorphic embeds at all

### G. Structure — `form.ex` is **6211 lines** (measured 2026-08-07 after 9C; was 6565 before it, 6257 when this was written)

Extract in this order, lowest risk first. ~~These already communicate via `send_update`, so the
seams are clean.~~

> **The premise above was CHECKED in Phase 9C and is FALSE as written.** Kept rather than deleted,
> per the audit's practice of amending records.
>
> **Inbound is `send_update`** — six sites, all real: `form/input/video.ex:241` (`:open_video_drawer`)
> and `:263` (`:update_edit_video`), and `live_view/form/hooks.ex:903/919/934/952` (the four upload
> actions). Those would retarget by changing a module name.
>
> **Outbound is direct assignment, not messages.** `handle_event("save_video_authorized", …)`
> (`form.ex`, pre-9C `:4064`) is *the mechanism by which the video id reaches the parent entry
> changeset*: it reads `form`/`entry`/`schema`/`singular` and writes `:form` and `:entry`, calls
> `ship_all_field_changes/1` and pushes `b:validate`. `update(%{action: :video_upload_complete}, …)`
> calls `update_changeset/3` for the same reason. Three further couplings are not messages either:
> `assign_drawer_recovery_state/1` computes image, video **and** file recovery in a single `cond`
> feeding the `phx-auto-recover` form on `Form`'s own element; `restore_video_drawer/2` is reached
> from the parent's own handler; and `commit_selected_asset/3` is shared with image and file.
>
> So a **stateful** extraction needs a callback protocol invented for the changeset write plus a
> CID change on every control in the drawer. A **markup** extraction costs nothing, because the
> call site already passes all seven inputs explicitly, `myself={@myself}` included. 9C did the
> second and recorded why, rather than forcing the first. That distinction should be applied to
> the two deferred items below before either is estimated.

- [x] `Form.VideoDrawer` — **DONE 2026-08-07 (Phase 9C), markup only.** `BrandoAdmin.Components.Form.VideoDrawer`,
      a `:component` exposing `render/1`, following `MetaDrawer`/`ScheduledPublishingDrawer` — the two
      sibling drawers whose events also belong to the parent form. **354 lines out of `form.ex`**
      (6565 → 6211): `@aspect_ratio_options` + `video_metadata_inputs/1` → `metadata_inputs/1`,
      `video_thumbnail_section/1` → `thumbnail_section/1`, `video_settings_section/1` →
      `settings_section/1`, `video_drawer/1` → `render/1`, and the five JS command helpers
      (`reset_video_field/2`, `reset_video_thumbnail/2`, `parse_video_url/2`, `extract_thumbnail/2`,
      `close_video/1`). All 8 `update/2` and 11 `handle_event/3` clauses stayed in `form.ex`
      deliberately — see the refutation above. The move was verified by diffing the extracted text
      against the original: **exactly 11 renames and nothing else.**
      The stale ranges were re-measured rather than trusted, and were wrong in both directions:
      `handle_event:3549-4069` **missed** `save_video`/`save_video_authorized` and **swallowed**
      six unrelated file and image handlers. `"extract_thumbnail"` — the one name in the inventory
      that does not say "video" — was checked and **does** belong to the video drawer: its only
      caller is `video_thumbnail_section/1`, rendered only from `video_drawer/1`.
      One thing the extraction surfaced that no finding had: `Tab` was aliased in `form.ex` **only**
      for the video drawer's sub-tabs, so the alias went unused and `--warnings-as-errors` caught it.

      **The extraction did not decouple, and this must be read before estimating the two below**
      (Phase 9 review SUGGESTION 5, measured in 9E rather than taken on the finding's word).
      `VideoDrawer` calls `Form.input/1` and `Form` calls `VideoDrawer.render/1`, so the dependency
      is mutual. `mix xref graph --source .../video_drawer.ex --label compile` reports the new module
      **inside a 202-node compile cycle** — it recompiles whenever anything in that cycle changes,
      exactly as `form.ex` did. Repo-wide there is still **1 cycle / 919 compile edges**.
      So what 9C bought was **line count in one file, not compile-time coupling, and not build time.**
      Both are worth having and they are not the same thing; the cost table in `phase-9-plan.md`
      § 9C-3 measures the first and says nothing about the second.
      *Consequence for Phase 10: do not justify `Chrome` or the `ImageDrawer`/`FileDrawer` pair on
      decoupling or compile-time grounds unless the extraction also breaks the `Form.input/1`
      back-edge — which none of the three sibling drawers does today.*
- [ ] `Form.ImageDrawer` / `Form.FileDrawer` — ~~`update/2:175-330`~~ — **Phase 10. The gate is
      OPEN: 9C's cost is measured** (354 lines, ~1h, both suites green throughout — see 9C-3).
      **Split it the way 9C did, and check the seam first.** These are the *harder* pair, not the
      easier: the image drawer additionally owns `image_editor_*` state and a focal-point
      component, and `assign_drawer_recovery_state/1` covers image and file in the same `cond`
      the video drawer could not be split out of. Expect the markup half to move cleanly and the
      stateful half not to.
      **Ranges doubly stale** — written before the file grew 308 lines, and 9C then removed 354
      from `:2603` onward. Re-locate by function head; do not shift them arithmetically.
- [ ] `Form.Chrome` — ~~the ~35 pure function components at `:5274-6257`~~ — **Phase 10, and on
      the evidence this is the CHEAPEST of the three, not the riskiest.** Section G ranked it last
      as highest-risk; 9C's seam check is what invalidates that ranking. "~35 *pure function
      components*" is a description of markup with no state to strand — the exact shape that cost
      9C nothing. It is also the largest, so it is where most of the remaining ~950 lines are.
      **Ranges doubly stale**, as above; `form.ex` is now 6211 lines, so `:6257` is past its end.
- **[DECISION, not a task]** Leave gallery/entry-relation delivery in place — state-entangled, not a clean split

---

## Phase 4 — Test harness (enables regression-proofing the above)

Coverage today: **zero mounted-LiveView form tests** (`live(conn` has no hits in `test/`).
Recovery is covered only by `e2e/.../blocks/block-recovery.spec.js`, which does a *cooperative*
`liveSocket.disconnect()/connect()` — the server process never dies, so it does not exercise the
case that actually loses data.

> **STATUS: COMPLETE (2026-08-06).** All 7 items shipped. Gates: `mix test` **1257 pass / 0 fail**
> (35 new tests, +35 over the 1222 Phase-3 baseline), `mix format --check-formatted` clean,
> `mix compile --warnings-as-errors` clean, `mix credo --strict` **284 findings, identical to
> baseline**. **E2E full suite: 108 passed / 0 failed** (`./test_e2e.sh --reset`, 9.0m).
> New deps: `{:lazy_html, ">= 0.1.0", only: :test}` (required by LiveViewTest) and
> `{:mox, "~> 1.2", only: :test}`; `mix.lock` gained only those and `fine`.
>
> **Three of the seven items were wrong as written, and the harness found four defects.**
> Two items asked for guarantees the system does not make (asset cleanup; recovery after a hard
> reload) and one asked for a boundary the wrong shape (one Mox seam for three HTTP clients that
> already have `Req.Test`). The defects: the entry form dropping everything default recovery
> handed it, a `validate` with no `_target` killing the form, `uid` required-but-unenforced, and
> block recovery not firing on a real connection loss at all. Two migrations were needed to make
> the test DB match what shipped apps have — the fixture had been under-specifying constraints,
> which is its own recurring finding. Details inline per item.
>
> The three checkboxes deferred from Phases 0–1 to "the Phase 4 harness" (B1's E2E, B5's E2E,
> C1's E2E) are addressed by the harness's existence rather than individually: `Brando.LiveCase`
> is what those needed, and `form_recovery_test.exs` covers B1/C1/C2's mechanism at the level
> that actually distinguishes them. They stay unchecked in their own phases, deliberately.

- [x] Add the first `Phoenix.LiveViewTest.live/2` form test — mount, kill the LV pid, remount,
      assert recovery. Unblocks B1/C1/C2 regression tests. Confirm a content-module factory exists `[testing]`
      — `test/support/live_case.ex` + `test/brando_admin/live/form_recovery_test.exs` (9 tests).
      Four pieces had to be wired before `live/2` worked at all, none of which existed: the test
      endpoint never plugged `BrandoIntegrationWeb.Router`, had no `:live_view` signing salt and a
      `secret_key_base` under the cookie store's 64-byte minimum, `BrandoIntegration.Presence` was
      defined but never started (`Hooks.handle_params/3` tracks every admin mount), and there was no
      `<admin_module>.Menus`. Added `{:lazy_html, ">= 0.1.0", only: :test}`; `mix.lock` gained only
      it and `fine`. Factories confirmed present (`:page`, `:module`, `:module_with_refs`, `:ref`).
      `kill_live/1` traps exits — `live/2` links the test to the client proxy, so an untrapped kill
      takes the test down with the view.
- [x] **The harness found a live data-loss bug on its first real assertion, and it is the one this
      whole audit is about.** `Form.handle_event("validate", …)` assigned the recomputed form
      *inside* the `[^singular | rest]` branch of its `_target` case. But form recovery has no
      originating element, so `pushFormRecovery` names **the first non-hidden input in the form**
      (`view.ts:2450`) — and on the entry form that is the `image_editor_upload` file input at
      `form.ex:2105`, two elements in. The server turns that into `_target: ["image_editor_upload"]`
      (`channel.ex:848-853`), which falls to the `[_]` clause: the recovered params were cast into a
      changeset and then **dropped**. Every reconnect recovered nothing, silently.
      This sharpens the scratchpad's retraction #1 rather than reversing it — default recovery *does*
      fire for plain fields, as recorded; the handler discarded its result. Fixed by assigning the
      form before the branch. Same edit closed a second hole: the case had no fallback, so a
      `validate` carrying no `_target` raised `CaseClauseError` and killed the form with every
      unsaved edit in it. Both pinned by tests verified failing pre-fix
- [x] **Fixed while here:** the sticky upload manager's queue form had `phx-change` with no `id`
      (`upload_manager.ex:647`), so `getFormsForRecovery()` skipped it — LiveViewTest warns about
      exactly this, which is how it surfaced. It is the one form that outlives a reconnect by design
- [x] Playwright: **positive** sessionStorage-recovery assertion via hard `page.reload()`, not just
      a socket toggle `[testing]`
      — **there is no positive assertion to make, and that is by design.** The hook captures in
      `disconnected()` and replays in `reconnected()`; `mounted()` is an explicit no-op ("No recovery
      on fresh mount"). A reload tears the page down without a disconnect and brings it back as a
      fresh mount, so neither half runs. Wrote the assertion that *is* meaningful instead —
      sessionStorage survives a reload within the tab, so the snapshot is still sitting on the new
      page; the test pins that a reload starts clean and does not replay it. If recovery ever moved
      to `mounted()`, abandoned blocks would resurrect on an unrelated page, and this catches it
- [x] Playwright: true network partition (`context.setOffline` / CDP) vs today's cooperative disconnect `[testing]`
      — **and it found the gap Phase 4 suspected was hiding behind the cooperative test.**
      `goOffline`/`goOnline` in `utils.js`: `setOffline` so LiveSocket's reconnects genuinely fail,
      plus closing the transport directly, because an established websocket does not notice
      `setOffline` at all — it dies on the next missed heartbeat, 30s out. Deliberately **not**
      `liveSocket.disconnect()`: that is the client agreeing to stop, and it disarms auto-reconnect.
- [x] **Measured, not inferred — block recovery does not fire on a real connection loss.**
      The probe: `disconnected()` fires and the snapshot is written correctly (root uid + its form
      both present). But when the network returns, LiveView cannot rejoin the view it lost and does a
      **full page reload** — so the hook runs `mounted()`, the no-op, and the snapshot is never read.
      It sits there until the 1h TTL. Recovery therefore covers `liveSocket.disconnect()` →
      `connect()`, a path only a test or the dev console takes, and not the connection loss it was
      written for. Confirmed by probe output: title empty, `.entry-block` count 0, snapshot key still
      in storage, one `PAGE LOAD` event.
      **Not fixed here, and the obvious patch does not work.** Moving recovery into `mounted()` would
      replay one abandoned create form's blocks into the next one — every unsaved entry shares the
      `new` bucket (C4), which is exactly what the "stale sessionStorage" test forbids. A real fix
      needs an identity that survives a reload without colliding across create forms: a design change,
      not a line edit, and the `tab.ex` item is the cautionary precedent. The spec asserts the current
      behaviour explicitly so the gap is visible and a future fix flips the test
- [x] DataCase upload/asset orphan test mirroring `orphaned_blocks_test.exs` — nothing currently
      verifies uploaded rows are cleaned up on a failed or reset save `[testing]`
      — **the framing was wrong and the premise check is the finding.** They are not cleaned up,
      deliberately: `docs/UPLOADER.md:529` separates asset creation from delivery, and
      `research/03-uploads.md:88` already recorded it as an *accepted-by-design orphan* — "the asset
      row is permanent… there is no GC for unreferenced assets". A cleanup test would have asserted a
      guarantee the system never made, which is D2's mistake exactly. `test/brando/uploads/asset_orphan_test.exs`
      instead pins the contract that does hold, both ways: an asset survives a failed save, a cleared
      field and a deleted entry (it is shared library content — a sibling entry pointing at the same
      image proves why deleting would be wrong), while the *references* give way when the asset is
      purged. Gallery objects are the opposite case and asserted as such: join rows with no life of
      their own, `delete_all` on both FKs. 9 tests
- [x] **Found by writing it: `clean_up_soft_deletions/0` could be wedged by one referenced image.**
      Seven asset FKs in the monolithic test migration were bare `references(:images)`/`references(:files)`,
      i.e. Postgres `NO ACTION`, where every consuming app gets `on_delete: :nilify_all` from
      `brando_80_extract_embeds_one_image_fields` / `brando_92_extract_files_embeds_one`. Purging a
      soft-deleted image that any page still referenced raised `foreign_key_violation` on
      `pages_meta_image_id_fkey` — and since `clean_up_soft_deletions/0` maps over the soft-delete
      schemas in order, every schema after `Image` was then never purged. **Fixture drift, not a
      production bug** — checked against the shipped templates before concluding, and the shipped
      side is correct. Aligned in a dated migration
      (`20260806000000_nilify_asset_fks_in_test_schemas`, per the repo convention that the monolithic
      file is the original schema; it is symlinked into e2e so both DBs get it). Two tests
      mutation-verified against the pre-migration fixtures: both raise the FK violation verbatim.
      *The point stands on its own: a fixture that under-specifies a constraint makes every test
      written on top of it assert behaviour production does not have.*
- [x] Introduce a behaviour + Mox boundary for the S3/Mux/Bunny clients — no mock boundary exists
      today (no Mox/Bypass hits for uploads) `[testing]`
      — **two seams, not one, and the split is the design decision.** S3 got the behaviour
      (`Brando.CDN.Client` + `Client.ExAws`, mocked via `{:mox, "~> 1.2", only: :test}`); the three
      video providers speak HTTP through `Req`, which ships `Req.Test`, so wrapping them in a
      behaviour would be a second seam over one the library already provides — **and a behaviour
      mock can only assert *that* a client was called, when the bugs these clients have are in the
      request they build.** Cloudflare already had a `:req_options` config seam; Mux and Bunny now
      match it. `config :brando, :cdn_client, Brando.CDN.Client.Mock` in test, so any un-stubbed S3
      call fails loudly rather than reaching a bucket
- [x] **Presigning was deliberately left out of the boundary**, and four existing tests are why.
      `ExAws.S3.presigned_url/5` is an HMAC over local credentials, not a network call — routing it
      through the mock bought nothing and broke `presign_put/3`'s four tests, which assert the signed
      URL's actual query parameters. Reverted after seeing them fail. *A seam belongs where the
      process boundary is, not where the module boundary is*
- [x] Test: `test/brando/uploads/direct_finalize_test.exs`, 4 tests — **the coverage D1 recorded as
      its honest limit** ("no test drives a *successful* finalize, because there is no S3 mock
      boundary in the repo"). Drives a completed direct upload all the way to a real `File` row, and
      pins that the server trusts only its own key/target plus what the bucket reports: a client
      claiming a 1234-byte PDF over a 12MB object, or `application/pdf` over `text/html`, is rejected
      — which is the entire reason `finalize_direct/3` does a HEAD instead of believing
      `direct_complete`. Plus `test/brando/videos/provider_client_test.exs`, 5 tests asserting the
      requests Mux and Bunny actually build (basic auth, library path, asset settings), and D3's
      raise-vs-return distinction from the client side
- [x] **Found by writing it: `Application.put_env(key, nil)` is not the same as absent.** The
      config-restore helper stored `nil`, which beats the `[]` default in
      `Application.get_env(:brando, __MODULE__, [])`, so `Keyword.get(nil, …)` raised a
      `FunctionClauseError` — breaking `video_upload_target_test.exs`'s D3 assertion in a
      *different file*, reproducibly but only when both ran. Restore now deletes the key when
      `fetch_env/2` says there was none
- [x] Partial-failure multi-root block save (one root invalid, siblings valid) — untested at any level `[testing]`
      — `test/brando/content/partial_block_save_test.exs`, 8 tests driving the real save path
      (materialize → recursive cast → `reject_deleted` → `strip_render_artifacts` → `put_assoc` →
      update). Pins atomicity (nothing persists, so a retry cannot double-insert the valid roots),
      error attribution (`[[], [:type], []]` — the editor has to point at *which* block failed), an
      invalid nested child aborting the whole tree, and the realistic case: valid blocks under an
      entry that fails its own validation. **The load-bearing one is that the valid siblings' content
      survives in the returned changeset** — the form re-renders from it, so losing it would be
      Phase 0's data-loss shape arriving through the save path
- [x] **Found by writing it: two identity holes, and only one was fixture drift.**
      - `uid` is declared `required: true` (`content/block.ex:86`) but neither `block_changeset/3`
        nor `recursive_block_changeset/3` enforced it, so **a root saved happily with `uid: nil`**.
        Not cosmetic: the op store keys on uid, the block component's DOM id is `block-<uid>`, and
        block recovery keys on `entry_block_form-<uid>` — a nil-uid block is unaddressable by all
        three. C6 fixed one way of *producing* one; `validate_required(:uid)` closes the source.
        Real fix, not fixtures. Mutation-verified; full suite green, so nothing was relying on it
      - `unique_constraint(:uid)` was declared with no index behind it in the test DB, so two roots
        could share a uid. Consuming apps have had `unique_index(:content_blocks, [:uid])` since
        `brando_123_blocks_uid_constraint` — fixture drift again, aligned in
        `20260806000001_unique_block_uid_in_test_schema`. Mutation-verified by rolling it back.
        **Second instance of the same class in one session** (see the FK item above): the test
        migration under-specifies constraints that shipped migrations do specify, and every test
        written on top of it then asserts behaviour production does not have
- [x] Replace fixed `waitForTimeout` (500-1500ms) in the block-recovery and multiuser-sync specs
      with event-driven waits — highest flake risk in the repo, per its own CI-timing note in `utils.js` `[testing]`
      — **all 19 gone from those two files** (2 in block-recovery, 17 in multiuser-sync). Three
      different replacements, because they were waiting for three different things:
      - waiting for a *server* round trip → `syncLV` or a retrying `expect`. A sleep that is
        immediately followed by an auto-retrying assertion was only ever adding latency
      - waiting for the socket to drop → `expect('.phx-connected').toBeHidden()`
      - waiting for the form to be usable after save-and-continue → assert the blocks themselves are
        there. `syncLV` returns while the block editor is still a loader shell, which is what the
        750ms was really covering
      What remains fixed is only the two **client-side timers the app itself runs** — `phx-debounce`
      (300ms) and `SHIP_SETTLE_MS` (400ms) — now named in `awaitBlockDebounce`/`awaitBlockShip`
      alongside the hook they mirror, each followed by an event-driven `syncLV`. That is the honest
      floor: they are plain `setTimeout`s in `assets/src/hooks/Block/index.js` with nothing
      observable to wait on. The variable part — everything after the push — is no longer guessed,
      which is what the flakes were
      **Verified: `block-recovery` 4/4, `block-multiuser-sync` 9/9, full e2e 108 passed / 0 failed
      (9.0m, `--reset`).** The 128 `waitForTimeout` calls in the other specs are out of this item's
      scope, which named these two files

---

## Verification

Per task:

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix test
mix credo suggest --format json --all --only warning
```

E2E (per AGENTS.md — **always `source .envrc` first**; rebuild assets when JS changed):

```bash
cd e2e/assets/backend && pnpm build        # only if JS/CSS changed
cd e2e && source .envrc && ./test_e2e.sh --reset tests/blocks/block-recovery.spec.js
```

Run only the specific failing spec while iterating, never the full suite.

---

## Sequencing

- **Phase 0** ships first and independently — A1/A2 are crashes, B1-B7 are silent data loss.
  B1 is the user's reported bug and should lead.
- **Phase 4's first task** (mounted LV test + pid kill) is worth pulling forward alongside B1,
  since it is what proves B1 and C1/C2 actually fixed.
- **Phase 1** depends on nothing in Phase 0 but shares files with B-tasks — sequence C6 and B1
  together to avoid churn in `events.ex`.
- **Phase 2** is independent of 0/1.
- **Phase 3** last; G (extraction) only after Phase 0 lands, to keep those diffs readable.

## Risks

- **Is the plan actually complete?** Every finding from all six reports is represented above or
  explicitly marked verify-first. Nothing was dropped as "pre-existing".
- **What could make B1's fix wrong?** Option (b) alone re-inflates the block payload that commit
  `6ee6e93a2` deliberately shrank. Measure the mount/edit payload before and after; the audit
  confirmed per-edit cost is currently flat and mount is the real cost, so regressing mount would
  be a poor trade. Option (a) carries no payload cost — hence (a) for correctness, (b) scoped to
  the four FK fields only for recoverability.
- **What is still unverified?** B5, C4, D2, and the `polymorphic_embed` `put_change` question.
  Each has a verify-first step rather than a speculative fix.
