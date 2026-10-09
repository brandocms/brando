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

Patching blocks into the page (`priv/static/js/block_patch.js`) is shared with
frontend edit mode (`priv/static/js/frontend_edit.js`, `guides/frontend_edit.md`),
whose sidebar form routes the same `update_block` and full-render requests to
the page in the parent window instead of a preview session
(`BrandoAdmin.Components.Form.FrontendEditor`). Check both when changing either.

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

## Coalesced updates

`Form.Preview` owns the pending preview timer, generation token and block-field
responses. It collects once per burst with a 25 ms minimum window, keeps the
earliest deadline, and chooses reload over body rerender over main update.
After a render the next one waits until 1 s has passed since it, so typing in
an entry field renders the first change at once and then at most once a second
with the latest state. An `update` broadcast carries only `<main>`, the only
part `livepreview.js` morphs; the cache keeps the whole document.
An edit during collection invalidates that generation and collects again;
late replies are ignored. Keep this accumulator separate from save/share.
Closing preview or switching targets cancels pending updates.

`Villain.RenderScope` memoizes source/context reads only during one synchronous
render, including nested refs and multiple block fields. Its keys include
tenant context, and cleanup runs even after failure. Preserve custom parser
source lists and the shared-library origin lookup. Module projections use the
existing module-list eviction namespace.

## Recovery is a two-event handshake

The main form's `validate` recovery and the hidden preview form's recovery can
arrive in either order. `maybe_finish_live_preview_recovery/1` waits for both
`form_recovered?` and `live_preview_recovery_pending?` before rendering. Starting
an iframe successfully does not establish that recovered unsaved inputs have
reached the server. Keep the recovery form outside the conditional preview pane
and avoid replacing the ignored iframe wrapper during ordinary patches.

Use `test/brando_admin/live/preview_updates_test.exs` for both preview recovery
arrival orders and `test/brando_admin/live/form_recovery_test.exs` for the wider
mounted-recovery harness.
Use `test/brando/live_preview/live_preview_test.exs` for rendering;
`test/brando/plugs/live_preview_test.exs` and
`test/brando_web/controllers/preview_controller_test.exs` for access and snapshots.
Browser cases in `e2e/playwright/tests/blocks/block-live-preview.spec.js` and
`e2e/playwright/tests/blocks/block-multi-live-preview.spec.js` cover unsaved
updates and nested modules. Follow AGENTS.md for test setup.
