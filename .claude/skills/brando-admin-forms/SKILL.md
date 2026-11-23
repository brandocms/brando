---
name: brando-admin-forms
description: Change Brando admin form state collection, transformer delivery, save coordination, or reconnect recovery. Use for cross-component lifecycle bugs, not ordinary Blueprint form declarations or isolated input styling.
user-invocable: true
---

# Admin form state coordination

Paths are repository-relative. The parent changeset lives in
`lib/brando_admin/components/form.ex`; the public
`lib/brando_admin/live_view/form.ex` facade installs hooks through its compiler.
For form declarations, use `guides/blueprint_forms.md` instead.

`components/form.ex` is several thousand lines. Before reading it, find the
area in [the section map](form-map.md) and grep for the names it lists.

## Find the state owner before changing delivery

- Ordinary subforms update the parent changeset. Transformers own a stream and
  provide data during save collection. BlockFields own the ops store and
  materialize it for save/preview; read [blocks](../brando-blocks/SKILL.md) before
  changing that boundary. Do not reintroduce child-component block gathering.
- Follow `fetch_transformer_data`, `provide_transformer_data`, and
  `event_tag_received` through Form and
  `lib/brando_admin/components/form/transformer.ex`. Preserve already collected
  state: `assign_transformer_statuses` deliberately initializes only once.
  A transformer also loads its rows once; after a save that stays on the
  form, the Form hands it the rows its save wrote, as the save returned
  them (`written`), which make the rows it sent saved rows, so the next
  save doesn't insert them again; and the rows read back after the save,
  which also hold another editor's save that landed while this one ran
  (the Form takes none then): each item stores the row read back with its
  id (and shows the asset it names when that differs from the written
  one), and other ids are taken in as below. A card is drawn again only
  when its row was new or the row read back differs from the written one.
  After another editor's save (`take_saved_entry`), it hands it that save's
  rows (`entry_saved_elsewhere`): the transformer takes them under its own
  unsaved changes, told from the rows it was built on (`base_ids`).
  Updating a transformer row also requires `stream_insert`; changing an assign
  alone does not update the streamed DOM.
- Match delivery IDs to the rendered component: transformer IDs use the HTML
  form ID (`form.id`), not the enclosing Form component ID. Provider webhooks
  enter through `lib/brando_admin/live_view/form/hooks.ex`; local uploads alone
  do not exercise this path. The regression in
  `test/brando_admin/live_view/form/transformer_routing_test.exs` demonstrates the
  silent delivery failure when those IDs diverge.
- Top-level asset ids and galleries become server-owned once Form writes them
  (`own_asset/4`): the cast (`cast_entry_edit/4`, which `cast_entry_params/3`
  wraps for save) keeps their current value when params arrive, because the hidden inputs lag one render behind delivery. New writers
  of those fields must go through Form and mark ownership. Do not read them back
  from `validate` params. Coverage lives in
  `test/brando_admin/live/stale_validate_asset_race_test.exs`. A field the user
  may not change (`LockedFields`) is owned only with a value the server built
  (a translation's, a revision's working copy's, recovered or handed over
  too), and every writer checks
  `locked_field?/3` (`edit_asset_locked?/2` for a drawer) before writing it;
  a new writer does the same. Nor does a locked field ship to the other
  editors (`pending_changes`), who could save it
  (`locked_media_deliveries_test.exs`).
