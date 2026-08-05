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
- [ ] E2E: same flow, then kill the LV process, assert the pick survives (needs Phase 4 harness)
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
- [ ] E2E regression covering conditional/looped ref regions — **not done**, covered at the
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
- [ ] E2E: add a root block with children, kill the process, assert children return —
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

- [ ] Reproduce: create unsaved blocks on entry A, navigate to entry B without saving, reconnect
      — **not reproduced, and the static read says it is hard to reach.** The snapshot is only
      written by `disconnected()`, and only `reconnected()` reads it — a hook that *mounts* after
      the reconnect runs `mounted()`, which is deliberately a no-op. So the leak needs the same
      hook element to survive an entry change, i.e. a `push_patch` within one LiveView rather
      than the `push_navigate` used between entries. Recorded as unconfirmed, not as absent:
      this is a reading of the hook lifecycle, not a runtime probe
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

### D1. Direct-S3 completion after a manager remount is silently dropped `[liveview]`

`upload_manager.ex:145` is a bare `_ -> {:noreply, socket}` catch-all, and `mount` hard-assigns
`items: %{}` (`:41`). A `direct_complete` arriving after the sticky manager remounts leaves an
object in the bucket with no `File` row, no log, and no reaper — videos have
`workers/video_upload_reaper.ex`; files and images do not.

- [ ] Log the unmatched `direct_complete` instead of swallowing it
- [ ] Persist pending-direct intents so they survive a manager remount
- [ ] Add an S3 sweeper mirroring `VideoUploadReaper` `[oban]`

### D2. Delivery has no ACK and the topic is remount-scoped `[liveview]` — **verify first**

`upload_manager.ex:428` broadcasts without acknowledgement, and a form remount mints a fresh
`deliver_topic` (`form.ex:59`), so an asset delivered to a dead form vanishes with only a
`:debug` log. Interaction with mid-upload reconnect is **unverified**.

- [ ] Verify the reconnect behaviour empirically before designing the fix
- [ ] Make `deliver_topic` stable across remount (derive from entry identity, not process)
- [ ] Add an ACK + bounded retry; surface an editor-visible error when delivery finally fails

### D3. Video config target hand-built with the wrong schema `[liveview]`

`form.ex:385` builds `"video:#{inspect(schema)}:#{field}"` from the **entry** schema, while the
sibling trigger at `form.ex:2779` correctly uses `edit_video.schema` + `ConfigTarget.serialize/1`.
Provider (Mux/Bunny/Cloudflare) upload is therefore broken for nested video fields, and this
violates the "use the canonical boundaries" contract in the uploads skill.

- [ ] Use `Brando.Assets.ConfigTarget.serialize/1` at `form.ex:385`
- [ ] Grep for any remaining hand-built target strings and route them through the constructor

### D4. Nested gallery pickers silently no-op `[liveview]`

`input/gallery.ex:863-866` derives `form_id` from `changeset.data.__struct__`, which for a nested
gallery names a component that does not exist, so picker selections go nowhere. The upload path
gets this right via `path` (`form.ex:1201`). Same defect duplicated in `gallery_objects.ex`.

- [ ] Derive the target from `path`, as the upload path does
- [ ] Fix both copies (see D-dup below)

### D5. Gallery objects and selections are never re-derived from the changeset `[liveview]`

`input/gallery.ex:149-155` and `gallery_objects.ex:38-42` use `assign_new` for state that must
track the changeset, so it goes stale after any external mutation.

- [ ] Move to `update/2`-derived assigns
- [ ] Test: mutate the gallery outside the component, assert the UI reflects it

### D6. Two pickers ignore current editing state `[liveview]`

`render_var.ex:1366` and `video_block.ex:534` open the picker with `selected_images: []` despite
knowing the current id — violating the skill's "selection means current editing state". Entry-field
pickers all read the changeset correctly (`image.ex:71`, `file.ex:52`, `video.ex:52`).

- [ ] Pass the current id at both sites

### D7. Drawer close re-queues image processing; upload-complete defeats drawer recovery `[oban][liveview]`

`form.ex:3945` re-queues Oban image processing on **every** drawer close, and `form.ex:604` clears
`editing_image?` on upload-complete, undermining the `recover_drawer_state` form.

- [ ] Queue processing only when the image actually changed
- [ ] Stop clearing `editing_image?` on upload-complete

### D-dup. Collapse the duplicated gallery components `[refactor]`

`input/gallery.ex` and `input/gallery_objects.ex` are near-duplicates carrying identical bugs
(D4, D5). Also: 3× entry-field delivery clauses, 3× folder→upload-path helpers.

- [ ] Extract the shared gallery logic after D4/D5 land (fix first, then dedupe)
- [ ] Collapse the delivery clauses and path helpers

---

## Phase 3 — Efficiency, idioms, dead code

### E. Performance

- [ ] `form.ex:1404-1426` `assign_addon_statuses/1` recomputes static per-schema data (5× `has_trait`,
      `Code.ensure_compiled!`, transformer changeset map) with `assign/2` on **every** `send_update`,
      including high-frequency Presence diffs (`page_form_live.ex:23`). Switch to `assign_new` —
      sibling helpers in the same pipeline already do. **Cheapest win in the audit.** `[liveview]`
