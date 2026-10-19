---
name: brando-live-preview
description: Change Brando live-preview cache invalidation, update transport, editor-state collection, or reconnect recovery. Use for preview internals and lifecycle bugs, not routine application target/template configuration.
user-invocable: true
---

# Live-preview lifecycle

Paths are repository-relative. Follow the server in `lib/brando/live_preview.ex`,
the producer in `lib/brando_admin/components/form.ex`, and the consumers: the
admin hook `assets/src/hooks/LivePreview/index.js`, the channel
`lib/brando_admin/channels/live_preview_channel.ex` and the iframe client
`priv/static/js/livepreview.js`. Search an event name at both ends before
changing its payload.

Patching blocks into the page (`priv/static/js/block_patch.js`) is shared with
frontend edit mode (`priv/static/js/frontend_edit.js`, `guides/frontend_edit.md`),
whose sidebar form sends the same `update_block` patches to the page in the
parent window instead of a preview session, and turns a full render into one
replacement per block field (`BrandoAdmin.Components.Form.FrontendEditor`,
`update_block/1` and `replace_fields/3`). Check both when changing either.

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
  shared-link rules are documented in `guides/authorization.md` ("Live previews
  and activity"); preserve the update/recovery checks in
  `Brando.Authorization.Preview` (`authorize_update/2`, `authorize_write/2`).

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
existing module-list eviction namespace
(`Brando.Villain.RenderSourceQuery.get_module/2`).

## Recovery is a two-event handshake

The main form's `validate` recovery and the hidden preview form's recovery can
arrive in either order. `maybe_finish_live_preview_recovery/1` waits for both
`form_recovered?` and `live_preview_recovery_pending?` before rendering. Starting
an iframe successfully does not establish that recovered unsaved inputs have
reached the server. Keep the recovery form outside the conditional preview pane
and avoid replacing the ignored iframe wrapper during ordinary patches.

## What the iframe shows

The iframe joins with the generation of the cache it shows
(`livePreviewVersion`, then each render's `v`) and the block patches applied
over it (each `update_block`'s `p`); `LivePreview.page_state/1` holds both.
`store_cache/2` starts a new generation unless the HTML is unchanged with no
patch since. The channel replays the cache when the generation differs.
Patches are not in the cache, so when the iframe is behind, the channel calls
`report_lost_patches/1`; the form ignores it while recovery is pending. The form
subscribes to `form_topic/1` while its preview is open
(`put_live_preview_key/2`), and `LiveView.Form.Hooks` routes the report back to
it: the form renders the whole page and pushes the drawer's notice. A render
the iframe already shows is not sent (`send_render/3`); a patch forgets what
was sent, so the next render goes out.

Use `test/brando_admin/live/preview_updates_test.exs` for both preview recovery
arrival orders and `test/brando_admin/live/form_recovery_test.exs` for the wider
mounted-recovery harness.
Use `test/brando_admin/components/form/preview_test.exs` for coalescing and
`test/brando/live_preview/sends_test.exs` for skipped sends and patch counts.
Use `test/brando/live_preview/live_preview_test.exs` for rendering;
`test/brando/plugs/live_preview_test.exs` and
`test/brando_web/controllers/preview_controller_test.exs` for access and snapshots.
Browser cases in `e2e/playwright/tests/blocks/block-live-preview.spec.js` and
`e2e/playwright/tests/blocks/block-multi-live-preview.spec.js` cover unsaved
updates and nested modules. Follow AGENTS.md for test setup.