- Entry fields sync between editors as the fields each editor changed
  ("Entry field sync" in Form): `validate` marks the field `_target` names
  and other inputs whose value it changed; a change Form makes itself must
  go through `put_local_form/2` (or `put_written_form/2` when no browser
  event follows), or it never ships. Fields ship on focus, blur and save;
  a button or a drag sends neither, so every local subform op
  (`update_entries`: add, insert, a row's multi-select, the form builder's
  edits) ships at once, and so does a `validate` whose `_target` is a
  relation's drop or sort param (`row_control?/2`): a remove button, or a
  drag (`Brando.SortableEmbeds` dispatches on the moved row's
  `data-sort-input`). That param names the relation as the target, so a
  removal is never read as the browser's old form (`drop_echoes/4`). A
  `has_many` row never ships, and an
  `embeds_many` goes as one value: an editor in one of its rows holds the
  incoming list (`held_remote`) until they leave it, and if they changed a
  row, their list wins. A value the form's rich-text check
  refused (`Brando.RichText.refused?/2`, the field or a row) never ships,
  from `pending_changes` or from a recovery's `share_recovered/3`, and stays
  in `unshipped_fields` until corrected (a recovered one too), so another
  editor's save keeps it; the others still see it marked
  (`broadcast_dirty_fields`). Every path that puts values in the form
  without a `validate` runs the check first (`put_written_form/2`,
  `take_handed_over/3`), or `refused?` can't see them; a refused value goes
  to the editor's other tab with the uncast ones (`tab_release`), and a
  recovered one typed offline gets a clock of its own (`unsent_clocks`),
  never sent, so an older value in a late join reply doesn't replace it. Received values go through
  `apply_field_change/3`, which drops the browser's param for the field (the
  form shows a param before a saved value), and only when their clock is
  newer. Form recovery (`recover_form`) marks only the fields the Form hook
  lists as typed into offline (`__offline_edits`); other recovered values
  ship with the oldest clock (`share_recovered/3`), so any real edit beats
  them, and values already received from other editors stay. Coverage
  lives in `test/brando_admin/live/entry_field_sync_test.exs`.
