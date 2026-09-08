# LiveView change-tracking audit — 2026-09-08

Audited revision: `dde6121a9a34eb2ea53345b77d2952963e307439`.
Phoenix LiveView: **1.2.11**, as pinned in both lockfiles and `mix.exs`.
This records the original audit before implementation. The fixes and regression
coverage are recorded in [FIXES.md](FIXES.md).

The main problems are stale state in reusable components, missing synchronization
across ignored DOM boundaries, and stream/DOM identity errors. The ordinary
`assign` pipelines are generally sound. Two shared wrappers explicitly discard
fine-grained tracking by spreading the entire assigns map into child components.

## Scope and verification

- Inventoried all 46 library LiveViews, 48 library LiveComponents, and nine E2E
  application LiveViews, including components reached through the shared form
  and listing macros.
- Parsed all Elixir source under `lib/` and `e2e/lib/` to locate HEEx sigils,
  including single-line sigils. Passed **601 templates** through the 1.2.11 HEEx
  compiler to AST. This is template analysis, not a complete application build.
- Examined shared function components, embedded layouts, Blueprint listing
  components, generated admin forms/listings/dashboard, and generator layouts.
  [COVERAGE.md](COVERAGE.md) records the file inventory, including supporting files
  found by the initial broad scan and 18 generator/template sources.
- Reviewed suspicious assign mutations, lifecycle initialization, component IDs,
  direct `assigns` access, local template bindings, render-time data loading,
  streams, and JavaScript-owned DOM. Inspected the surrounding handlers to check
  whether explicit refresh/recovery paths already compensate for these patterns.
- Ran **10 standalone ExUnit probes**, including functions extracted directly
  from the current RenderVar, PictureBlock, and VideoBlock source. All assertions
  passed; several deliberately assert the current incorrect behavior.
- Ran **seven DOM assertions** in isolated Chromium using the exact packaged
  LiveView 1.2.11 JavaScript bundle. They confirm stale presence rows and the
  ignored date/code editor boundaries. These are local fixtures, not application
  E2E tests. No database reset, consumer asset build, or full E2E suite was run.

The source inventory is comprehensive; runtime verification is targeted. A clean
inventory entry means no additional actionable issue was established by these
checks, not that every interaction in that module has been exercised.

## Findings

### F1 — P1: RenderVar retains stale media foreign keys after a parent update

