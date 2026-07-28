# Block editor: LiveView vs. a Svelte client-owned-state frontend

**Date:** 2026-07-27
**Question:** Should the block editor be rebuilt with a Svelte frontend holding all state,
using the websocket only to check changesets? Or do the July 2026 changes actually do the trick?
**Verdict: Do not rewrite.** Keep LiveView as the state owner. Fix three measured problems and
close the scale test gap. Extend the *existing* Svelte island pattern only where a widget
genuinely needs local state.

---

## 1. What was measured

All numbers below are from live instrumentation of the running e2e app
(`MIX_ENV=e2e`, port 4444), capturing raw WebSocket frames via Playwright/CDP while driving the
real editor. The harness is kept at `bench-payload.spec.js.reference` in this directory.

### 1.1 Per-edit cost does NOT scale with block count

Typing into the **first** block of an entry, with a growing number of root blocks:

| Root blocks | Typing burst (out) | Typing burst (in) | Single edit (out) | Single edit (in) |
|---|---|---|---|---|
| 12 | 5 476 B | 23 078 B | 5 476 B | 23 081 B |
| 24 | 5 517 B | 23 122 B | 5 520 B | 23 125 B |
| 40 | 5 560 B | 23 165 B | 5 563 B | 23 168 B |

Growth from 12 → 40 blocks: **+84 bytes out, +87 bytes in**. That is O(1), not O(N).

**This is the single most important result.** Dual-ownership of form state — the thing that made
the old editor structurally quadratic and produced the "clobber/FK-wipe" bug class — is gone, and
the measurement confirms it. The central structural indictment of LiveView for this editor no
longer holds.

Two more good results:

- **Typing is fully debounce-coalesced.** 40 characters typed at 70 ms intervals produced exactly
  **one** `validate_block` round trip. The 300 ms `phx-debounce` absorbs continuous typing entirely.
- **Live preview is cheap.** With preview open, an edit adds a single **354-byte** targeted
  `update_block` frame carrying the rendered HTML. The earlier decision not to build incremental
  preview diffing looks correct.

### 1.2 But the per-edit constant is fat — and ~74 % of it is waste

A single-character edit costs **5.4 KB up / 23.0 KB down**. Byte composition of the inbound diff
(leaf strings, 17 847 B of the 23 KB frame; the rest is JSON structure):

| Bytes | Share | What it is |
|---|---|---|
| 8 375 B | **46.9 %** | `phx-click` / `phx-click-away` JS-command attributes (dropdown toggle/show/hide JSON) |
| 4 827 B | **27.0 %** | form field attrs — `name=`, `id=`, `value=`, `for=` on hidden inputs |
| 3 427 B | 19.2 % | actual content / markup |
| 1 218 B | 6.8 % | `data-*` attributes |

The dropdown JS commands are **static apart from a `uid` interpolation that never changes**, and
the hidden-input attrs are overwhelmingly unchanged values. Roughly **three quarters of every
keystroke's payload is boilerplate being re-serialized and re-sent**.

This is a change-tracking failure in Brando's own templates, not a LiveView law. LiveView's
documented change-tracking pitfalls line up with what `block/render.ex` does: variables computed
in function bodies rather than via `assign/3`, and slot-bearing function components
(`block_toolbar/1` → `block_actions_dropdown/1` at `render.ex:1895/1948`) whose subtree re-renders
because an ancestor's `@form`-derived assigns changed. It is a local, tractable fix with a
measurable target.

### 1.3 Structural ops are the one thing that IS O(N)

Inserting a block, by entry size:

| Root blocks | Insert latency | Insert payload (in) |
|---|---|---|
| 12 | 387 ms | 79 406 B |
| 24 | 503 ms | 79 514 B |
| 40 | 687 ms | 79 637 B |

Payload is flat; **wall-clock grows ~10 ms per existing root block**. Extrapolated to the real
115-block entries the codebase already references, an insert would sit near **1.5 s**. Inserting a
block also costs 79 KB — 3.4× a text edit, with a single 57 KB frame.

### 1.4 Scale verification at 115 blocks — the gate (Phase 0, completed 2026-07-27)

Measured against seeded fixtures (`e2e/priv/repo/e2e_seeds_large.exs`) with mixed module types,
via `e2e/e2e/playwright/bench/`. Blocks are shaped exactly as `BlockField.build_block/5` builds
them.