- A save reaches the other forms of the entry as `{:entry_saved, …}`
  ("Saves by other editors" in Form): each reads the entry back without its
  blocks and rebuilds on it, keeping only its own unsaved fields
  (`unshipped_fields`, `synced_values` that differ from the save, and the
  has_many/has_one/many_to_many relations in `edited_relations`, marked
  when the editor changes them, never by another editor's multi-select),
  and moves its recovery baseline (`Drafts.rebase/2`; the blocks part when
  the block field reads the saved rows, `entry_blocks_reloaded`). A kept
  relation keeps the editor's rows whole (`RelationRows.keep/4`), with the
  saved values in rows it didn't change; rows are never merged. When the
  save changed that relation too, the form asks which to keep
  (`relation_conflicts`, `Form.SavedElsewhere`). The browser sends the rows
  it showed before until it has drawn the new ones: the form revision
  (`_form_rev`) tells, and such an event leaves the relation as the form
  has it (`stale_relations/2`): its params are dropped before the cast
  (`PendingRows.drop/3`), and a recovery capture copies the form's rows.
  A save that arrives while the form saves is taken once that save fails
  (`take_after_save`); one that arrives while the form asks to redirect
  the old address is in the entry its refresh reads back after the
  answer, as one in the gap of its save. On reconnect, each relation's base
  (`_relation_bases`, `RelationRows.base/2`: its rows in the entry the
  form is built on, read order left out, computed at render from
  `@entry`) tells whether its rows were saved otherwise meanwhile; if so,
  recovered rows that differ from the saved ones are a conflict
  (`settle_edit/4`). An unanswered conflict keeps its pre-take base
  (`conflict_bases`), so a reconnect asks again. A save of other fields
  or of other relations is not a conflict. A server-side value set at
  save reaches the others only this way. Coverage
  lives in `test/brando_admin/live/entry_saved_elsewhere_test.exs` and
  `test/brando_admin/components/form/relation_rows_test.exs`.
- A synchronized translation's pending version belongs to the entry's edit
  session (`Brando.EditSession.take_version/3`, `Data.version`), so the
  entry fields and the shared block fields load the same one. The Form
  decides only at mount (a reconnect too) and after its own save
  (`Form.Translation.decide/2`, from `action: :apply_translation`):
  `{:load, id}` loads it into the fields and every block field,
  `{:keep, id}` into the entry fields alone (the blocks are in the session).
  A parent update rebuilds the state on the held version and only notes a
  newer one (`waiting?`); never load a version there. Another form moving
  the session (`{:edit_session_version, …}`, routed by the hooks) makes this
  one take a version without changes or be `behind?`, which refuses the
  save. A form behind catches up in place (`catch_up_translation`,
  `Translation.catch_up/2`): it rebuilds on the saved entry without the
  editor's own unsaved entry fields (`discard_entry_edits`, shipping saved
  values for the ones it had shipped) and decides again as at mount. It does
  so by itself when the editor has none (`own_entry_edits`: `unsaved_edits`
  less received values, the held version's own and the last-editor stamp)
  and is in no entry field (`maybe_catch_up`, asked again on `"blur"`: a
  rich text commits after a pause), otherwise from the panel's button
  (`"load_session_version"`); never while the form saves or holds a
  working copy. Any version load keeps the values received from other
  editors (`keep_received`, so they don't ship back as this editor's) and
  records the replaced input values as the AI fill does, against a
  `validate` sent before the load reached the browser. A read-only client (no update permission, a tab that
  does not edit) shows a version without setting it; after a session crash
  the first form back puts its held version on the new session unless it
  is `behind?`. A form without block fields decides alone. Coverage
  lives in the "one pending version" describe of
  `test/brando_admin/live/translation_form_test.exs`.
- Read pending subform associations through the helpers in
  `lib/brando_admin/components/form/input/subform_helpers.ex`. Applying child
  changesets before rewriting the association loses pending edits. Use the
  append-changeset pattern in [brando-changesets](../brando-changesets/SKILL.md) and the
  component identity rules in AGENTS.md rather than inventing a second
  nested-form protocol.

## Recovery and verification

Rich-text inputs keep their hidden `.tiptap-text` input mounted from the start.
Ordinary form rich text mounts its editor immediately. Block-owned rich text
(text refs, block HTML vars/table cells, and block-slot content) initially renders
a sanitized display copy and creates the editor on click or keyboard activation. Never write that display copy back
to the input: untouched HTML must survive save and recovery exactly. Incoming
replacements update dormant previews and their inputs as well as active
editors. An entry form's rich text (a field, a subform row's field, a page
variable; not a block's) shows what its hidden input holds after each patch,
so a server write reaches a row's editor wherever the row has moved: write the
form, not an event addressed to the editor, whose DOM id follows the row's
position. Only an input in a form with `phx-change` is followed (a gallery
caption's popover input names no form; such an input is read on Save, so
after a patch it gets the editor's text back), and not during a rejoin: from
`disconnected()` the input keeps the editor's text, and `reconnected()` puts
in what the recovered form's patch left in it, changed or not (a text another
editor saved meanwhile is in the join patch, which renders the saved entry,
and the recovery keeps it), and follows that once. With only the join patch
in, nothing is put in: a recovered form that comes later is followed as any
patch. Once activated, an editor stays mounted to
retain undo history.
Open a dormant editor programmatically with `brando:tiptap:activate` on its hook
element, rather than assuming a `contenteditable=true` node already exists.

The main form and preview recovery form reconnect independently. Follow
`maybe_finish_live_preview_recovery/1` in Form and the
[live-preview skill](../brando-live-preview/SKILL.md) when both are involved.

Choose the regression matching the changed boundary:
`test/brando_admin/live/form_recovery_test.exs` for reconnects,
`test/brando_admin/components/form/input/subform_helpers_test.exs` for pending
nested edits, and the transformer routing test above for asynchronous delivery.
For browser verification, exercise an edit followed by an unrelated update,
save, and reload; a successful initial render cannot detect lost state. Follow
AGENTS.md for the consumer build and test commands, and
[uploads](../brando-uploads/SKILL.md) for media intake/delivery.
