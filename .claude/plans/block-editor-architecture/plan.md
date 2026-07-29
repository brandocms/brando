# Plan: validate and tighten the LiveView block editor (no Svelte rewrite)

**Decision:** keep LiveView as the owner of block state. See `assessment.md` for the evidence.

**Status: Phases 0 and 1 are DONE (2026-07-28). Phases 2–5 are open.**
The architecture decision stands — Phase 0 proved per-edit cost is flat in block count, and
Phase 1 cut mount by a third, per-edit by half, save by 93% and memory by ~73% without moving any
state to the client. The one target missed is mount at 115 blocks, and the reason is now understood
and documented below rather than open.

**Checkbox convention.** `- [ ]` is open work and will be picked up by a resume. `- [x]` is closed:
either delivered, or prefixed **WON'T DO** for something decided against, with the condition that
would reopen it. Nothing decided against is left unchecked — an unchecked box here means somebody
should still do it.

## Where we stand (measured 2026-07-28/29, 115 root blocks unless noted)

| Metric | Phase 0 baseline | Now | Target | |
|---|---|---|---|---|
| Mount, inbound | 6 271 KB | 3 887 KB* | ≤ 1 500 KB | ✗ −38 % |
| Mount, wall clock | 4 849 ms | 4 501 ms | ≤ 2 500 ms | ✗ −7 % |
| **Retained session memory** | ~16 MB* | **4.31 MB** | ≤ 8 MB | ✅ |
| **Save, inbound** | never measured | **65 KB** | — | was 1 082 KB |
| Single edit, inbound | 23.0 KB | 11.1 KB | ≤ 11 KB (P2) | ~at gate, −52 % |
| Single edit, outbound | 5.6 KB | 5.0 KB | ≤ 3 KB (P2) | −11 % |
| Insert, latency | 1 128 ms | 827 ms | ≤ 400 ms (P3) | −27 % |
| Insert, inbound | 83.1 KB | 67.4 KB | ≤ 40 KB (P3) | −19 % |
| Mount @40, inbound | — | **1 460 KB*** | ≤ 1 500 KB | ✅ under |
| Mount @5, inbound | — | 317 KB* | — | |
| Nested mount, inbound | 3 334 KB | 1 723 KB | — | −48 % |

\* Mount figures from 2026-07-29 onward are measured on **harder fixtures** than the Phase 0
baseline: three of five bench module types now carry config and hidden vars, which the original
fixtures had none of. Like-for-like the improvement is larger than the table's percentage.

\* The ~16 MB baseline was taken with the single-GC version of `measure_lv_memory.exs` and is
probably overstated — see the measurement note below. The 4.31 MB figure is settled and
reproducible; treat the *ratio* with suspicion, not the current number.

### Why the mount target is missed, and why that is not a loose end

All the removable chrome is gone. What remains is dominated by form inputs that **must** be in the
DOM: `Input.input` (596 KB), `FieldBase` field wrappers (297 KB), checkbox wrappers (177 KB) and
`Form.label` (147 KB) in the attributed dynamics. They cannot be dropped because of one contract:

> `validate_block` params must fully describe every child record on every keystroke, or Ecto
> rebuilds the missing ones from whatever params remain.

Three separate attempts to shrink mount hit exactly this wall, each caught by a save+reload check
rather than by reasoning:

  * config vars reduced to identity-only hidden inputs → blanked (`has_many`, `cast_assoc`)
  * ref config slot omitted while closed → blanked (polymorphic `embeds_one`, `cast_embed`)
  * `:hidden` vars on unsaved blocks → blanked; pre-existing, now fixed

The 1 500 KB target was set from a composition estimate that assumed ~803 KB of mandatory form
attrs. With wrappers counted it is ~1 200 KB, so the target was unreachable by chrome removal from
the outset. **Mount is at the gate already at 40 blocks (1 631 KB) and 333 KB at 5** — the miss is
confined to the 115-block outlier, and closing it needs viewport mounting (see Phase 1 leftovers).

### The save frame — investigated and fixed