| Entry | Mount in | Mount ms | Block DOM nodes | Edit first (in/out) | Edit last (in/out) | Insert | Save |
|---|---|---|---|---|---|---|---|
| flat, 5 | 425 KB | 2 774 ms | 26 | 23 074 / 5 607 B | 21 736 / 3 175 B | 387 ms | 3 423 ms |
| flat, 40 | 2 284 KB | 3 262 ms | 208 | 23 074 / 5 607 B | 21 736 / 3 176 B | 457 ms | 3 502 ms |
| flat, 115 | **6 271 KB** | 4 849 ms | 598 | **23 049** / 5 606 B | **21 719** / 3 177 B | **1 128 ms** | 3 826 ms |
| nested, 40×3 (160 blocks) | 4 544 KB | 3 770 ms | 320 | 7 818 / 1 522 B | 7 995 / 2 184 B | 824 ms | 3 671 ms |

**GATE PASSED — decisively.** Per-edit cost from 5 → 115 root blocks moves from 23 074 B to
23 049 B. That is **−25 bytes across a 23× increase in entry size**, and the outbound params are
identical to the byte (5 607 → 5 606). Editing the *last* block of a 115-block entry costs the same
as editing the first. Editing a block nested three levels deep costs 7.8 KB, also flat. The
single-owner architecture holds at the worst-case regime this repo has ever recorded.

**Save is effectively flat too**: 3.4 s → 3.8 s, with payload constant at ~18.7 KB regardless of
entry size. `Ops.materialize_root/2` reducing untouched blocks to id-only params is working exactly
as designed.

Two problems the gate surfaced instead:

**(a) Mount is O(N) with a brutal constant — this is now the dominant real-world cost.**
6.27 MB arrives in a **single WebSocket frame** to open a 115-block entry: ~54 KB per block, 598
block DOM nodes rendered eagerly. For comparison, the underlying content in Postgres for that same
entry is **16 KB of block rows + 29 KB of vars + 31 KB of refs = ~76 KB**. LiveView is shipping
**~82× the weight of the actual data**. This is what the "132 blocks — that's why it takes a
moment" loading overlay exists to paper over.

A known contributor: every block renders its config modal into the DOM eagerly (CSS-hidden, not
lazy), and every ref renders in full whether or not the block is collapsed.

**(b) Insert degrades ~2.9× from 5 → 115 blocks** (387 → 1 128 ms), confirming §1.3 at scale.
Payload stays flat, so this is server-side render work, not transport.

### 1.5 Server-side memory per editor session

LiveComponents are not separate processes — every `Block`/`RenderVar` component's assigns live on
the parent LiveView process heap. Measured over Erlang distribution against the running node
(`e2e/bench/measure_lv_memory.exs`), before and after a forced GC:

| Entry | Blocks | LiveView pre-GC | **LiveView post-GC** | Socket pre-GC | Socket post-GC |
|---|---|---|---|---|---|
| flat, 5 | 5 | 1 762 KB | **951 KB** | 3 163 KB | 140 KB |
| flat, 40 | 40 | 10 912 KB | **6 509 KB** | 18 688 KB | 9 KB |
| flat, 115 | 115 | 13 504 KB | **16 195 KB** | 40 971 KB | 87 KB |
| nested, 40×3 | 160 | 18 681 KB | **11 247 KB** | 23 880 KB | 87 KB |

**~16 MB retained per open 115-block editor session**, scaling roughly linearly at ~140 KB per root
block. That works out to roughly **60 concurrent editors per GB** on a large entry, ~150/GB on a
40-block entry. For a CMS admin that is a real but not alarming constraint — worth knowing before
anyone sizes a box.

The socket handler's 41 MB pre-GC spike at 115 blocks is transient serialization garbage from the
6.27 MB mount frame; it collects down to 87 KB, so the payload does not stay resident.

The likely driver of the per-block constant is documented but unverified: every `Block`
LiveComponent holds a full changeset *plus deep-copied* `containers`, `fragments` and
`palette_options` lists. Sharing those instead of copying per component is a concrete optimisation
candidate.

*Caveat:* at 115 blocks the post-GC figure came back **higher** than pre-GC (16 195 vs 13 504 KB).
A forced collection can grow a process's total heap when it promotes live data and resizes with
headroom, so this is plausible rather than a misreading — but it means the 115-block figure should
be treated as approximate. The order of magnitude, and the linear trend, are the usable results.

---

## 2. The specific proposal, examined

> "have the state in the frontend completely, and use websocket to check blocks (changeset)"

**The changeset-checking half of the premise does not hold.** There is no user-facing block
validation to offload:

- `lib/brando/content/block.ex`, `var.ex`, `ref.ex` contain **zero** `validate_required` /
  `validate_*` calls.
- The Blueprint `required: true` markers on `Block.uid`, `Var.label`/`key`, `Ref.name`/`uid` are
  never enforced during block editing — `block_changeset/3` is hand-written and bypasses
  `Blueprint.ChangesetRunner`.
- The only real checks are `unique_constraint(:uid)` (a DB constraint that surfaces at save) and
  structural shape forcing (`finalize_new_block/2` forcing `action: :insert` on nil-id blocks).

