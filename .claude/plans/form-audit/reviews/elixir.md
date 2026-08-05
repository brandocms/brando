# Code Review: commit 2c26cb31b (form-logic audit Phase 0)

## Summary
- **Status**: ⚠️ Changes Requested
- **Issues Found**: 4 (1 blocker, 1 warning, 2 suggestions)

## Critical Issues

1. **`ops.ex:765-769` (`deep_merge_params`) — child merge silently drops an
   earlier ref/var/table_row edit when the field's real diff shape is a LIST,
   not the index-keyed map the docstring (and its own test) assumes.**

   `changes_to_params/1`'s `change_value/1` clause for `is_list(value)`
   (ops.ex:805-809) is exactly what fires for `cast_assoc(:refs/:vars/:table_rows)`
   — Ecto's `changeset.changes[:refs]` is a **list** of nested changesets, not
   a `%{"0" => ..., "1" => ...}` map. `deep_merge_params/2` only recurses when
   *both* sides are maps (`is_map(old) and is_map(new)`); lists fall through
   to `deep_merge_params(_old, new), do: new` — replaced wholesale, same as
   `table_rows`.

   Concrete failure: on a **persisted child block**, round 1 edits `refs[0].description`
   → child changeset delta this round is `changes[:refs] = [ref0_cs(desc changed)]`
   (Ecto only includes entries that actually diverge from `data`, though when it
   *does* include the field it emits the whole current list — see caveat below).
   Round 2 edits `refs[1].image_id` on a **different** ref; since ref0's edit is
   now baked into round 2's `apply_changes/1` base (per the "child rebases on
   apply_changes" design), round 2's *local* delta for ref0 is empty — so the
   list this round is `[%{"id" => ref0_id}, %{"id" => ref1_id, "image_id" => 2}]`.
   `deep_merge_params` replaces the *previous* stored `"refs"` list (which had
   `description` on ref0) with this round's list wholesale — `ref0`'s
   `description` entry disappears from the merged diff entirely. At save,
   `Ops.materialize_child`/`materialize_root` reads this merged diff and casts
   it against the **real DB row**, so `description` never reaches SQL. Same
   mechanism applies to `vars` and (per the existing, accepted, test) `table_rows`.

   `ops_test.exs:88-95` ("CHILD merge is deep — a diff touching one ref keeps
   the other") passes today, but it hand-authors `%{"refs" => %{"0" => ...}}`
   as input — a shape `changes_to_params/1` never actually produces for a
   `has_many` assoc. The test doesn't exercise the real code path
   (`change_value(list)`), so it gives false confidence; `ops_test.exs:98-106`
   ("replaces lists wholesale") documents the real, lossy behavior for
   `table_rows` and — unnoticed — applies identically to `refs`/`vars`.

   Fix needs to either (a) key the stored ref/var/table_row diffs by their
   `"id"` (or `"uid"`) before merging, deep-merging entry-by-entry and
   re-flattening to a list at materialization, or (b) accept structural fields
   stay list-replaced but change the *emission* side so each round's diff is
   demonstrably a full, current snapshot of the sub-list (verify this is
   actually always true — if Ecto ever omits an untouched sibling from
   `changes[:refs]` instead of including it as an id-only entry, replace-wholesale
   loses it outright rather than just reverting it). Needs a regression test
   using a **real** `Ecto.Changeset` from `Block.block_changeset/3` across two
   `validate` rounds, not hand-built params.

## Warnings

1. **`ops.ex:798-803` (`change_value/1` doc comment is inverted).** The
   comment "embedded-schema changesets (no `__meta__`)... can't be partially
   cast by id-matching — snapshot their full applied state" sits directly
   above the clause matching `data: %{__meta__: _}` (i.e. **DB-backed**
   schemas — refs/vars/table_rows), which does the opposite: partial
   `changes_to_params/1` + `put_data_pk`. The full-snapshot behavior it
   describes is actually the *next* clause (`%Changeset{}` with no
   `__meta__`, i.e. genuinely embedded/polymorphic data). Purely a doc bug,
   but this module is the one place documenting the fragile changes-vs-data
   invariant everything else in this audit depends on — worth fixing before
   it misleads the next person touching `change_value/1`.

## Suggestions

1. **`ops.ex:742-748` (`stored_block_params/3`) has a dead `:entry_block`
   branch.** `merge?: true` is only ever passed from `apply_op({:update, ...})`
   for children, which always calls `register_params(..., :block, merge?: true)`
   — the `shape=:entry_block` clause of `stored_block_params/3` can never be
   hit. Harmless, but either drop it or add a root-merge caller to justify it.

2. **`page_vars.ex:139-157` (`sequenced_subform`) re-implements
   `SubformHelpers.sequenced_subform/2` inline** instead of calling it (as
   `vars.ex:121-123` does). It correctly uses `current_entries`/`put_entries`
   so it's not buggy, just duplicated — a future edit to the shared helper
   (e.g. another `get_field`-class fix) won't reach this copy.

## Verified correct (adversarial checks that did not find a bug)

- `events.ex` `restore_ref_media_params/2`: `Map.put_new` precedence is safe
  — DOM-rendered refs always carry all 4 FK hidden inputs unconditionally
  (`render.ex:1299-1302`), so params already have the key and `put_new` is a
  no-op; the restore only fires for refs carried identity-only via
  `carried_refs/1` (liquid-stripped, persisted-only), where the FK keys are
  genuinely absent. `String.to_existing_atom/1` is safe (hardcoded 4-item
  list, atoms already exist as schema fields). The `"id" => ""` (unsaved ref)
  case is a no-op by design: unsaved refs either carry every field via DOM
  (non-stripped) or are dropped entirely (documented "Known gap",
  `render.ex:1215-1223`, pre-existing/out of scope).
- `ops.ex` root-vs-child `{:update}` split (replace vs. deep-merge) matches
  the actual asymmetry in how the two `validate_block` clauses in `events.ex`
  compute their diffs (root rebases on `changeset.data` → cumulative;
  child rebases on `apply_changes/1` → delta) — correct as designed, modulo
  the list/map blocker above.
- `block_field.ex` `find_block_by_uid/2`: `Enum.find_value/2` correctly
  short-circuits per-sibling on a truthy return and falls through to the next
  sibling when a subtree search returns `nil`; a block with `NotLoaded`
  children hits the `is_list(children)` guard failure and falls to `_ -> nil`
  safely. No silent early-return found.
- `ops.ex` `materialize_child/2` vs `materialize_root/2`: both funnel through
  `materialize_block/4` and drop the same `"sequence"/"rendered_html"/"rendered_at"` render
  artifacts; `materialize_child`'s caller (`block_field.ex:263-281`,
  cross-parent move) supplies `sequence` out-of-band and the tree remains
  authoritative at final save, so omitting it here is correct, not an
  oversight.
- `content/block.ex` `ref_changeset/3`/`@var_attrs` FK list widening
  (`gallery_id` added) is consistent with the existing `image_id`/`video_id`/
  `file_id` trust model — no new castable field that shouldn't be
  client-settable.

## Pre-existing issues (not in scope, one-liners)

- `lib/brando_admin/components/form/block/events.ex:972` — fallback clause
  logs and `:cont`s on truly unknown events; fine, but silently swallows any
  future typo'd event name into a warning log rather than surfacing in dev.