The baseline "save" row was never measuring a save: the bench fixtures were seeded without
`template`, which the Page changeset requires, so every save failed validation while the benchmark
reported a latency anyway (it times the round trip, not the outcome). Fixed in
`e2e_seeds_large.exs`. A *succeeding* save then cost **1 082 KB** — instantly the largest frame in
the editor.

Cause, found by bisection: **the `@entry` fan-out, not the `replace_form` cascade.** The obvious
hypothesis was that re-seeding all 115 roots re-rendered each subtree. Measured: with `@entry` held
stable, forcing `replace_form` on all 115 costs **21 695 B** — the cascade is free, because the
fresh forms render byte-identical and change tracking sends nothing. Holding `@entry` stable alone
cut the frame from 1 040 704 B to 21 695 B.

Fix: `Block.update/2` drops `:entry` from incoming assigns for blocks whose module never reads it.
**The DB-sync guarantee is untouched** — `reload_all_blocks/1` is unchanged and still re-seeds every
root after every save; `replace_form` is its own `update/2` clause, matched before the generic one,
so it never passes through the drop. `entry` was never part of that contract: `Block` has no
`entry.id`/`entry_id` read at all, only render-path reads.

The drop test is deliberately **wider** than the registration regex, because the failure modes are
asymmetric — a false positive costs one re-render (the old behaviour), a false negative renders
stale entry data forever, silently. The registration regex only catches literal `entry.<field>` and
misses aliasing (`{% assign e = entry %}` … `{{ e.x }}`), so `may_read_entry?/2` keeps a block on
the old behaviour if the module mentions the word `entry` at all, or is HEEx (entry arrives via the
render context, invisible to any source regex). Failing open measured identical: 75 855 B vs
75 882 B.

### Measurement note — trust repeated readings only

`measure_lv_memory.exs` called `:erlang.garbage_collect/1` once and reported the result as
"retained". That badly overstates: successive calls on the same 115-block session read 11.3 MB →
6.5 MB → 4.3 MB, settling only on the third. This briefly made the benchmark look like a 2.6×
memory regression that did not exist. The script now collects until two consecutive readings agree
within 2%, and reports 4.30 MB on a fresh session where the old one reported 11.3 MB. Anything
comparing against the ~16 MB Phase 0 baseline should account for that baseline having the same flaw.

Related: **a spec that asserts on latency rather than outcome can hide a total failure** — that is
exactly how the broken bench save went unnoticed for a whole phase.

---

## Phase 0 — Verify the premise at real scale (GATE) — ✅ DONE 2026-07-27

**Result: GATE PASSED.** Per-edit cost is flat from 5 → 115 root blocks (23 074 B → 23 049 B) and
flat for blocks nested three levels deep. The architecture decision stands. Full table in
`assessment.md` §1.4.

- [x] `[e2e]` Seeded large-entry fixture — `e2e/priv/repo/e2e_seeds_large.exs` builds
      `/bench-flat-5`, `/bench-flat-40`, `/bench-flat-115` (five mixed module types) and
      `/bench-nested` (40 containers × multi × 2 entries = 160 blocks, 3 levels). Idempotent, not
      part of the normal seed run, publishes entry ids to `bench/fixture-ids.json`.
- [x] `[e2e]` Diagnosed the "save hang". **It was not a sandbox issue** — Playwright's
      `actionTimeout` defaults to unlimited, so with `test.setTimeout(600000)` a mistyped locator
      blocked for the full 10 minutes instead of failing. The bench config now sets
      `actionTimeout: 20000`. Worth knowing for any future long-timeout spec in this repo.
- [x] `[e2e]` Maintained benchmark at `e2e/e2e/playwright/bench/` with its own config so it never
      runs in the regression suite:
      `pnpm playwright test --config bench/playwright.bench.config.js`.
- [x] Results recorded in `assessment.md` §1.4; recommendation re-prioritised — mount, not
      per-edit cost, is the dominant real-world problem.
- [x] Measured LiveView process memory — **~16 MB retained per open 115-block editor session**
      (~140 KB per root block, ≈60 concurrent editors/GB). Done over Erlang distribution rather
      than an eval endpoint: `e2e/bench/measure_lv_memory.exs` + the `hold entry` spec, documented
      in `e2e/bench/README.md`. Full table in `assessment.md` §1.5.

