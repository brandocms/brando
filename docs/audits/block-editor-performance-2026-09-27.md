Performance opportunities in the block editor, rendering and live preview — 2026-09-27

Initial audit reviewed commit `8c650905b`. Items 1–3 have now been implemented
and validated; the original findings below describe that baseline. Large-editor
mount cost is addressed separately below with deferred rich-text editor mounting.

**Implementation and validation**

- Blocks no longer render discarded HTML when enabling preview, receiving entry
  updates or receiving ordinary parent props. Validation skips local HTML when
  slots require a full refresh or media changes require an iframe reload.
- `Form.Preview` coalesces full-preview requests before collecting state, with a
  25 ms minimum window, the earliest deadline and reload/rerender/update
  precedence. Generation tokens reject stale replies. Its accumulator is
  separate from save/share; both recovery arrival orders retain unsaved input.
- `Villain.RenderScope` reuses source lists and context reads for one synchronous
  render, including nested refs and multiple block fields. It includes tenant
  context in keys and releases inputs on success or failure. Custom parsers keep
  their full source-list contract. Local module lookups cache individual
  projections using the existing module-list eviction namespace; cold fills
  reuse the library cache, avoiding per-module preload queries. Tenant library
  origin resolution remains in `SharedLibrary`.

Fresh before/after comparisons used the same read-only restored BY harness,
three warmups and 31 samples in fresh processes. The baseline loaded original
source from `8c650905b`; the comparison used the final implementation. Entry
loading was outside the timer, render caches were warm, and GC ran before each
sample. Times below are medians; these isolated server stages cannot be added
to predict browser latency.

| Case | Full preview, before → after | Root-only preview enable, before → after | Warm root module lookups, before → after |
| --- | ---: | ---: | ---: |
| 63, 57 roots | 9.37 → 6.99 ms | 5.66 → 0.07 ms | 3.63 → 0.39 ms |
| 57, 41 roots | 9.42 → 6.12 ms | 15.49 → 0.05 ms | 2.26 → 0.33 ms |
| 1, 30 roots | 4.89 → 4.12 ms | 10.94 → 0.04 ms | 2.13 → 0.26 ms |

Full-preview query-cache reads fell from 260/164/128 to 7 per render, measured
separately with the profiler. This counts cache lookups, not SQL. Normalized
HTML matched on all three pages. Root-only enable excludes child propagation,
LiveView diffs and transport. The 25 ms coalescing window adds a small delay to
individual full-refresh requests; a burst of 12 requests is covered by a test
asserting one collection per field and one render.

Cold lookup batches also improved: 6.22 → 3.55, 4.20 → 1.90 and 3.15 → 1.98 ms
for the same three entries (11 samples, module caches evicted before each).
The cold-cache regression test asserts that a second distinct module requires
no extra SQL after the library is loaded.

Validation passed:

- Focused Elixir suites for preview scheduling, block rendering, cache eviction,
  tenant scope, parser overrides, slots, footnotes, HEEx, shared libraries,
  preview targets and mounted form recovery.
- 33 browser tests: basic and multi-module preview (22), Liquid/HEEx region
  reactivation (4), and reorder/persistence/node preservation (7).
- Compilation, formatting and whitespace checks.

Tests used isolated databases. The existing E2E database had an outdated schema;
browser validation used a fresh `preview_perf_20260927` instance. No JS/CSS was
changed for items 1–3. Those measurements do not claim an end-to-end editor-load speedup.

**Deferred TipTap mounting (item 4)**

Block-owned rich text now starts as a formatted preview with a localized Edit
text button. Ordinary form rich-text fields still mount immediately; only text
refs, HTML variables/table cells within blocks, and block-slot content defer their
editor. The preview uses a compact edit control alongside the formatted text.
Clicking its text or activating the button with the keyboard mounts that field's
editor. Existing footnote markers open their notes directly; explicitly opening
a note drawer activates its first text field. Activated editors stay mounted
when blurred, preserving undo history.

The hidden input remains in its original form throughout. The preview sanitizes
a display copy only; it never writes that copy back to the input. Tests compare
untouched HTML byte for byte after an unrelated edit, save and reload. Typing
continues to update the input synchronously through the existing TipTap handler.
Remote replacement events and LiveView patches update dormant previews too.

