---
name: brando-villain
description: Work on Brando Villain rendering, Liquex/HEEx template adapters, custom parser callbacks, datasource output, render invalidation, refs, or composed footnotes. For editor state use brando-blocks.
user-invocable: true
---

# Villain rendering

Paths are repository-relative. Start with `lib/brando/villain/villain.ex`,
`guides/villain_parser.md`, and `guides/block_editor.md`. The renderer lives in the nested Villain directory.

## Rendering boundaries

- `Brando.Villain.parse/3` accepts entry-block rows and the current entry, builds
  context, dispatches nodes, composes HTML, and resolves footnotes at the render
  scope. `render_block/3` handles individual content blocks or their join rows.
- `lib/brando/villain/parser.ex` defines the parser behavior and defaults.
  Applications may override callbacks with `use Brando.Villain.Parser`; preserve
  existing callback compatibility when adding a block type.
- `lib/brando/villain/template_adapter.ex` defines the common engine contract.
  Implementations under `lib/brando/villain/template_adapter/` render modules,
  multi modules, children, and containers for Liquex or HEEx. A change to one
  adapter can leave the other engine broken even when the final HTML looks alike.
- `lib/brando/villain/context_cache.ex` provides identity, globals, and navigation
  to rendering. Template parse caches are not rendered-output caches; entry
  values and request/tenant context must remain specific to the current render.
  `parse_and_render_cached/2` caches constant templates without eviction; do not
  feed it a different template string on every request.
- `lib/brando/villain/render_invalidation.ex` recognizes references to shared
  render inputs. Both HEEx and Liquid syntax matter when invalidating dependants.

## Refs, datasources, and footnotes

- Read the concrete block under `lib/brando/villain/blocks/` before changing
  `apply_ref`: template synchronization must preserve intended content values
  and usage overrides. Exercise `test/brando/villain/blocks/ref_apply_test.exs`.
- Datasources use `lib/brando/datasource.ex`, its registry/invalidation modules,
  and Blueprint datasource entities.
  Use `guides/datasources.md` and the current callback signature; list, selection,
  and single sources do not have interchangeable input/return contracts.
- Footnote resolution occurs after the complete scope is composed. Resolving
  numbers or links independently inside child blocks breaks cross-block order.
- Preserve preview annotations and block/region boundaries when changing HTML
  wrappers. A static render can pass while incremental preview targeting fails.

## Verification

Use the relevant tests under `test/brando/villain/`, especially
`parser/dispatch_test.exs`, `template_adapter/heex_test.exs`,
`render_invalidation_test.exs`, `context_cache_test.exs`, and `footnotes_test.exs`.
Exercise both template engines when changing shared adapter contracts.
Read [blocks](../brando-blocks/SKILL.md) before altering editor/reducer state and
[live preview](../brando-live-preview/SKILL.md) for transport changes.
