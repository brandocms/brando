# Iron Law Violations Report (Pass 2 — remaining 9 files)

## Summary
- Files scanned: 9 (form.ex, block.ex, block/events.ex, block_field.ex,
  block_field/ops.ex, input/subform_helpers.ex, input/vars.ex, input/video.ex,
  subform.ex, pages/page_vars.ex)
- Iron Laws / conventions checked: Ecto changeset get_field vs get_assoc,
  put_assoc/put_change misuse, NotLoaded handling, raw/1 usage, inline styles,
  String.to_atom, import hygiene (partial pass, in progress)
- Violations found so far: 1 (HIGH)

## High Violations

### [Ecto: get_assoc, never get_field — Append Changeset pattern] `sequenced_subform` bypasses SubformHelpers
- **File**: `lib/brando_admin/components/form/subform.ex:372-413`
- **Code**:
  ```elixir
  def handle_event("sequenced_subform", %{"ids" => order_indices} = event_params, socket) do
    ...
    related_entries = get_change_or_field(changeset, field_name)
    ...
  end

  defp get_change_or_field(changeset, field) do
    with nil <- Ecto.Changeset.get_change(changeset, field) do
      Ecto.Changeset.get_field(changeset, field, [])
    end
  end
  ```
- **Confidence**: LIKELY
- **Detail**: `lib/brando_admin/components/form/input/subform_helpers.ex` has an
  extensive moduledoc explicitly warning that reordering/rebuilding a relation
  MUST go through `current_entries/2` (which dispatches to `get_assoc`/`get_embed`)
  and never `Ecto.Changeset.get_field/3`, because `get_field` returns applied
  structs — writing them back produces child changesets with no changes, so a
  row the user typed into but hasn't blurred silently reverts on save. This
  handler in `subform.ex` reimplements the read with a private
  `get_change_or_field/2` that falls back to `Changeset.get_field/3` instead of
  using `SubformHelpers.current_entries/2` (which the sibling `remove_subentry`
  handler in the same file correctly uses at line 351-356). This is the exact
  failure mode the module's own doc comment documents as a measured bug
  ("PENDING" case). Reordering a subform with unsaved edits on any row is at
  risk of dropping them.
- **Fix**: Replace `get_change_or_field(changeset, field_name)` with
  `SubformHelpers.current_entries(changeset, field_name)`, and route the write
  through `SubformHelpers.put_entries/3` instead of hand-rolled
  `put_embed`/`put_assoc` branching (lines 393-398), for consistency with
  `remove_subentry` and to keep the get_assoc/put_assoc pairing intact for
  assoc-backed subforms too (currently `sequenced_subform` uses
  `event_params["embeds"]` to branch put_embed/put_assoc based on a client-sent
  flag rather than `relation_kind/2`'s schema introspection — an extra
  divergence from the shared helper's already-correct logic).

## Notes / Lower-confidence observations (not filed as violations)

- `lib/brando_admin/components/form/block.ex:2207` — `entry |> Brando.Utils.try_path(var_path) |> raw()`
  renders admin-entered entry field content unescaped into a liquid-preview
  splits list. Content originates from the same admin's own entry, not
  cross-user untrusted input, so this is pre-existing/likely intentional
  (liquid template rendering) rather than a new XSS surface — flagged for
  awareness only, REVIEW confidence, not confirmed as part of this diff's
  added lines (could not isolate exact diff without `git diff` access — no
  Bash tool available in this session).
- `lib/brando_admin/components/form/block_field/ops.ex` reviewed in full —
  well-documented pure reducer; the only defect (`deep_merge_params/2` failing
  to merge list-shaped relation diffs) was already reported by a separate
  reviewer and is not re-reported here.
- `lib/brando_admin/components/form/block_field.ex` — extensive, consistent
  `get_assoc`/`put_assoc` pairing throughout observed call sites; no
  `get_field`-before-`put_assoc` misuse found in the sections reviewed.

## Caveat

This session has no Bash tool access, so `git diff HEAD~1` could not be run
directly to isolate exactly which lines were added vs. pre-existing in these
9 files. Findings above were derived from reading full file contents and
targeted grep for known risk patterns (get_field/get_assoc/put_assoc/NotLoaded,
raw(), String.to_atom, inline styles). Coverage of `vars.ex`, `video.ex`,
`page_vars.ex`, `block/events.ex`, and the HEEx-template portions of `form.ex`
and `block.ex` (constant-function-calls-in-template, stable component ids) was
partial at time of writing due to file size (form.ex is 6279 lines, block.ex
is 2711 lines) and turn budget.