## Phase 1 — Cut the mount payload — ✅ DONE 2026-07-28 (mount target missed, see above)

6.27 MB in a single frame to open a 115-block entry, ~54 KB per block, 598 block DOM nodes
rendered eagerly — against ~76 KB of actual content in Postgres. An **82× multiplier**. This is
what the "132 blocks — that's why it takes a moment" loading overlay exists to hide, and it is the
one metric where a client-owned editor would win structurally (see `assessment.md` §6).

Measured composition of the mount frame **before this phase** (344 components; 117 Block components
>20 KB each account for 4 594 KB / 75 %): `phx-click` JS commands 1 100 KB (22.7 %),
modal/`_config` markup 867 KB (17.9 %), form field attrs 803 KB (16.6 %, must stay — recovery
depends on them), other markup 2 754 KB. The first two buckets are now gone; the third turned out
to be nearer 1 200 KB once field wrappers are counted, which is why the target was unreachable.

- [x] `[liveview]` Stop rendering block config modal **chrome** eagerly, keeping its inputs — done
      2026-07-28. `module_config`/`container_config`/`fragment_config` render the `Content.modal`
      subtree only when a new per-block `config_open` assign names that block's uid; opening is a
      server round trip (`open_block_config`) and the modal arrives with `show={true}`, so the
      entrance is CSS keyframes rather than a JS transition.
      **Measured @115: mount 5 386 → 4 491 KB (−895 KB), edit diff 17.1 → 13.5 KB, insert
      1 109 → 951 ms; nested mount 3 334 → 2 139 KB (−36 %).** 70/70 blocks e2e pass.
      **The plan's "bare hidden inputs when closed" turned out to be wrong, and the save+reload
      check is what caught it.** `carried_var/1` emits only `id` + `_persistent_id`, and
      `cast_assoc` matches params to records **by primary key** — so for a var that has never been
      saved there is nothing to match, and Ecto rebuilds it from those params alone, blanking
      `key`, `placement` and `value`. Blocks are created with unsaved vars, so that is the normal
      case. The closed surface therefore keeps rendering the real var inputs, just inside a hidden
      container; only the chrome (panels, labels, buttons, `Input.Select` live_components) is
      deferred. New spec `e2e/.../blocks/block-config-vars-persistence.spec.js` plus a seeded
      `Config Vars` module pin this.
- [x] `[bug]` `:hidden`-placement vars blanked on unsaved blocks — **fixed 2026-07-28.**
      `carried_var/1` carried only `id` + `_persistent_id`, but `Relation.pop_current/2` keys the
      existing records by primary key, so every pk-less var collides on `[nil]` and Ecto builds a
      brand new record from whatever params arrived — `key`, `placement` and `value` all nil. Silent
      data loss on the first save of any block carrying a `:hidden` var.
      An unsaved var now carries its full cast surface, driven off the newly exposed
      `Brando.Content.Block.var_attrs/0` so the two lists cannot drift, plus its `options` embeds
      and a `name[]` form for array fields. Bounded and temporary: once the var has an id it drops
      back to identity-only, so mount payload for a loaded entry is unchanged.
      **The subtle part:** "unsaved" has to mean *blank*, not `nil`. After one validate round trip
      the id comes back as the `""` that this component's own hidden input submitted, and testing
      `is_nil/1` made the fix silently stop working after the first keystroke. Pinned by the
      `tracking_id` var in `block-config-vars-persistence.spec.js`, which asserts the Vars panel
      still lists every var by key after save + reload.

- [x] `[liveview]` Defer `:vars` materialisation — done 2026-07-28, and it was simpler than the
      corrected note suggested. The retained `:vars` assign had exactly **one** live reader,
      `assign_available_identifiers/1` (datasource blocks only). Every editing surface — including
      `vars/1` — builds its forms from `@form[:vars]` instead. The assign was also threaded as a
      `vars={@vars}` attr through `render/1` → `module`/`container`/`fragment_block` →
      `module_content` and read by none of them: **dead**. So it is now built on demand by
      `block_vars/1` rather than held for the component's lifetime.
      **Measured @115: retained session memory 16 MB → 4.43 MB post-GC (−72 %) — the ≤8 MB gate is
      MET.** Insert latency 951 → 883 ms as a side effect. Mount payload unchanged, as expected.
      70/70 blocks e2e pass.