**Location:** [render_var.ex:311](../../../lib/brando_admin/components/form/input/blocks/render_var.ex#L311),
with consumers at lines 845, 887, 928, and 974.

`assign_var_fields/2` refreshes `:var` and `:value` but initializes `:value_id`,
`:image_id`, `:file_id`, `:video_id`, and `:gallery_id` with `assign_new`. Those
keys already exist on subsequent updates, including when their value is nil.
Meanwhile, `refresh_asset_assign/5` correctly notices a changed parent FK and
refreshes the displayed asset. The card and its hidden input can therefore
disagree: the card can show the new asset while the input submits the old ID.

**Trigger:** update the parent var form for the same component ID, for example
through recovery, reset, or the owning block's replacement flow. This does not
require the var component's own picker handler, which separately updates its FK.

**Reproduced:** for each of image/file/video/gallery, update the parent FK from
11 to 22. The new form field and `:value` are 22; the corresponding cached FK
and `:value_id` remain 11. A subsequent form submission can restore the old
association or erase a newly supplied association if the cached value was nil.

**Correction:** derive the hidden-input FK from the current authoritative var
form on ordinary parent updates. Keep the one-shot upload/picker commit ordering
and expected-selection checks intact. Cover nil→ID, ID→different ID, and ID→nil
through parent updates as well as local picker events.

### F2 — P2: Picture and video ref components ignore replacement media

**Locations:** [picture_block.ex:103](../../../lib/brando_admin/components/form/input/blocks/picture_block.ex#L103),
[video_block.ex:133](../../../lib/brando_admin/components/form/input/blocks/video_block.ex#L133).

The normal update path accepts the new `ref_form`, but resolves its image/video
only through `assign_new`. The video component also retains `video_data`, `type`,
and cover-image state from the initial selection. Ref component identity remains
stable at [block/render.ex:1513](../../../lib/brando_admin/components/form/block/render.ex#L1513),
so the replacement does not cause initialization to run again.

**Trigger:** an owning Block receives `replace_form`, including a remote apply,
with a different media FK for an existing ref UID. That cascade updates Block
children and renders fresh ref forms; it does not remount these ref LiveComponents.
Local picker events have dedicated handlers, but do not cover this parent path.

**Reproduced:** the current normal update functions accept ref FK 22 while
retaining image/video 11; PictureBlock also retains `old.jpg` as its display name.
The UI and actions based on that cached asset can target the previous selection.

**Correction:** reconcile cached display media when the incoming ref's identity
or media FK changes, including reset to nil. Preserve the owning Block's deliberate
protection against unsolicited parent form replacement. Same-FK metadata refresh
and in-flight local commits need separate handling, rather than unconditional
reloading on every render.

### F3 — P2: Presence modal changes stream IDs and retains obsolete rows

**Location:** [chrome.ex:46](../../../lib/brando_admin/live/chrome.ex#L46), especially
the suffixed IDs on lines 48 and 53; stream resets are at lines 133–134.

The same presence streams render both avatars and modal rows. The modal changes
each supplied `dom_id` to `dom_id <> "_modal"`. LiveView's stream insert metadata
is keyed by the original ID, so those modal rows never receive a stream reference.
Normal stream-parent morphing preserves their children, while stream reset only
removes elements associated with the reset stream reference.

**Reproduced in Chromium:** render user 1 online, then reset the streams with that
user offline. The online avatar disappears correctly. The online modal row remains
and the offline modal row is added, showing the same user in both groups.

**Correction:** use separate modal streams with their own configured DOM IDs,
or retain a separate ordinary assigned collection for the modal. Use each stream's
provided DOM ID unchanged.

### F4 — P2: Date and datetime fields cannot receive server-side value changes

**Locations:** [input.ex:142](../../../lib/brando_admin/components/form/input.ex#L142),
[input.ex:166](../../../lib/brando_admin/components/form/input.ex#L166),
[DatePicker](../../../assets/src/hooks/DatePicker/index.js),
[DateTimePicker](../../../assets/src/hooks/DateTimePicker/index.js).

The actual named hidden input is inside `phx-update="ignore"`, together with the
Flatpickr-generated control. Neither hook has an `updated` handler or a current
value attribute outside the ignored subtree. Updating `@field`/`@value` on the
server therefore updates neither the browser's submitted value nor Flatpickr.

**Trigger:** restore or programmatically replace a form while retaining the field's
DOM ID. The failure applies even if the field has no focus.

**Reproduced in Chromium:** the server patch changes the hidden input from
`2026-09-01` to `2026-09-08`; its DOM value remains `2026-09-01`.

**Correction:** provide a tracked value on a patchable hook element and reconcile
Flatpickr through its API, including clear/reset. Ensure there is one authoritative
submitted input. Applying a server value should not dispatch a new user edit.

### F5 — P2: CodeEditor only synchronizes edits toward the server

**Locations:** [input.ex:65](../../../lib/brando_admin/components/form/input.ex#L65),
[CodeEditor:13](../../../assets/src/hooks/CodeEditor/index.js#L13).

The textarea is patchable, but CodeMirror's DOM is ignored. `mounted` reads the
textarea once; the hook has no update handler that applies a newly patched value
to CodeMirror. The application's remount registry contains TipTap, not this hook.
There is also a cleanup mismatch: `destroyed` calls `this.editor?.destroy()`, but
the created instance is stored in `this.view`.

**Trigger:** a server-side form replacement with the same editor ID, such as a
hard entry reset. The textarea can hold the replacement source while the visible
editor still holds the old document. The next editor transaction writes that old
document back into the textarea and sends an input event.

**Reproduced in Chromium:** textarea becomes `restored source`; ignored editor
content remains `old source`. Source inspection confirms the missing hook bridge.

**Correction:** reconcile server document changes in `updated`, with a guard that
prevents echoing them as local edits, and destroy `this.view` on removal.

### F6 — P2: Gallery configuration IDs collide across gallery fields

**Location:** [input/gallery.ex:266](../../../lib/brando_admin/components/form/input/gallery.ex#L266),
including child IDs on lines 282 and 292 and the matching open/close selectors.

Each gallery field renders the same `gallery-object-config-modal` DOM ID. Its
configuration LiveComponent ID is based only on object index, for example
`gallery-image-config-0`, without the owning gallery's ID.

**Trigger:** a form contains two populated gallery fields. Their modal DOM IDs
already collide. If configuration children of the same media type/index coexist,
their `{module, id}` identities also collide, even though their gallery owners
differ. Phoenix's component registry is scoped to the LiveView, not the nesting
position; it can reject duplicate component IDs. Modal JS selectors are ambiguous
before that point.

**Correction:** namespace modal IDs, child component IDs, and every matching
selector by the owning gallery component's stable `@id`. Keep the row index as
the row discriminator inside that namespace.

### F7 — P2: Entire-assign spreads disable tracking in shared render paths

**Locations:** [file_browser.ex:19](../../../lib/brando_admin/components/assets/file_browser.ex#L19)
(also 27, 35, 36), and
[block/render.ex:209](../../../lib/brando_admin/components/form/block/render.ex#L209)
(also 378).

`<.browser_top {assigns} />`, `<.browser_main {assigns} />`, and
`<.collection_children {assigns} />` cause the compiler to give those function
components `__changed__: nil`. Any relevant parent render evaluates their entire
dynamic contents. This is especially expensive for the recursive collection
wrapper and the shared browser used by all three media pickers.

The hot module rendering path also uses `assigns[:heex_compiled_module]` at
lines 905 and 956. That expression depends on the entire assigns map, so the
attribute is marked changed even when the compiled module did not change.

**Reproduced:** on an unrelated parent assign change, a spread child emits its
unchanged value again. An explicit-prop child is skipped; a direct function call
with the original assigns preserves the child's tracked dynamics.

**Correction:** pass explicit attributes. Where an internal wrapper truly needs
the exact same assign contract, a regular function call retaining the original
tracking map is an acceptable alternative. Replace optional map access with a
default assigned before HEEx and a named `@heex_compiled_module` dependency.

This is an avoidable-render-work finding. Descendant LiveComponents still perform
their own assign comparisons; the claim is not that every child remounts or that
the complete HTML is necessarily transmitted on every parent change.

### F8 — P2: Select option caches do not follow changed parent options

**Locations:** [select.ex:306](../../../lib/brando_admin/components/form/input/select.ex#L306),
[select.ex:330](../../../lib/brando_admin/components/form/input/select.ex#L330),
[multi_select.ex:568](../../../lib/brando_admin/components/form/input/multi_select.ex#L568).

The parent supplies fresh `opts`, but the regular update path uses `assign_new`
for `input_options`. Select recomputes its selected label against the old list.
The repository has genuinely dynamic callers: var choices at
[render_var.ex:815](../../../lib/brando_admin/components/form/input/blocks/render_var.ex#L815)
and datasource queries at
[module_props.ex:490](../../../lib/brando_admin/components/form/module_props.ex#L490).

**Trigger:** change labels/choices or the datasource query options while the
component retains its ID. Its selected label and an already-open option list can
remain stale. Both controls have explicit refresh paths; Select refreshes options
when opening, so this is not a claim that its list stays stale permanently.
Opening does not itself recompute the selected label.

**Correction:** invalidate derived options when their dependencies change. For
literal option lists, compare the old/new option specification; for callable
providers, define the form-field dependencies or an explicit refresh contract.
Retain deliberate lazy database loading. Do not replace every option read with a
database query on every keystroke.

### F9 — P2: Identifier picker caches outlive their filter inputs

**Location:** [select_identifier.ex:45](../../../lib/brando_admin/components/content/select_identifier.ex#L45),
with `assign_selected_schema/1` at lines 86–125.

`update` accepts fresh `wanted_schemas`, `language`, and `statuses`, but
`available_schemas`, workspace counts, and loaded identifiers are initialized
with `assign_new`. `sync_selection/2` refreshes the selected identifier only;
it does not refresh these result-set dependencies.

**Trigger:** reuse the picker after its parent changes link schema restrictions
or language. Link vars pass current schema restrictions from the changeset at
[render_var.ex:1143](../../../lib/brando_admin/components/form/input/blocks/render_var.ex#L1143).
The TipTap dialog also reuses a fixed child ID and passes its current language.
The existing result list/counts can describe the previous filters; selecting a
schema manually refreshes results, but not the cached schema choices/counts.

**Correction:** retain local selection state only while it remains compatible
with the new filter tuple. On a tuple change, rebuild available schemas/counts,
validate the selected schema, and reload its identifiers. Keep this separate from
refreshing solely because unrelated parent assigns changed.

## Smaller follow-ups

- Local bindings remain in `shared_library_live.ex:146–148`, `input/video.ex:421`,
  and `input/gallery/thumb.ex:44`. Move the calculations into named component
  assigns or helpers with explicit input dependencies. These are performance
  cleanup items, not evidence of stale UI. Ordinary `for`, `case`, and `:let`
  variables should not be flagged in the same way.
- `Input.color/1` loads a palette inside function-component execution
  (`input.ex:85–91`). Its `assign_new(assigns, ...)` is not a cache across separate
  function-component calls. `Render.ref/1` also resolves a module for footnote
  settings during rendering (`block/render.ex:1504,1570`). The latter uses a
  module cache, so it should not be described as an unconditional SQL query.
  Consider resolving these values at the owning state boundary and passing them
  explicitly; measure this after fixing F7.
- Generated frontend layouts repeat whole-assign spreads, and the generated
  dashboard uses `assigns[:authorization]`. Update the generator and E2E example
  together if their contracts become explicit. Controller-only layouts are not
  evidence of recurring LiveView patch overhead.
- The missing-block diagnostic branches directly read `assigns` and the fallback
  prints all assign keys. These low-frequency diagnostic paths are lower priority
  than F7's normal render path.
- `Input.Entries` also initializes `selected_identifiers` and available identifiers
  with `assign_new` (`input/entries.ex:65–96`). Its local selection handler maintains
  these lists, but parent replacement and `filter_language` changes warrant a
  focused regression check alongside F9. No separate end-to-end failure was
  established for this older picker during this audit.

## Patterns verified as intentional or correct

- No generic `Map.put/merge` mutation of the tracked rendering assigns was
  established in the ordinary LiveView/function-component paths. Map operations
  on changesets, event payloads, or intermediate maps are not the same problem.
  `HeexRenderer.render_to_string/3` deliberately produces a complete string;
  `Phoenix.HTML.Safe.to_iodata` evaluates its dynamics with tracking disabled.
- `Primitives.input/1` and `Render.dynamic_block/1` dispatch through
  `Phoenix.LiveView.TagEngine.component/3` with the existing assigns map.
  The helper preserves an existing `__changed__` key. These calls are not the
  same as HEEx attribute spreads and should not be mechanically rewritten.
- Block mount seeds and the intentional dropping of parent `:form`/`:children`
  after initialization protect local edits. The sanctioned `replace_form` path
  and the block op store must remain authoritative. F1/F2 concern descendants
  failing to consume a legitimate current form, not removal of that protection.
- Root and nested block collections already use stable UIDs and keyed
  comprehensions. Ordinary component IDs are generally stable; form IDs such as
  `var.id` on a `Phoenix.HTML.Form` are not database IDs merely because they use
  the property name `id`.
- Transformer list expansion reinserts the affected stream entry, so changes to
  `open_entries` reach streamed markup. FilePicker selection updates rebuild its
  visible stream. Image/VideoPicker use hook events for their client selection
  decorations. These paths already account for stream items leaving server memory.
- Presence locks use sticky JS classes/attributes. Injected field avatars live
  inside an ignored presence container; the focal-point pin is also ignored.
  Their plain DOM mutations should not be reported as unprotected decorations.

## Corrections to the repository guidance

`AGENTS.md` says a nil LiveComponent ID generates a random ID. In LiveView 1.2.11,
`Phoenix.Component.live_component/1` raises for nil. A valid changing ID does
create a different component identity; Brando also has its own random UID
fallbacks. Keep those three cases distinct.

Likewise, a function call with no assign dependencies directly inside HEEx is
normally skipped during tracked updates after the initial render. It is not
automatically evaluated on every patch. The recommendation to establish constant
options once remains useful, but the actual cost depends on dependency tracking,
function-component invocation, and whether a surrounding expression is tainted.
The standalone probes verify both of these points against 1.2.11.

## Phoenix sources consulted

The [assigns and HEEx guide](https://hexdocs.pm/phoenix_live_view/assigns-eex.html#common-pitfalls)
was the starting point. The audit used the exact cached Hex package source and
matching compiled 1.2.11 Elixir modules, rather than the older 1.0.18 dependency
found in a neighboring checkout.

- [engine.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.11/lib/phoenix_live_view/engine.ex):
  conditional dynamics, component tracking at lines 790–843, strong taint from
  `assigns`, and comprehension dependency tracking.
- [phoenix_component.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.11/lib/phoenix_component.ex):
  assign/assign_new and nil component-ID validation at lines 2201–2216.
- [tag_engine.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.11/lib/phoenix_live_view/tag_engine.ex):
  preservation of an existing `__changed__` map at lines 133–139.
- [utils.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.11/lib/phoenix_live_view/utils.ex):
  socket assign equality, first-write initialization, and changed-key bookkeeping.
- [diff.ex](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.11/lib/phoenix_live_view/diff.ex):
  `{component, id}` identity at line 867 and duplicate-ID validation at line 905.
- [dom_patch.ts](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.11/assets/js/phoenix_live_view/dom_patch.ts):
  ignored subtree handling at lines 408–417, stream insert/reset metadata at
  lines 508–522, and DOM-ID lookup at lines 694–707.
- [dom.ts](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.11/assets/js/phoenix_live_view/dom.ts),
  [js.js](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.11/assets/js/phoenix_live_view/js.js),
  and [view_hook.ts](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.11/assets/js/phoenix_live_view/view_hook.ts):
  attribute merging and sticky hook JS operations.

## Evidence

[reproduce.exs](reproduce.exs) is a standalone ExUnit probe. Run from the repository
root with the project's compiled dependencies on the code path, for example:

```sh
elixir -pa '_build/test/lib/*/ebin' docs/audits/liveview-change-tracking-2026-09-08/reproduce.exs
```

After implementation, this script retains the four Phoenix engine semantics
checks. The application state-update probes have been replaced by regressions
against the actual compiled components under `test/brando_admin/`. The original
10-probe results above describe the audited revision, before the fixes.

[browser-probe.cjs](browser-probe.cjs) runs the isolated DOM fixtures. See its
environment-variable inputs. [RESULTS.txt](RESULTS.txt) records the observed
outputs. Fixes should add appropriate regression coverage at the real owner/
component boundary, especially for parent-driven replacement and recovery.
