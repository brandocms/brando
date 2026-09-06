---
name: brando-live-preview
description: Change Brando live-preview cache invalidation, update transport, editor-state collection, or reconnect recovery. Use for preview internals and lifecycle bugs, not routine application target/template configuration.
user-invocable: true
---

# Live-preview lifecycle

Paths are repository-relative. Follow the server in `lib/brando/live_preview.ex`,
the producer in `lib/brando_admin/components/form.ex`, and the consumer in
`assets/src/hooks/LivePreview/index.js` plus the preview channel/client. Search
an event name at both ends before changing its payload.

## Preserve render and cache ordering

- Form requests materialized BlockField state before initializing a block
  preview. Keep the current unsaved entry; loading the persisted entry again
  discards the edit being previewed. Read [blocks](../brando-blocks/SKILL.md)
  before changing block ownership or collection.
- Target preloads run before cached assign callbacks; `mutate_data` runs after
  those callbacks. An assign that needs a relation must receive it through
  `schema_preloads`. A mutation cannot prepare input for an earlier callback.
- Assign values and rendered HTML have separate caches. Updating HTML alone
  does not refresh an assign. Trace `reassign_on_change` through scalar and
  nested-field update paths, and invalidate affected keys before rendering.
- A new template or newly introduced frontend behavior may need `reload`, not
  an HTML morph. Keep the preview key when reloading so existing block-channel
  subscriptions remain valid. Device viewport controls and template targets
  are separate choices.
- Extend `cleanup_cache/1` whenever adding session cache data. Ownership and
  shared-snapshot rules are documented in `guides/authorization.md`; preserve
  its update/recovery authorization checks.

## Recovery is a two-event handshake

The main form's `validate` recovery and the hidden preview form's recovery can
arrive in either order. `maybe_finish_live_preview_recovery/1` waits for both
`form_recovered?` and `live_preview_recovery_pending?` before rendering. Starting
an iframe successfully does not establish that recovered unsaved inputs have
reached the server. Keep the recovery form outside the conditional preview pane
and avoid replacing the ignored iframe wrapper during ordinary patches.

Use `test/brando_admin/live/form_recovery_test.exs` as a mounted-recovery
harness; when changing this handshake, cover both arrival orders explicitly.
Use `test/brando/live_preview/live_preview_test.exs` for rendering;
`test/brando/plugs/live_preview_test.exs` and
`test/brando_admin/preview_controller_test.exs` for access and snapshots.
Browser cases in `e2e/e2e/playwright/tests/blocks/block-live-preview.spec.js` and
`e2e/e2e/playwright/tests/blocks/block-multi-live-preview.spec.js` cover unsaved
updates and nested modules. Follow AGENTS.md for test setup.
