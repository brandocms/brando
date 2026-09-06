---
name: brando-live-preview
description: Work on Brando preview target configuration, cached preview rendering, assign invalidation, iframe updates, share previews, or preview recovery. Use brando-blocks as well for block-state changes.
user-invocable: true
---

# Live preview

Paths are repository-relative. The current implementation is in
`lib/brando/live_preview.ex`; the target entity and Spark DSL are in
`lib/brando/live_preview/target.ex` and `lib/brando/live_preview/dsl.ex`.
Use the consumer's `e2e/lib/e2e_project_web/live_preview.ex` as a working example.

## Render and update flow

- Form's `open_live_preview` starts collection of the current entry, blocks, and
  transformers. `event_tag_received` initializes or updates the preview once
  that data is available; an unsaved entry must not be replaced with a DB reload.
- LivePreview prepares the entry, applies target preloads, computes cached
  assigns, applies `mutate_data`, renders block fields, builds a preview conn,
  and renders the target template inside its layout.
- Assign callbacks accept the entry or entry plus language. They see the
  preloaded entry before `mutate_data`. Their cache is separate from HTML;
  changing HTML alone does not recompute a cached listing/navigation assign.
- `rerender_on_change` requests a full render for configured field paths;
  `reassign_on_change` invalidates selected assign keys. Trace both the scalar
  form validation path and nested component update path for dependency changes.
- `initialize`, `update`, `rerender`, `reload`, and `share` have different
  transport semantics. `reload` keeps the cache key, so existing block-channel
  subscriptions continue to address the same preview.

## Browser and ownership contracts

- `assets/src/hooks/LivePreview/index.js` controls the split pane and device
  dimensions. The Form hook and preview channel/client manage content updates.
  Search the event names in both producer and consumer before changing payloads.
- Device viewport choices and rendered page/template targets are distinct
  concepts even where historical assigns use similar names.
- `lib/brando/authorization/preview.ex` registers ownership and checks reads,
  writes, and broadcasts. Keep these checks for updates and recovery as well
  as initial creation. A cache key alone is not an authorization decision.
- `cleanup_cache/1` removes HTML, ownership metadata, and cached assign values.
  Preserve cleanup when adding target-specific caches or switching behavior.
- Shared previews are persisted snapshots with export authorization; they must
  not silently inherit later edits from an active editing session.

## Verification

Start with `test/brando/live_preview/live_preview_test.exs`,
`test/brando/plugs/live_preview_test.exs`, and
`test/brando_admin/preview_controller_test.exs`. The browser fixtures are in
`e2e/e2e/playwright/tests/blocks/block-live-preview.spec.js` and
`e2e/e2e/playwright/tests/blocks/block-multi-live-preview.spec.js`.
Check unsaved changes, cached assigns, reload/recovery, and independent editors.
Read [blocks](../brando-blocks/SKILL.md) before changing block state or collection.