- [x] Re-measure mount at 5 / 40 / 115 — done, table above. **Mount gate NOT met at 115 (4 336 KB
      vs 1 500 KB); memory gate MET (4.43 MB vs 8 MB).** At 40 blocks mount is 1 583 KB, i.e. at
      the gate, and at 5 blocks 333 KB — the miss is confined to the 115-block outlier.
- [x] `[test]` Mount payload budget assertion — `BUDGETS` in `bench/block-editor.spec.js`, ~10 %
      above the measured values for mount and single-edit at every fixture size. The bench now
      fails rather than just printing numbers.

### Phase 1 — closed decisions

- [x] **WON'T DO** — `[liveview]` Render collapsed blocks as shells. Bad ratio: it can only drop the
      `RenderVar` chrome (~400–500 KB of field wrappers and labels), **not** the inputs, and only on
      entries that are actually collapsed — the bench fixtures are not, so the benchmark cannot even
      show it. It also needs a persisted-vs-unsaved distinction to stay safe, since bare hidden
      inputs blank unsaved vars.
      *Reopen if:* the params contract is fixed, which is what would let a shell drop its inputs
      entirely and change the ratio.
- [x] **WON'T DO** — `[liveview]` Viewport-based mounting for the root list, and with it the
      ≤1 500 KB mount target at 115 blocks, which is **accepted as missed**. It is the only lever
      that reaches the gate, because it is the only one that stops rendering blocks rather than
      shrinking them — but it collides with block recovery (an unrendered block has no inputs to
      capture), `SortableBlocks` and the outline drawer. That is a design pass, not a task, and
      mount is already at the gate at 40 blocks and 333 KB at 5.
      *Reopen if:* 115-block entries turn out to be a real workload rather than an outlier.

## Cross-cutting — the params contract — ✅ ANSWERED, not worth doing

This is the "risky change" the plan circled for two sessions: have the block
changeset merge unsubmitted children from existing data instead of rebuilding them from
whatever params arrived, so the DOM would not have to carry every child on every keystroke.

**It was never scoped with a number, because the bench fixtures had no config vars.** Every
estimate of its value came out as "unknown in real projects". That was a measurement gap, not
a genuine unknown — fixed 2026-07-29 by seeding two config vars and one hidden var into three
of the five bench module types (138 config + 69 hidden vars across 115 root blocks).

With that in place the answer is concrete:

| | bytes @115 blocks |
|---|---|
| What a config surface costs at mount | **546 KB** (14 % of the frame, none of it on screen) |
| Recovered by carrying persisted vars by identity + value | **493 KB** |
| **Left for the risky refactor** | **~65 KB** |

- [x] **WON'T DO** — `[refactor]` the params contract. The prize is ~65 KB, not the ~650 KB it
      was estimated at, because the cheap rule — a persisted record needs only its identity —
      took 90 % of it with no change to how casting works.
      *Reopen if:* a future need makes it necessary for correctness rather than payload.

**The 65 KB that cannot be dropped, and why.** A var's *value* must round-trip even when its
editing surface is off screen. An edit made while the config modal was open lives in the
changeset's `changes`, and `validate_block` rebuilds entry blocks from `changeset.data` — the
original database values, deliberately, so `cast_assoc` can detect changes. Omit `value` from
the params and that edit is silently reverted by the next keystroke anywhere else in the block.
`block-config-vars-persistence.spec.js` caught exactly this on the first attempt: "Config two"
came back as "Config one". The distinction that matters is not saved-vs-unsaved *record* but
edited-vs-never-edited *field*: definitions are never edited here and can go; values cannot.

## Phase 2 — Reclaim the per-edit payload

