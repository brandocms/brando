---
name: brando-admin-forms
description: Change Brando admin form state collection, transformer delivery, save coordination, or reconnect recovery. Use for cross-component lifecycle bugs, not ordinary Blueprint form declarations or isolated input styling.
user-invocable: true
---

# Admin form state coordination

Paths are repository-relative. The parent changeset lives in
`lib/brando_admin/components/form.ex`; the public
`lib/brando_admin/live_view/form.ex` facade installs hooks through its compiler.
For form declarations, use `guides/blueprints.md` instead.

## Find the state owner before changing delivery

- Ordinary subforms update the parent changeset. Transformers own a stream and
  provide data during save collection. BlockFields own the ops store and
  materialize it for save/preview; read [blocks](../brando-blocks/SKILL.md) before
  changing that boundary. Do not reintroduce child-component block gathering.
- Follow `fetch_transformer_data`, `provide_transformer_data`, and
  `event_tag_received` through Form and
  `lib/brando_admin/components/form/transformer.ex`. Preserve already collected
  state: `assign_transformer_statuses` deliberately initializes only once.
  Updating a transformer row also requires `stream_insert`; changing an assign
  alone does not update the streamed DOM.
- Match delivery IDs to the rendered component: transformer IDs use the HTML
  form ID (`form.id`), not the enclosing Form component ID. Provider webhooks
  enter through `lib/brando_admin/live_view/form/hooks.ex`; local uploads alone
  do not exercise this path. The regression in
  `test/brando_admin/live_view/form/transformer_routing_test.exs` demonstrates the
  silent delivery failure when those IDs diverge.
- Read pending subform associations through the helpers in
  `lib/brando_admin/components/form/input/subform_helpers.ex`. Applying child
  changesets before rewriting the association loses pending edits. Use the
  append-changeset and identity rules already in AGENTS.md rather than inventing
  a second nested-form protocol.

## Recovery and verification

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