So the per-keystroke changeset does not *validate* anything a user would see. It exists to build
persistence params — and the op store (`BlockField.Ops`) **already does exactly that** with
uid-keyed param diffs, independent of the forms. A Svelte client sending params for changeset
checking would be re-creating a round trip whose only current purpose is already served by a
mechanism that doesn't need it.

---

## 3. What a full Svelte rewrite would actually cost

The server-side editing surface is **~11 300 LOC of Elixir** (block.ex 2 640, render.ex 2 382,
block_field.ex 1 653, render_var.ex 1 629, events.ex 1 002, ops.ex 765, plus per-type block
components), against **7 442 lines for the entire admin JS bundle source**. Concretely, the
interface a client-owned frontend would have to replace or re-expose:

### 3.1 Things with no client equivalent at all

- **The editor's WYSIWYG layout *is* a server-side Liquid parse.** `maybe_parse_module/1`
  (`block.ex:1334-1400`) splits the module template on `{% ref refs.X %}`, `{{ var }}` and
  `{% picture … %}` with Elixir regexes and renders each placeholder to HTML. `liquid_splits` is
  the editor's visual structure. A client would need this parser reimplemented, or a
  serialize-the-parse-result API.
- **HEEx modules are compiled to real Elixir modules at runtime**
  (`Villain.HeexRenderer.get_or_compile!/2`, keyed `"admin_#{uid}"`) and rendered through
  `Phoenix.LiveView.TagEngine.component/3`.
- **Live preview builds a real `Plug.Conn`** via `Phoenix.ConnTest.build_conn/2`, runs the browser
  pipeline and renders the actual frontend template.

### 3.2 Things that exist but would need a new API and new authorization

- **103 `handle_event` clauses**, **52 `send_update` message clauses**, **37 `send_update` call
  sites** across the editor tree.
- Uploads: a sticky `UploadManager` LiveView (680 LOC) + a **260-line PubSub delivery-routing
  dispatch** in `form/hooks.ex` with six target kinds, async Oban processing and a second PubSub
  hop, plus a 25 ms serialization queue for gallery adds.
- Collaboration: four PubSub topics, `Ops.subtree_snapshot`/`apply_remote_snapshot`, deferred-apply
  while focused, unchanged-snapshot suppression, late-joiner catch-up, delete tombstones,
  restorable bin.
- Modules/refs/vars/identifiers/datasources/containers/palettes/fragments/revisions — each with
  its own server-side diff-against-definition logic (`fetch_missing_refs`, `reset_var`, …).
- **There is currently zero authorization in the block editor** — grep for `can?`/`authorize`/
  `current_user.role` across `block.ex`, `block_field.ex`, `block/`, `block_field/` returns
  nothing. Authz rides entirely on LiveView mount. Any client-owned API would have to invent an
  authorization layer that does not exist today. This is a security-relevant cost, not just work.

### 3.3 What you would be discarding

The July 2026 refactor was a two-day, 14-commit rewrite that deleted the gather protocol, the
`propagate` flag, the position-ack handshake and the parallel ordered form lists. It is pinned by
**68 blocks e2e specs** and **60 `Ops` unit tests**, and it made the two named bug classes
("clobber/FK-wipe", "drift") structurally unrepresentable. Historically ~67 % of block-editor
defects were LiveView-architecture-induced — but that is past tense, and the fix is the thing a
rewrite would throw away.

---

## 4. The honest case *for* a rewrite

Not everything points one way. The strongest counter-evidence:

- **The friction inventory is long and real.** Sticky-JS lock decorations, widget-remount frame
  ordering (`push_event` must come from the Block, not BlockField, or widgets re-read stale DOM),
  `phx-update="ignore"` islands, `focusout` suppression during drags, "let it settle"
  `waitForTimeout(750)` in specs, ~55 hard-coded waits across the blocks e2e suite, and a named
  recurring flake where morphdom replaces a button mid-click. Every one of these is a seam between
  LiveView's DOM ownership and client-side JS. A client-owned editor deletes the seam.
- **Large entries are slow, and the response was a progress overlay, not a speedup.**
  `form.ex` ships a three-step loading UI whose own comment reads: *"'ah, 132 blocks — that's why
  it takes a moment' instead of a frozen screen."*
- **~190 LiveComponents** for a 30-block page (3 vars, 2 media refs each), each holding a full
  changeset plus deep-copied container/fragment/palette lists.
- **Several actions still re-render the whole tree**: copying a block (clipboard_meta is read
  inside the root comprehension), save (`replace_form` cascade), preview enable, and entry-field
  keystrokes fanning out to every entry-consuming block.
- **The measured-pain regime is completely untested.** No LiveView integration tests of the block
  editor exist at all; e2e specs build 1–3 blocks; the 115-block entry that produced the worst
  measured number in the repo's history has no coverage.