**Partly banked by Phase 1 already: the edit diff is 23.0 → 12.5 KB (−46 %), outbound 5.6 → 5.0 KB.**
The `phx-click` JS-command attrs that were 46.9 % of the old 23 KB diff are gone (delegated
handlers), and the config-modal chrome that rode every diff is gone too. Remaining gap to the
gate: 12.5 → 11 KB inbound, 5.0 → 3 KB outbound.

Original composition of the 23 KB diff, for reference: 46.9 % `phx-click` JS-command attrs,
27.0 % unchanged form-field `name`/`id`/`value`/`for` attrs, 19.2 % real content. The first bucket
is resolved; what is left is dominated by the second, which is the same mandatory-input surface
that blocks the mount target.

- [x] `[liveview]` Diagnose why change tracking doesn't reach the dropdown — **answered in Phase 1
      by removal rather than diagnosis**: the dropdown no longer emits JS commands at all, so the
      question is moot for it. But hypothesis (c) was separately *confirmed* elsewhere — a changed
      `@entry` re-emitted whole subtrees through function components that rebuild `assigns` above
      their `~H` sigil, which is what made the save frame 1 MB. Expect the same mechanism anywhere
      else a large shared assign is threaded through the block tree.
- [x] `[liveview]` Hoist the static JS commands out of the per-edit render path — **done in Phase 1.**
      The dropdown carries data attributes instead of serialised commands, and the config modal is
      no longer always-rendered.
- [ ] `[liveview]` Reduce the re-sent hidden-input surface. `entry_block[block][uid|type|multi|
      module_id|parent_id|creator_id|source|marked_as_deleted]` are re-serialized on every
      keystroke in both directions and never change during an edit session.
- [ ] Re-measure. Gate: inbound ≤ 11 KB, outbound ≤ 3 KB, no e2e regressions.
- [x] `[test]` Add the payload budget as an e2e assertion — **done in Phase 1.** `BUDGETS` in
      `bench/block-editor.spec.js` asserts mount, single-edit and save at every fixture size.

## Phase 3 — Structural-op latency and tree-wide re-render triggers

**Two of these were measured on 2026-07-29 and the plan had them backwards.**
`bench/tree-triggers.spec.js` covers both, since neither happens during a
mount/edit/insert/save cycle:

  * **Copy a block: 930 KB, 2.7 s @115 blocks.** The concern was real. `clipboard_meta` is
    threaded to every block so each paste button can decide whether to show, and changing it
    re-renders all 139 components. Converting the button from `:if` to an always-rendered
    `hidden` node recovered only 53 KB and cost 14 KB of mount, so it was reverted — the
    paste button is not the bulk. This is the same structural re-render as the old save
    frame, and unlike `entry` we cannot simply stop passing it. A real fix takes clipboard
    state out of the block tree entirely (ancestor attribute + CSS), which is a design
    change, not a tweak.
  * **Open the outline drawer: 45 KB, 1.0 s @115 blocks.** The opposite of what was assumed —
    the payload is small; the cost is a second of *server* time rebuilding every root
    changeset. The item below still stands, but as a latency fix, not a payload one.

**Measurement gotcha:** a copy reaches BlockField through a `send_update`, so its diff lands
after `syncLV` returns. Measured without an explicit wait, that traffic is billed to whatever
runs next — which first made this look like a 1 MB outline drawer and a free copy.


Insert latency measured at 387 ms @5 → 457 ms @40 → 1 128 ms @115 blocks. Payload is flat
(79–83 KB), so this is server-side render work, not transport.

- [ ] `[liveview]` Profile a root insert at 115 blocks. Confirm whether the cost is the
      `:for` comprehension over `root_shells(@root_order, @seed_forms)` (`block_field.ex:1338`)
      re-evaluating and calling `update/2` on every root Block, or the op-store reduce.
- [ ] `[liveview]` The 79 KB insert payload has a single 57 KB frame — identify it (likely the
      ModulePicker re-render) and make it not ride the insert.