- [ ] `block.ex:927-938,1260-1266` — every block ETS-copies all containers/fragments/palettes,
      though only container/fragment blocks render that markup. Cheapest **mount** win. `[liveview]`
- [ ] `fieldset/field.ex:28` calls `ComponentResolver.resolve/1` every render on a value that is
      static per Blueprint compile. Resolve once in `Dsl.transform_form/1`, store on the struct
- [ ] `input.ex:286-296` (`radios/1`) recomputes `:languages` every render; `select.ex:336-345` and
      `multi_select.ex:578-587` already cache via `assign_new`. Extract one shared helper
- [ ] `block_field.ex:656,672` subscribes to PubSub and broadcasts on the **dead** render — gate on `connected?`
- [ ] `image_picker.ex:93` / `video_picker.ex:104` load the entire library for a config target into
      assigns on every open/refresh/folder change — paginate or stream
- [ ] Form-side `"brando:image:<id>"` subscriptions are never unsubscribed
      (`hooks.ex:511,531,603,628,663,692`); the manager unsubscribes correctly at `:451`

### F. Dead code and drift

- [ ] Delete `lib/brando/blueprint/forms/legacy.ex` (no-op macro, zero call sites) and its import
      at `dsl.ex:273`
- [ ] Delete the dead `handle_event("delete_selected", ...)` in `input/gallery.ex:727-750`
      (**found during Phase 0's A1 audit**) — the only `delete_selected` in a template is
      `content/list.ex:1212`, which targets the listing hook (`live_view/listing/hooks.ex:111`),
      not this component. It is also the last unguarded `put_embed` on a dynamic field name and
      carries the B6 `get_field` bug, so deleting it closes both without a separate fix
- [ ] Remove the dead `mark_as_deleted` typo at `lib/brando/content/blocks.ex:923`
- [ ] Drop the forced `Map.put(:action, :validate)` in `assign_form/1` (`form.ex:4863-4890`),
      `assign_refreshed_form/1` (`:4876-4883`), `refresh_entry` (`:924-933`) — `error_tag`/`has_error`
      already gate on `used_input?/1`, so it achieves nothing
- [ ] Replace inline hand-rolled `<svg>` in `form.ex:1911-1977` with the `<.icon>` convention
- [ ] Fix SKILL.md drift: §9 recovery claim (C1), §10's removed position-response tracker,
      `ops.ex:26-28` (B2)
- [ ] `form/tab.ex:44-49` uses `:if` (full unmount) for the video drawer's Upload/External-URL
      sub-tabs (`form.ex:2748,2823`), so switching mid-edit can drop an unflushed `source_url`.
      Main form tabs correctly use CSS toggling (`form.ex:2236-2238`). Narrow blast radius: 2 fields
- [ ] Verify `vars.ex:118`, `link.ex:69`, `subform_helpers.ex:18,39` `put_change/3` usage against
      `polymorphic_embed`'s `cast/1` — consistent 3-site pattern, likely intentional, **unverified**

### G. Structure — `form.ex` is 6257 lines

Extract in this order, lowest risk first. These already communicate via `send_update`, so the
seams are clean.

- [ ] `Form.VideoDrawer` — `update/2:365-459`, `handle_event:3549-4069`
- [ ] `Form.ImageDrawer` / `Form.FileDrawer` — `update/2:175-330`
- [ ] `Form.Chrome` — the ~35 pure function components at `:5274-6257`
- [ ] Leave gallery/entry-relation delivery in place — state-entangled, not a clean split

---

## Phase 4 — Test harness (enables regression-proofing the above)

Coverage today: **zero mounted-LiveView form tests** (`live(conn` has no hits in `test/`).
Recovery is covered only by `e2e/.../blocks/block-recovery.spec.js`, which does a *cooperative*
`liveSocket.disconnect()/connect()` — the server process never dies, so it does not exercise the
case that actually loses data.

- [ ] Add the first `Phoenix.LiveViewTest.live/2` form test — mount, kill the LV pid, remount,
      assert recovery. Unblocks B1/C1/C2 regression tests. Confirm a content-module factory exists `[testing]`
- [ ] Playwright: **positive** sessionStorage-recovery assertion via hard `page.reload()`, not just
      a socket toggle `[testing]`
- [ ] Playwright: true network partition (`context.setOffline` / CDP) vs today's cooperative disconnect `[testing]`
- [ ] DataCase upload/asset orphan test mirroring `orphaned_blocks_test.exs` — nothing currently
      verifies uploaded rows are cleaned up on a failed or reset save `[testing]`
- [ ] Introduce a behaviour + Mox boundary for the S3/Mux/Bunny clients — no mock boundary exists
      today (no Mox/Bypass hits for uploads) `[testing]`
- [ ] Partial-failure multi-root block save (one root invalid, siblings valid) — untested at any level `[testing]`
- [ ] Replace fixed `waitForTimeout` (500-1500ms) in the block-recovery and multiuser-sync specs
      with event-driven waits — highest flake risk in the repo, per its own CI-timing note in `utils.js` `[testing]`

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