These are genuine. But note what they are: *seam friction* and *unmeasured scale* — not evidence
that per-edit state ownership belongs on the client. And the seam already has a proven answer.

---

## 5. The hybrid already exists and works

This is not a hypothetical migration path — it is shipped:

- `assets/src/components/TipTap/TipTap.svelte` is **792 lines of Svelte 5** (runes: `$props`,
  `$state`, `$bindable`), mounted via the Svelte 5 imperative `mount()`/`unmount()` API from
  `hooks/TipTap/index.js`, fenced with `phx-update="ignore"`, syncing to the server by writing a
  hidden input and dispatching an `input` event. The ProseMirror document, all formatting commands,
  paste cleaning and 20 toolbar state flags are 100 % client-owned.
- `hooks/ImageEditor/index.js` is **1 377 lines** of client-owned WebGL crop/focal-point editing
  with exactly two server touches.
- **Svelte 5 + `@sveltejs/vite-plugin-svelte` + `svelte-preprocess` are already devDependencies and
  already wired into both Brando's Vite config and the consumer app builds** (`assets/vite.config.js`,
  `e2e/assets/backend/vite.config.js`, `svelte.config.cjs` in both). Adding an island costs a file,
  not a migration.

The architecture is therefore already "LiveView owns structure, persistence and forms; Svelte/JS
owns the hard interactive widgets." The question is not *whether* to use Svelte — it is *how far to
push the boundary*. The evidence says: push it where the seam hurts, not to the state model.

---

## 6. Recommendation

**Keep LiveView as the owner of block state. Do not rewrite the editor in Svelte.**

Rationale in one line: the per-edit cost is already O(1) in block count, the remaining constant is
~74 % removable *within* LiveView, the "changeset checking" the rewrite would offload does not
exist, and the server-side coupling includes three subsystems (Liquid editor-layout parsing, HEEx
runtime compilation, Plug-based live preview) with no client equivalent plus an authorization layer
that would have to be invented from scratch.

Do this instead, in priority order (revised after the Phase 0 measurement):

1. **Cut the mount payload.** 6.27 MB to open a 115-block entry, against ~76 KB of underlying
   content, is the dominant real-world cost and the thing users actually feel. Render collapsed
   shells and mount block bodies on expand; stop rendering config modals and refs eagerly for every
   block. Target: ≤ 1.5 MB at 115 blocks.
2. **Reclaim the per-edit payload.** Cut the 23 KB inbound diff by ≥ 50 % — ~74 % of it is
   re-serialized boilerplate (§1.2).
3. **Fix the O(N) insert latency** (1.13 s at 115 blocks) and the remaining tree-wide re-render
   triggers.
4. **Close the test gap** — LiveView integration tests, and a scale regression that fails if
   per-edit cost stops being O(1).
5. **Only then**, and only where measurement still shows pain, convert the drag/reorder canvas to a
   Svelte island using the established TipTap pattern.

**Where the rewrite case is genuinely strong, and I want to be straight about it:** mount is the
one metric where a client-owned editor would win structurally. Shipping ~76–200 KB of JSON per
entry-open instead of 6.27 MB of rendered HTML is a real, order-of-magnitude difference, paid for
once as a bundle rather than per entry-open. If item 1 above cannot get mount down substantially,
that argument gets much harder to answer — and the honest response would be to reconsider, not to
defend the decision.

Revisit this decision if item 1 fails to move mount materially, or if per-edit cost ever stops
being O(1).

---

## 7. Caveats on this assessment

- The §1.1–1.3 benchmarks used one simple module type ("Styled Header", 2 vars + 1 ref). The §1.4
  scale run used five mixed module types and reproduced the same per-edit numbers, so the shape is
  confirmed — but a gallery-heavy or table-heavy entry is still unmeasured.
- Mount numbers are *payload and wall-clock as observed by the client*. Server-side memory per
  LiveView process at 115 blocks (~730 LiveComponents, each holding a changeset plus deep-copied
  container/fragment/palette lists) is still unmeasured, and it bounds how many concurrent editors
  a server can hold. `evalLV` in `e2e/e2e/playwright/utils.js` looks like it would help but is
  dead — no `sandbox:eval` handler exists anywhere in the codebase.
- Save latency (~3.5 s) was measured end-to-end including the post-save `replace_form` re-seed
  cascade and a fixed settle wait, so treat it as an upper bound rather than server time.
- `.claude/skills/brando-blocks/SKILL.md` sections 5–10 still describe the **pre-refactor**
  architecture (`send_form_to_parent`, the gather protocol, `position_response_tracker`) that the
  Phase 3 section at the bottom of the same file says was deleted. Anything read from those
  sections should be verified against code.