- [ ] `[liveview]` Stop clipboard copy from re-rendering the whole tree — **confirmed at 930 KB
      per copy**, see above. "Move it to a lookup the blocks read on demand" does not work:
      every paste button genuinely needs the value, so any per-block assign changes. The
      viable shape is to stop passing it to blocks at all and drive paste-button visibility
      from a single ancestor attribute in CSS. The `{:multi, module_id}` paste context cannot
      be expressed in CSS alone, so that case needs a different mechanism.
- [ ] `[liveview]` Bound the entry-field fan-out. Typing in the entry title `send_update`s every
      entry-consuming block (`form.ex:3007`), each re-running
      `update_liquid_splits_entry_variables/2` + `render_module/1`. Debounce/coalesce it, or skip
      it entirely while live preview is closed (the same gating that fixed per-keystroke Villain
      renders).
      **Narrowed in Phase 1:** blocks whose module never mentions `entry` no longer receive the
      entry assign at all (`may_read_entry?/2`), so the fan-out now reaches only genuine consumers
      instead of every block. What remains is the cost *per consumer*, which is what this item is
      really about.
- [ ] `[liveview]` Make the outline drawer cheap — **1.0 s of server time at 115 blocks**,
      payload is only 45 KB. `rebuild_outline_items/1` materializes and casts every root
      changeset from scratch on each open, to read eight fields off it. It can read the op
      store projection instead. Note it is also called on structural ops, not just on open.
- [ ] Re-measure insert at 115 blocks. Gate: ≤ 400 ms.

## Phase 4 — Close the test gap

The refactor is pinned by e2e only. There are **no LiveView integration tests of the block editor**
(`test/brando_admin/live/` has only `content/module_form_live_test.exs`), and no test exercises
anything near the sizes that produced the worst numbers in this repo's history.

- [ ] `[test]` LiveView integration tests (`Phoenix.LiveViewTest`) for the block editor covering
      the paths currently only reachable through Playwright: mount, `validate_block` for entry and
      child blocks, insert/delete/reorder/duplicate, and the `replace_form` cascade. These run in
      seconds and would have caught the four compounding nested-child save bugs from `dffc72e79`.
- [ ] `[test]` A scale regression that fails if per-edit cost stops being O(1) in block count —
      the property the whole architecture decision rests on.
- [ ] `[test]` Nested-child coverage beyond the current 2 specs. `dffc72e79` noted every blocks
      e2e persistence spec is root-blocks-only, which is exactly why those bugs survived.
- [x] `[docs]` Fix `.claude/skills/brando-blocks/SKILL.md` — **done 2026-07-29.** Sections 5, 7
      and 8 documented the deleted pre-refactor architecture (`send_form_to_parent`, the save
      gather cascade, `position_response_tracker`, `signal_position_update`) while the section at
      the end of the same file said those were removed. Verified none of those functions exist in
      `lib/` any more, then rewrote the lifecycle, event-flow and parent/child sections against
      the current single-owner + op-store design, with an explicit "these do not exist" note so
      the old names cannot be reintroduced by search.

## Phase 5 — Targeted Svelte islands (conditional)

Only if Phases 1–4 leave measurable pain. Use the established pattern: Svelte 5 `mount()`/
`unmount()` from a hook, `phx-update="ignore"` fence, sync via hidden input + `input` event —
exactly how `TipTap.svelte` works today. Svelte 5 and the Vite plugin are already in both Brando's
and consumers' builds; an island costs a file, not a migration.

- [ ] Evaluate converting the **drag/reorder canvas** to an island. This is where the seam hurts
      most: `forceFallback: true`, `focusout` suppression during drags, `waitForTimeout(750)`
      settle waits, mid-drag patches detaching the dragged element, and a named recurring flake
      where morphdom replaces a button mid-click.
**Standing constraint (not a task):** do **not** move block form state, module/ref/var resolution,
live preview, uploads or collaboration sync into the client. Those are the three
no-client-equivalent subsystems plus the missing-authorization problem documented in
`assessment.md` §3.

---

## Risks

- **Phase 2 could turn out to be structural.** If LiveView genuinely cannot skip the dropdown
  subtree without restructuring `block_toolbar`'s slots, the fix gets more invasive than "hoist an
  attr". Mitigation: the diagnosis task is explicitly measure-driven, and the target is a 50 % cut,
  not zero — even partial wins are worth it.
