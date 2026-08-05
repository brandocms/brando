# LiveView follow-up review — commit 2c26cb31b (gap items only)

## 1. `subform.ex` — schema-based dispatch (`SubformHelpers`) vs old assign-based dispatch

**Consistent for all relation types currently used.** `SubformHelpers.relation_kind/2`
dispatches on `module.__schema__(:association, field_name)` (truthy → `:assoc`,
else `:embed`). Checked every Blueprint relation type that reaches a subform
(`has_many`, `many_to_many`, `belongs_to`, `entries` — all real Ecto
associations, so `__schema__(:association, ...)` is truthy → `:assoc`;
`embeds_many`/`embeds_one` are not associations → `:embed`). This matches the
old `assigns.embeds?`, which was `true` only for blueprint `type:
:embeds_many` and `false` otherwise (`subform.ex:66-73`, pre-diff logic
preserved as a separate assign, see below).

**WARNING — two dispatch mechanisms now coexist, un-unified.**
`update_subentry`/`add_subentry`/`remove_subentry` (subform.ex:20-41, 313-343,
345-366) were moved onto `SubformHelpers.current_entries/put_entries`
(schema introspection). `sequenced_subform` (subform.ex:372-407) was **not**
moved — it still branches on `embed? = event_params["embeds"]`, a boolean
threaded from the client via `data-embeds={@embeds?}` (subform.ex:150), which
is computed from the *Blueprint relation type*, not the schema. Both happen
to agree today because every existing relation type maps 1:1 between
Blueprint type and Ecto schema kind. But this is now two independent sources
of truth for the same assoc-vs-embed question, one server-authoritative
(schema), one client-round-tripped (DOM attribute → JS event payload). If a
subform's `data-embeds` attribute goes stale after a `send_update`-triggered
re-render races the in-flight drag event, `sequenced_subform` could receive
a stale `embeds` flag and call `put_assoc`/`put_embed` on the wrong branch,
raising `Ecto.Changeset` errors. Recommend routing `sequenced_subform`
through `SubformHelpers` too (it already exists as
`SubformHelpers.sequenced_subform/2`, unused by `subform.ex`) for one source
of truth, matching page_vars.ex's own `sequenced_subform` (which does *not*
use the shared helper either — see #2).

**Edge case, no known live instance:** if `field_name` is neither a schema
association nor a schema embed (a subform name with no backing Ecto field),
`relation_kind/2` still returns `:embed` (its `else` branch), and
`Changeset.get_embed/put_embed` will raise `ArgumentError` rather than a
Brando-specific error. Old code's `embeds?` defaulted to `false` in the same
situation, so the old dispatch would have raised via `put_assoc` instead —
different exception, same crash. Not a regression, just unfriendly either way.

Nothing else in the diff reads `socket.assigns.embeds?`/`socket.assigns.relations`
besides the `data-embeds` DOM attribute and `Form`/`Fieldset` passing
`relations` straight through as a prop (`form.ex:2302`, `fieldset.ex:25`,
`fieldset/field.ex:69`) — unrelated to write-dispatch.

## 2. `page_vars.ex` — BLOCKER: `sequenced_subform` reads a non-existent assign

`page_vars.ex:141` reads `socket.assigns.form.source`. `PageVars` is invoked
by `fieldset/field.ex:36-48` as a custom subform component and is passed
`field={@form[@input.name]}` — **no `form=` prop is ever passed.** `PageVars`
has no `update/2` and no `assign_new(:form, ...)`; its `mount/1` only sets
`:advanced`. So `socket.assigns.form` does not exist on this LiveComponent.
Every drag-reorder in the PageVars "advanced" mode (the `Brando.SubFormSortable`
hook firing `"sequenced_subform"`) will raise `KeyError` inside
`handle_event/3`, crashing the parent LiveView (an unhandled exception in a
live_component's handle_event kills the owning LiveView process, blanking
the admin form for the user).

This is exactly the split the task description warned about: `add_subentry`
(via `SubformHelpers.append_subentries/2`) and `remove_subentry` (via
`SubformHelpers.remove_subentry/2`) correctly read `socket.assigns.field.form.source`
inside the shared helper. `sequenced_subform` was left as bespoke inline code
still reading `socket.assigns.form.source` — the wrong (nonexistent) binding.
Fix: change `page_vars.ex:141` to `socket.assigns.field.form.source` (or route
through `SubformHelpers.sequenced_subform/2`, which already does this
correctly and is currently unused by this file).

`SubformHelpers.update_form/4`'s derived `form_id` (`"#{module.__naming__().singular}_form"`
from `changeset.data.__struct__`) is otherwise correct and matches the old
inline construction exactly, for every handler that reaches it — the only
defect is the wrong changeset source at line 141, not the form_id logic
itself.

## 3. `form.ex` `commit_selected_asset/3` — other senders (IN PROGRESS)

Confirmed guard: `commit_selected_asset(socket, %{field: field}, asset) when
not is_nil(field)` fires unless `edit_asset[:block_target]` is set
(form.ex:1177-1185). All three `:update_edit_*` receiving clauses
(form.ex:180-191 file, 217-231 image, 289-302 video) call it identically:
merge `updated_edit_*` then `commit_selected_asset(updated_edit_*, asset)`.

Established so far: `select_video` (input/video.ex) was already verified
correct by the earlier pass. Not yet independently re-verified against this
guard: `duplicate_image`, `save_image`'s block path, `input/image.ex:319`
(`select_image`), `input/file.ex:197` (`select_file`).

## Not investigated

- `form.ex` `handle_event("duplicate_image", ...)` — whether the `image:`
  it sends via `:update_edit_image` carries a `field` (so the guard fires)
  and whether firing `commit_entry_field_asset` here double-commits against
  whatever `duplicate_image` itself already writes to the changeset/DB.
- `form.ex` `handle_event("save_image", ...)` block path — task states this
  send is only reached "inside `if block_target`"; if so the
  `commit_selected_asset` guard's `block_target` short-circuit should already
  no-op it, but this was not confirmed by reading the actual send site
  (only the two `:update_edit_image` send sites at form.ex:3453/3543 were
  located, not yet read in context).
- `input/image.ex:319` (`select_image`) — not read; unverified whether
  `field`/`block_target` are populated the same way `select_video` populates
  them, and whether `ship_all_field_changes()` here could broadcast a
  picker selection to other connected editors before the user confirms via
  the drawer's close button (the documented old failure mode this commit
  fixes, per the comment at form.ex:1169-1173) — need to confirm it can't
  now double-fire (once from picker select, once from drawer close).
- `input/file.ex:197` (`select_file`) — same, not read.
- Whether `ship_all_field_changes()` firing from `update/2` (component
  process, not `handle_event`) for these picker paths could interleave with
  a concurrent `handle_event` on the same component in a way that ships a
  half-built changeset — not analyzed.