The isolated browser fixture initialized 155 formatted previews in 32–36 ms
(2,635 fixture DOM elements), with the first activation taking 26–27 ms. These
are illustrative local runs, not a before/after page-load benchmark. The
regression asserts zero editor instances initially and exactly one after
activation; it also checks that the other 154 input values remain untouched.
The full application retains its block forms, server components and TipTap
JavaScript bundle; this change saves editor instance/toolbars/plugin work,
not those other costs.

In the E2E consumer, a saved test entry with one block containing 155 rich-text
refs opened in 2,047 ms (navigation through LiveView readiness): 12,050 DOM
elements, 155 hidden inputs and zero editor instances. Activating its first
field created exactly one editor. This is a synthetic large-entry smoke check,
not a before/after timing of the restored BY entries.

Validation passed the consumer asset build, TipTap component regressions and
27 focused E2E cases across the runs above. Coverage includes
byte-for-byte untouched saves, immediate saves after typing, keyboard activation,
English/Norwegian labels, desktop/mobile layout, concurrent updates into both
dormant and active editors (including the receiver's save), late joiners,
footnote opening/numbering/media/recovery, nested rich-text fields and
Liquid/HEEx live-preview regions, page/project creation and link-picker controls.
Screenshots are in
`docs/admin-ui/block-text-preview-{en,no}-{1440,390}.png`,
`rich-text-regular-desktop.png`, `project-media-fields-1440.png` and
`rich-text-blocks-desktop.png`.

The follow-up scope check verifies that ordinary form rich text mounts immediately,
while a block-owned HTML variable remains dormant. Block preview save/reload and
keyboard editing pass in English and Norwegian. The gallery and Related entries
fields now share the image/video field layout; browser checks cover gallery uploads
and configuration, clearing persisted related entries, saving, selecting them again,
and retaining other field values. Desktop and mobile screenshots are in
`docs/admin-ui/project-media-fields-{1440,390}.png` and
`related-entries-{selected,norwegian}-{1440,390}.png`.

Recovery coverage distinguishes LiveSocket rejoin from a real network partition.
The rejoin test preserves edits, including input entered while disconnected.
The real-network-loss probe reproduced the existing hard-reload gap documented
in `block-recovery.spec.js`: the page can reload from saved content instead of
recovering the in-memory form. This change does not fix that broader lifecycle
issue or add collaborative edit flags.

**Original audit measurements and findings**

Fresh measurements used the existing read-only `bench/liquid_rust/by/preview_boot.exs`
harness and restored BY cases. Each timing has three warmups and 21 samples in
fresh processes, with GC before timing and ordinary GC during timing included.
Entries, preview assigns and render caches were warm; entry loading was outside
the timer. The root pass invokes the existing `Block.maybe_render_module/1` on
root component sockets. It measures the rendering work that preview enable
requests, excluding LiveView message delivery, child-component enable messages,
HEEx editor diffs, transport and browser work. These independently measured
stages must not be added to predict user-visible latency.

| Restored case ID | Roots | Full `LivePreview.render/4`, median | Additional root render pass, median |
| --- | ---: | ---: | ---: |
| 63 | 57 | 9.21 ms | 5.97 ms |
| 57 | 41 | 9.45 ms | 18.20 ms |
| 1 | 30 | 4.62 ms | 10.62 ms |

Both timed render paths issued **zero SQL queries** in a separate telemetry
capture on each case. This does not cover newly selected media or cold caches.
Profiling ran separately from timings. The E2E application was not running;
no fresh end-to-end editor latency or payload measurement is claimed here.

1. **Remove preview renders whose HTML is never delivered. High priority;
   relatively contained scope.**

   Opening preview first renders the full page in
   [Form.event_tag_received/2](../../lib/brando_admin/components/form.ex:2077),
   then enables every block. [Block.update/2](../../lib/brando_admin/components/form/block.ex:442)
   responds by rendering again through `maybe_render_module/1`. The new HTML is
   assigned to each block form but is not broadcast by that handler.

   There are two more instances of the same issue. Entry-field validation sends
   updates to consuming blocks and requests a full preview. Each
   [update_entry_field handler](../../lib/brando_admin/components/form/block.ex:884)
   calls `render_module/1`, although the full-page render supplies the preview
   HTML. And [block validation](../../lib/brando_admin/components/form/block/events.ex:768)
   renders before [maybe_update_live_preview_block/1](../../lib/brando_admin/components/form/block.ex:2253)
   decides that slots and single modules with children require a full refresh.
   Those local render results are discarded too.

   Select the required transport before rendering. Enable should normally set
   preview state; entry updates should refresh editor-facing splits; render
   individual HTML only when sending an incremental block update. Guard the
   generic `Block.update/2` call to `maybe_render_module/1` as well: currently a
   parent prop update can render a root with no content change. Preserve the
   independent HEEx editor preview and force-render behavior on reactivation.

   The measured extra root pass above makes this the clearest demonstrated
   server opportunity. Verify opening preview, entry-field edits, slot edits,
   reorder and reactivation with renderer call counts and unchanged output.

2. **Coalesce full-preview requests before collecting state. High priority;
   medium scope.**

   [update_live_preview](../../lib/brando_admin/components/form.ex:544) schedules
   [fetch_root_blocks](../../lib/brando_admin/components/form.ex:4710) at delay
   zero. Each request can materialize/cast every root, render all block fields,
   render the page/layout, store HTML and broadcast the full document. The
   delayed full-rerender path also schedules work without retaining a timer or
   request generation. A delay alone is not debounce.

   Use one pending preview generation per form, with an explicit transport
   precedence (`reload`, body rerender, main update) and bounded coalescing.
   Collect the latest op-store state once when it fires. Keep save/share and
   recovery coordination separate, preserve assign invalidation ordering, and
   reject obsolete results if rendering later moves to a task.

   The iframe's [full update handlers](../../priv/static/js/livepreview.js:487)
   parse a complete document and perform several whole-document passes:
   block-key stamping, media initialization and registry rebuilding. Coalescing
   avoids that work as well. Afterwards, scope passes to the morphed region and
   consider carrying only `<main>` for main-only updates while retaining full
   cached HTML for reloads. Ordinary `update_block` already uses its registry;
   it does **not** rescan the whole document on every successful lookup.

   Burst amplification is established by the scheduling path, not quantified
   by this audit. Measure render count and iframe update count during bursts
   before selecting a coalescing interval. Preserve keyed video/iframe nodes.

3. **Retrieve only the render definitions needed, and reuse context within a
   render batch. Medium to high priority; medium scope.**

   [Villain.render_block/3](../../lib/brando/villain/villain.ex:118) builds base
   context and copies the entire module list for each module block.
   [Content.fetch_module/2](../../lib/brando/content.ex:245) also reads the full
   list during component initialization and outline construction.
   [find_module/3](../../lib/brando/content.ex:206) then searches it linearly.
   Existing type-specific source loading is useful, but still copies every
   module when just one or a few are needed.

   Separate profiling of the root passes recorded 79, 59 and 42 calls to
   `RenderSourceQuery.list_modules/1` for the three cases. These include rendering
   reached through the site's parser. Query count remains zero because the
   lists are cached; copying and processing cached terms still costs CPU and
   allocation.

   A lookup cache keyed by tenant/library origin/module ID and revision can
   avoid copying unrelated definitions. Batch rendering should obtain one
   context and one source index rather than rebuilding them per block. Merely
   converting the whole fetched list into a map per block does not solve the
   copying cost. Preserve mutation-driven eviction, shared/local identity,
   parser overrides, and target/language/request context.

   A related smaller opportunity is [multi_module/5](../../lib/brando/villain/parser.ex:337):
   children are processed for their individual rendering, then vars/refs are
   processed again for `entries`. Even `skip_children: true` builds the
   `entries` projection. Reuse prepared child values; omit the projection only
   when the template demonstrably does not consume it. Templates may legally
   read `entries`, so skipping it unconditionally would change behavior.

4. **Reduce rich-text mount work and block-form diff size. Potentially high
   impact on large entries; needs a fresh browser baseline.**

   Collapsed blocks are hidden with
   [CSS](../../assets/css/components/Form/Input/Blocks/Block.css:217); their
   forms and rich-text editors still mount.
   [TipTap.mounted](../../assets/src/hooks/TipTap/index.js:14) creates the Svelte
   component/editor immediately. Start by deferring rich-text editor creation
   for collapsed/offscreen bodies while retaining the raw form input. This can
   reduce editor initialization without first redesigning all form recovery.
   Full body virtualization is a larger subsequent option.

   [module_content](../../lib/brando_admin/components/form/block/render.ex:1111)
   also renders an unkeyed `liquid_splits` comprehension containing ref inputs.
   Use stable split identity, and separate value dependencies from stable form
   metadata where possible. Stable keys alone will not prevent diffs if every
   subtree still receives a changed form.

   Preserve DOM-backed invalid input, pending debounce flushes, drafts,
   reconnect recovery, focus, drag/outline scrolling and remote updates. Never
   simply remove hidden fields: association casting relies on carried values.
   Config chrome is already lazy, and TipTap accessibility updates already
   avoid unconditional `setOptions`; neither should be proposed as new work.

   The September 13 audit is historical evidence of mount/layout costs, not a
   current timing baseline. Re-run the 5/40/115-block and heavy rich-text mount
   probes before projecting savings.

5. **Batch footnote numbering per block field. Medium priority; small scope
   for the client portion.**

   [renumberFootnotes](../../assets/src/components/TipTap/extensions/Footnote/index.js:13)
   scans every marker in `.blocks-wrapper` and rewrites text and attributes.
   Each editor schedules it on mount; editors with notes call it on hook
   updates; [TipTap.onUpdate](../../assets/src/components/TipTap/TipTap.svelte:177)
   calls it on every content edit. Multiple editor callbacks repeat the same
   work within one field.

   A fresh Chromium microbenchmark using the actual function, 155 synthetic
   editors, 600 span elements/editor and one note/editor measured **52.0 ms**
   median for 155 calls versus **0.3 ms** for one call. With no notes the work
   was negligible. This is a function benchmark, not a measured LiveView patch
   or a reproduction of editor mounting.

   Queue one pass per scope per frame, write only changed numbers/labels, and
   invalidate for insertion/removal/reorder rather than every text edit.
   Retain numbering updates after deleting the last note in an editor.

   On the server, [assign_ops/2](../../lib/brando_admin/components/form/block_field.ex:1103)
   calls `notify_note_observers/1`. If observers are registered it materializes
   and casts every root to build note metadata on every op. Cache a projection
   of note identity/order/labels and update affected roots; this cost is absent
   when no observers are registered.

6. **Make draft capture incremental with an acknowledged baseline. Medium
   priority; higher correctness risk.**

   [draftRecovery.capture](../../assets/src/hooks/Form/draftRecovery.js:21)
   serializes all block forms after a three-second pause, or at the 15-second
   deadline during continuous input. The server then
   [casts/snapshots every root twice](../../lib/brando_admin/components/form/block_field.ex:605)
   to overlay raw browser values on materialized state. One changed field thus
   creates page-wide serialization and changeset work.

   Track dirty form UIDs and send raw values only for changed forms against a
   server-acknowledged baseline. A full initial/reconnect capture and deletion
   tombstones are still necessary. Preserve failed casts, unsent debounced
   input, request/generation acknowledgements and timeout retries. Replacing
   browser capture with only the op store would lose raw input not yet accepted
   by the server. Measure bytes, long tasks and capture CPU first; this audit
   did not time the draft path.

7. **Remove repeated linear root lookups, but treat this as secondary at normal
   page sizes. Low priority; small scope.**

   [Ops.materialize_root/2](../../lib/brando_admin/components/form/block_field/ops.ex:529)
   searches `state.order` twice per root; callers loop over every root.
   [materialize_base_struct/2](../../lib/brando_admin/components/form/block_field.ex:1013)
   adds another linear scan of persisted entry blocks. A batch materializer
   with indices and a UID-keyed base lookup makes this linear overall without
   adding a second owner of order or form state.

   Fresh pure-reducer measurements for materializing every root were 0.017 ms
   at 40 roots, 0.172 ms at 155, 1.583 ms at 500 and 22.766 ms at 2,000. This is
   real quadratic growth but not the first explanation for sluggishness at
   155 blocks. These numbers exclude base lookup and Ecto casting.

The already-implemented final Liquid delimiter fast path, parsed-template cache,
preview-closed render guard, targeted entry-field fan-out and recursive CTE
preloading all remain in place. The renderer still has per-item media fallback
loads when associations are missing, but the zero-query warm measurements and
existing batch preloads do not justify labeling normal rendering an N+1 problem.
Measure unsaved gallery/video replacement separately before changing that path.

Follow-up validation should count full/block renders per action, query count,
LiveView/preview payload bytes, browser long tasks and retained process memory.
Start with items 1–3, then refresh large-editor browser measurements for item 4.
Use the existing focused preview, slot/footnote, recovery and media tests for
each change; rebuild JS/CSS through the E2E consumer as AGENTS.md requires.
The measurement probes and aggregate logs from this audit are in
`/tmp/brando-perf-audit.exs`, `/tmp/brando-perf-audit.log`,
`/tmp/brando-footnote-audit.cjs` and `/tmp/brando-footnote-audit.log` for this session.