- **Phase 1 is where the rewrite case is strongest.** If lazy rendering can't move mount
  materially, the honest response is to reopen the architecture question, not to defend this plan.
- **This plan defers the seam friction** rather than eliminating it. That is a deliberate bet:
  the friction is well-documented, test-pinned, and currently stable. If new seam bugs start
  appearing at the old rate, Phase 5 should be pulled forward.
- **Self-check:** the strongest arguments against this plan are the friction inventory
  (`assessment.md` §4) and the 82× mount multiplier — a rewrite would delete both. The plan does
  not dismiss either; it puts mount first precisely because that is the contested ground, and it
  states the reversal condition explicitly rather than burying it.

## Change inventory (Phases 0–1) — for review

**Editor internals**
- `form/block/render.ex` — delegated UI triggers; `config_open` gating of block, container,
  fragment and ref config chrome; `carried_var/1` full-surface carry for unsaved vars; dead
  `vars={@vars}` attr chain removed.
- `form/block.ex` — `consumes_entry?` + `may_read_entry?/2`; `drop_on_reentry/1`; `:vars` assign
  removed in favour of on-demand `block_vars/1`; bare `module_picker_id`.
- `form/block/events.ex` — `open_block_config` / `close_block_config`.
- `form/block_field.ex` — delegated field dropdown; bare `module_picker_id`. `reload_all_blocks/1`
  is **unchanged** (verified — the post-save re-seed still runs in full).
- `form/input/blocks/*.ex` (7 files) — `config_open` threading; 10 `show_modal`/`hide_modal`
  triggers converted to server pushes.
- `brando/content/block.ex` — `var_attrs/0` exposed so the DOM carry cannot drift from the cast.

**Client**
- `assets/src/uiCommands.js` (new) — one delegated listener rebuilding LiveView JS ops via
  `liveSocket.execJS`, so `DOM.putSticky` behaviour is unchanged.
- `assets/src/buildApplication.js` — installs it.
- `assets/src/hooks/MapURLParser/index.js` — resolves `.closest('.modal-content')` on click, not at
  mount (the slot now first mounts outside any modal).
- `assets/css/components/Modal.css` — entrance keyframes for server-gated modals.

**Tests / tooling**
- `blocks/block-config-vars-persistence.spec.js`, `blocks/block-ref-config-persistence.spec.js`
  (new) — pin the two params-contract rules and the `:hidden` var fix.
- `e2e_seeds.exs` — `Config Vars` module (content + config + hidden placements).
- `bench/block-editor.spec.js` — mount/edit/save budgets, asserted not just printed.
- `bench/dump-mount-frame.spec.js`, `bench/dump-save-frame.spec.js` (new) — frame capture for
  composition analysis.
- `bench/playwright.bench.config.js` — `webServer.cwd` fixed (was pointing at a dir with no
  `mix.exs`, masked by `reuseExistingServer`).
- `e2e_seeds_large.exs` — fixtures get `template`, so bench saves actually succeed.
- `e2e/bench/measure_lv_memory.exs` — collect-until-settled.
- `e2e/lib/e2e_project_web/controllers/*_html.ex` (3) — redundant `use Phoenix.Component` removed;
  `test_e2e.sh --reset` was failing its `--warnings-as-errors` gate before any Phase 1 edit.

**Verified at close:** `mix format --check-formatted`, `mix test` (997 tests, 0 failures), no new
compiler warnings in changed files, 71/71 blocks e2e, all bench budgets pass.

## Verification

After each phase: `mix compile --warnings-as-errors`, `mix format --check-formatted`,
`mix credo --strict`, `mix test`, and
`cd e2e && source .envrc && ./test_e2e.sh --reset tests/blocks/` (now 71 specs).
Payload and memory claims: `pnpm playwright test --config bench/playwright.bench.config.js`, which
asserts mount/edit/save budgets, plus `e2e/bench/measure_lv_memory.exs` for retention.
Payload/latency claims must be re-measured, not reasoned about — every number in this plan came
from instrumentation and every target should be checked the same way.
