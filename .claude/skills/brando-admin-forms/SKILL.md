---
name: brando-admin-forms
description: Work on Brando admin form loading, validation, saving, nested inputs, subforms, transformers, drafts, or form JS hooks. Route block state changes to brando-blocks and media intake to brando-uploads.
user-invocable: true
---

# Admin form lifecycle

Paths are repository-relative. Start at `lib/brando_admin/components/form.ex`;
`lib/brando_admin/live_view/form.ex` is the public LiveView setup facade, not the
owner of every field's state.

## Trace an edit

1. `lib/brando_admin/live_view/form/compiler.ex` installs runtime hooks from
   `lib/brando_admin/live_view/form/hooks.ex`. They establish the entry scope,
   subscriptions, asset delivery, and collaboration handling.
2. The Form component loads the Blueprint form and entry, resolves defaults and
   preloads, and owns the parent changeset. Field dispatch goes through
   `lib/brando_admin/components/form/fieldset/field.ex` and
   `lib/brando_admin/components/form/primitives.ex`.
3. Validation follows the real input name/path. Save collects component-owned
   state before running the context mutation. Search `fetch_root_blocks`,
   `event_tag_received`, and `provide_transformer_data` for that collection flow.
4. `assets/src/hooks/Form/index.js` handles browser-side form coordination,
   recovery, and preview interaction. Server state and recoverable browser
   snapshots have different lifetimes.

## State boundaries

- Keep component IDs stable across validation and parent renders. Nested DOM
  inputs use the form's identity/index rather than a nullable record ID.
- Ordinary subforms modify the parent changeset. Use `current_entries/2` and
  `put_entries/3` in `lib/brando_admin/components/form/input/subform_helpers.ex`:
  reading applied structs loses pending changes when the relation is rewritten.
- Transformers in `lib/brando_admin/components/form/transformer.ex` own a stream
  and collect their data at save time. Existing rows supply changesets; new rows
  supply maps. Stream item updates need `stream_insert`, not only an assign.
- `assign_transformer_statuses` initializes collection state once. Reinitializing
  it during unrelated parent updates can discard already collected edits.
- A custom form query owns its preload list. An unloaded relation is not an
  empty relation and should not be written back as one.
- Error display depends on changeset action and field usage. Test an invalid
  save and dismiss the error dialog before asserting underlying accessible inputs.
- Persistent browser decorations use the hook's sticky JS commands; ordinary
  DOM mutations are replaced by LiveView patches. See AGENTS.md.

## Verification and related skills

Use `test/brando_admin/live/form_recovery_test.exs` for mounted-form patterns and
`test/brando_admin/components/form/input/subform_helpers_test.exs` for pending
relation edits. Browser cases should exercise edit, unrelated update, save, and
reload. Follow AGENTS.md for the E2E consumer build and isolated test database.

Read [blocks](../brando-blocks/SKILL.md) before touching BlockField/reducer state,
[uploads](../brando-uploads/SKILL.md) for asset delivery, and
[live preview](../brando-live-preview/SKILL.md) for preview collection/rendering.
