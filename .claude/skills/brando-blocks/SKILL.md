---
name: brando-blocks
description: >
  Reference for Brando's block system. Use when working with blocks, modules,
  refs, vars, containers, fragments, block_field, block recovery, reordering,
  duplication, live preview, or block changesets.
user-invocable: true
---

# Brando Blocks System Reference

## 1. Architecture Overview

### Component Hierarchy
```
Form (LiveView) → BlockField (LiveComponent) → Block (LiveComponent, recursive)
```

### Data Model
```
Entry → EntryBlock (join table) → Block → vars/refs/children/table_rows/block_identifiers
```

- **EntryBlock** is auto-generated per-schema via the Blueprint `blocks` macro (e.g. `Brando.Pages.Page.Block`). It joins an entry to a `Block` and holds `sequence` and `entry_id`.
- **Block** holds the actual content: type, module/container/fragment references, vars, refs, children (recursive), table_rows.
- Blocks live **OUTSIDE** the main `<.form>` tag for performance — avoids sending all block data on every keystroke in the main form.
- Each block has its own `<.form phx-change="validate_block" phx-target={@target}>`.

---

## 2. Key File Paths

### Schemas
| File | Description |
|------|-------------|
| `lib/brando/content/block.ex` | Block schema (Blueprint): attributes, relations, `block_changeset`, `recursive_block_changeset` |
| `lib/brando/content/var.ex` | Var schema: typed variables (boolean, string, text, html, image, color, select, file, link, date, datetime) |
| `lib/brando/content/ref.ex` | Ref schema: polymorphic embed `data` field + media associations (image, video, gallery, file) |
| `lib/brando/content/container.ex` | Container schema |
| `lib/brando/content/module.ex` | Module schema: defines block templates with vars/refs |
| `lib/brando/content/table_row.ex` | TableRow schema for tabular data in blocks |
| `lib/brando/content/block_identifier.ex` | Join table between blocks and identifiers |
| `lib/brando/content/var/option.ex` | Options for select-type vars |
| `lib/brando/content/template.ex` | Block template schema |
| `lib/brando/content/table_template.ex` | Table template schema |
| `lib/brando/pages/fragment.ex` | Fragment schema |

### LiveView Components
| File | Description |
|------|-------------|
| `lib/brando_admin/components/form/block_field.ex` | BlockField component: manages root entry_blocks, builds blocks/containers/fragments, handles recovery, reposition, save cascade |
| `lib/brando_admin/components/form/block.ex` | Block component: renders individual blocks, manages children, validate_block, refs, live preview |
| `lib/brando_admin/components/form/block/events.ex` | Event handlers: validate_block, duplicate, delete, reposition, table_row, identifier events |
| `lib/brando_admin/components/form/block_field/module_picker.ex` | Module picker modal |

### Block Input Components (Ref Renderers)
| File | Description |
|------|-------------|
| `lib/brando_admin/components/form/input/blocks/picture_block.ex` | Picture ref block input |
| `lib/brando_admin/components/form/input/blocks/video_block.ex` | Video ref block input |
| `lib/brando_admin/components/form/input/blocks/media_block.ex` | Media ref block input |
| `lib/brando_admin/components/form/input/blocks/gallery_block.ex` | Gallery ref block input |
| `lib/brando_admin/components/form/input/blocks/svg_block.ex` | SVG ref block input |
| `lib/brando_admin/components/form/input/blocks/map_block.ex` | Map ref block input |
| `lib/brando_admin/components/form/input/blocks/render_var.ex` | Var rendering component |
| `lib/brando_admin/components/form/input/blocks/utils.ex` | Block rendering utilities |

### Villain (Rendering & Block Types)
| File | Description |
|------|-------------|
| `lib/brando/villain/villain.ex` | Main Villain module: rendering, parsing, duplicate helpers |
| `lib/brando/villain/parser.ex` | Liquex template parser |
| `lib/brando/villain/block.ex` | Base block behaviour and macros |
| `lib/brando/villain/blocks.ex` | Block type registry (lists all available block types) |
| `lib/brando/villain/blocks/*.ex` | Individual block type implementations (text, picture, video, header, gallery, etc.) |

### Context & Traits
| File | Description |
|------|-------------|
| `lib/brando/content.ex` | Content context: CRUD for Block, Container, Module, etc. |
| `lib/brando/traits/blocks.ex` | Blocks trait for Blueprint schemas |
| `lib/brando/traits/blocks/prevent_circular_references.ex` | Prevents circular block references |
| `lib/brando/blueprint/villain.ex` | Blueprint villain integration |

### JS Hooks
| File | Description |
|------|-------------|
| `assets/src/hooks/BlockField/index.js` | Recovery: captures forms to sessionStorage on disconnect, restores missing blocks on reconnect |
| `assets/src/hooks/Block/index.js` | Autosize textareas via `autosize` library |
| `assets/src/hooks/SortableBlocks/index.js` | Drag-and-drop via SortableJS, fires `reposition` event |

### Tests
| File | Description |
|------|-------------|
| `test/brando/content_test.exs` | Content context tests |
| `test/brando/villain/villain_test.exs` | Villain rendering tests |
| `test/brando/villain/blocks/ref_apply_test.exs` | Ref apply_ref tests |
| `e2e/e2e/playwright/tests/blocks/` | E2E tests (identifiers, table rows, live preview) |

---

## 3. Block Types

| Type | Description |
|------|-------------|
| `:module` | Standard block backed by a Module (template + vars + refs). Most common type. |
| `:container` | Groups child blocks. Has a container_id pointing to a Container record that defines allowed children and layout. |
| `:fragment` | References a shared Fragment. Read-only embed — edits happen on the Fragment itself. |
| `:module_entry` | Module block used within multi-blocks (when `multi: true`). Children of a `:module` block. |

---

## 4. Schema Quick Reference

### Block Fields
```
uid, type (:module/:container/:fragment/:module_entry), active, collapsed,
description, anchor, multi, datasource, rendered_html, rendered_at,
source (Brando.Type.Module), identifier_metas (JSON), module_version,
sequence, creator_id, module_id, container_id, fragment_id, parent_id, palette_id
```

`module_version` is server-controlled and deliberately absent from `@block_attrs`
— see section 14.

### Block Relations
```
belongs_to: container, fragment, module, palette, parent (self-ref)
has_many: children (self-ref), vars, refs, table_rows, block_identifiers
has_many through: identifiers (via block_identifiers)
```

### Var Types
`:boolean`, `:string`, `:text`, `:html`, `:image`, `:datetime`, `:color`, `:select`, `:file`, `:link`, `:date`

### Ref Structure
- `name` (text) — matches `{% ref refs.name %}` in Liquex templates
- `data` — PolymorphicEmbed (types from `Brando.Villain.Blocks.list_blocks()`: text, picture, video, header, media, gallery, svg, map, etc.)
- Media associations: `image`, `video`, `gallery`, `file` (each belongs_to with `on_replace: :nilify`)
- Standard preloads: `Brando.Content.Ref.preloads()` → `[:image, :file, video: [:thumbnail], gallery: [gallery_objects: [:image, :video]]]`

### EntryBlock Structure (auto-generated)
```elixir
# e.g. Brando.Pages.Page.Block
schema "pages_page_blocks" do
  belongs_to :entry, Brando.Pages.Page  # or whichever schema
  belongs_to :block, Brando.Content.Block
  field :sequence, :integer
end
```

---

## 5. Component Lifecycle

### BlockField
1. `mount/1` — `{:ok, assign(socket, :outline_items, [])}`
2. `update(assigns, socket)` — catch-all: `initialize_blocks/2`, guarded so it runs once
3. `initialize_blocks` — builds `@seed_forms` (a uid-keyed map of mount-time seeds) and
   the op store via `assign_ops(Ops.from_entry_blocks(entry_blocks))`. `@root_order` is the
   store's render projection and is assigned **only** through `assign_ops/2`.

### Block
1. `mount/1` — attaches `Events.attach_block_events/1`
2. `update(assigns, socket)` — catch-all, runs on every parent re-render:
   - After first mount it **drops `:form` and `:children`** from incoming assigns — the
     block owns its form exclusively from then on. It also drops `:entry` for blocks whose
     module never reads it (`may_read_entry?/2`), so a replaced entry struct does not
     re-render the whole tree.
   - `assign_new` for uid/type/multi/has_vars? etc — set once, never overwritten
   - `maybe_assign_children` → `maybe_assign_module` → `maybe_parse_module` →
     `maybe_render_module`
   - Sets `block_initialized: true`

**Key guard**: `assign_new` plus the `Map.drop` above are what stop a parent re-render from
clobbering local editing state — the historical clobber/FK-wipe class of bug.

---

## 6. Form & Changeset Patterns

### `to_change_form` vs `to_form`
- **`to_change_form(block_module, entry_block_or_cs, params, user_id)`** — runs `block_module.changeset(entry_block, params, user_id)` before wrapping in `to_form`. Used when you want the changeset pipeline to run (casting, validation).
- **`to_form(changeset, as: ..., id: ...)`** — wraps an existing changeset directly. Used when you've already built the changeset manually (e.g. after `build_block`).

### Building New Blocks
```elixir
BlockField.build_block(module_id, user_id, parent_id, source, type)   # :module or :module_entry
BlockField.build_container(user_id, parent_id, source)
BlockField.build_fragment(user_id, parent_id, source)
```
All return a `%Changeset{}` with `action: :insert`.

### Changeset Pipeline
```
block_module.changeset(entry_block, params, user_id)
  └─ cast_assoc(:block, with: &block_changeset/3 or &recursive_block_changeset/3)
       └─ Block.block_changeset(block, attrs, user)
            ├─ cast(attrs, @block_attrs)
            ├─ cast_table_rows(user)
            ├─ cast_block_identifiers(user)
            ├─ cast_assoc(:vars, with: &var_changeset/4)
            └─ cast_assoc(:refs, with: &ref_changeset/3)
```

For new blocks (nil ID): filters out `:replace` action from refs/vars, forces `:insert` action.

### validate_block — Two Variants

**Child block** (`"child_block"` params):
1. `apply_changes(changeset)` to get struct with in-memory modifications
2. Filter table_rows to persisted only (with IDs)
3. Restore `original_block_identifiers` from socket assigns
4. Clear vars/refs for new blocks (nil ID) to avoid duplicate PK warnings
5. `Block.block_changeset(block_for_changeset, params, user_id)`
6. `render_and_update_block_changeset` → `Block.assign_block_form/2` (assigns `:form`, emits the update op)

**Entry block** (`"entry_block"` params):
1. Use `changeset.data` (original DB values) as base — NOT `apply_changes`
2. Same filtering: persisted table_rows, original block_identifiers, clear vars/refs for new
3. `block_module.changeset(block_for_changeset, params, user_id)` — runs full pipeline including `cast_assoc(:block)`
4. Check for container active status flip → force render
5. `render_and_update_entry_block_changeset` → `Block.assign_block_form/2` (assigns `:form`, emits the update op)

**Critical difference**: entry_block uses `changeset.data` as base; child_block uses `apply_changes`. This is because `cast_assoc` for entry_blocks compares params against `data` — using `apply_changes` would bake in previous edits and `cast_assoc` wouldn't detect them.

---

## 7. Event Flows

### Validation Flow
```
User types in a block form
  → phx-change="validate_block" (target: the block's @myself)
  → Events.handle_block_event("validate_block", params, socket)
  → build the changeset from params
  → Block.assign_block_form/2   ← the chokepoint: assigns :form AND emits
                                   {:update, uid, diff} to BlockField's reducer
  → maybe_update_live_preview_block()
```
There is no form handoff to the parent. The block keeps its form; the parent gets a param
diff. See "Block Editor: single-owner state & ops" at the end of this file for why.

### Save Flow
```
Form sends: send_update(BlockField, event: "fetch_root_blocks", tag: :save)
  → BlockField materializes every root from the op store in ONE pass
    (Ops.materialize_root/2) — no messages to blocks, no collection cascade
  → send_update(form_cid, event: "provide_root_blocks", ...)
```
After the save completes, `reload_all_blocks/1` hands every mounted root a fresh form via
the `replace_form` cascade, so blocks stop diffing against pre-save nil-id data.

### Duplication Flow
```
Events.handle_block_event("duplicate_block")
  → has children: send "fetch_changeset_for_duplication" to each child, which reply with
    "provide_changeset_for_duplication" until the parent is `populated: true`
  → then: duplicate via ContentBlocks.duplicate_block/2, put a seed form, and apply an
    {:insert, uid, sequence, diff} op
```
Duplication is the one place a changeset still travels between components, because a copy
needs the whole materialized subtree.

### Copy / Paste Flow
Copy gathers the same way duplication does, then stores
`%{changeset, type, parent_module_id}` in **`Brando.Cache` under
`{:block_clipboard, user_id}`** (4h TTL, tenant-scoped) — never in the socket. That is what
makes paste work **across entries and across schemas**: any BlockField the same user mounts
reads the same clipboard.

* `initialize_blocks/2` hydrates `clipboard_meta` + `paste_multi_module_id` from the cache.
  Skipping that hydration is what used to make paste look same-document-only: the buttons
  are shown by CSS from `data-paste-allow`, which is rendered from `clipboard_meta`.
* **A paste never consumes the clipboard** — one copy pastes into as many spots and as many
  entries as the user likes. The only way out is the block field's actions dropdown
  (`clear_clipboard` → `Brando.Cache.del/1` + `assign_clipboard_meta(socket, nil)`), which
  names what it holds from the `label` snapshotted at copy time. Because a clipboard can
  legitimately sit there for hours, the pills are faded out until their `.block-plus-wrapper`
  is hovered (opacity only — `pointer-events: none` would take them out of Playwright's
  hit-target check).
* Paste forces `source:` to the **target** field's `block_module` (`duplicate_block/2`'s
  `:source` opt, applied recursively) — `source` names the join table `list_orphaned_blocks/0`
  reaches a block through, so a cross-schema paste must re-source.
* `duplicate_ref/2` **deep-copies the ref's gallery** (`Galleries.duplicate_gallery/2`,
  a real DB insert): images/videos/files are library assets and stay shared, but a gallery
  is owned by its ref, so sharing the row would make the copy's edits hit the original.
  The new `gallery_id` is written to the ref's *data* (not `put_assoc`ed) because the op
  store snapshots a new block's applied state.

### Insert / Delete / Reorder
All are **ops applied to the store**, not list surgery:
`{:insert, uid, seq, diff}`, `{:delete, uid}`, `{:reorder_children, parent, uids}`. Root-level
structure is applied by BlockField directly; everything else arrives from blocks through
`Block.emit_block_op/2`. Blocks read their position from the `list_index` prop supplied by
the keyed `:for` — never from a form's `sequence` field, which is stale by design.

---

## 8. Parent-Child Communication

### Upward (Child → Parent)
- **`block_op`** — the main channel. Carries a named op with **param diffs, never changesets
  or forms** (`Ops.block_diff_params/1`).
- **`provide_changeset_for_duplication`** — duplication only, as above.
- **`register_block_wanting_entry`** — a block whose module reads `entry.*` registers for the
  targeted entry fan-out.

### Downward (Parent → Child)
- **`replace_form`** — the ONLY sanctioned form handoff after mount. Used post-save and on
  remote-sync apply, and it cascades down the tree. Anything else re-introduces the clobber
  class.
- Structural and UI messages: `set_collapsed`, `set_children_collapsed`, `insert_block`,
  `insert_pasted_block`, `paste_block`, `paste_child_block`, `outline_reorder_child`,
  `extract_child`, `update_ref`, `update_ref_data`, `update_block_var`,
  `update_entry_field`, `enable_live_preview` / `disable_live_preview`.

> There is **no** position-response tracker, no `send_form_to_parent`, and no
> `signal_position_update`. Those belonged to the pre-2026-07 architecture and were removed
> with it — see "Block Editor: single-owner state & ops" at the end of this file.

---

## 9. Recovery Mechanism

### Scope — what this mechanism is *for*

Bespoke recovery exists for the one case LiveView's own form recovery structurally
cannot reach: **brand-new root blocks that were never persisted.** Everything else
is already covered — the main entry form and every block form carry a stable `id`
plus `phx-change`, so LiveView replays their DOM params through `validate` /
`validate_block` on reconnect, rebased on a freshly DB-loaded changeset. (Absence
of `phx-auto-recover` means *default* recovery, not none.)

The corollary is the thing to remember: **recovery replays the DOM.** State held
only in changeset `changes` or in component assigns, with no input backing it, is
not recoverable here — and is usually already lost by the next keystroke,
disconnect or not.

### JS Hook (`BlockField/index.js`)
1. **`disconnected()`**: Captures all block form data from DOM (`FormData` → nested params), root UIDs, and `childOrder` (parent uid → ordered child uids, read off the `data-parent_uid` wrappers) to `sessionStorage`, with a `savedAt` stamp
2. **`reconnected()`**: Reads from sessionStorage, compares stored UIDs vs current DOM UIDs, sends `recover_blocks` with the missing roots **and their whole child subtree**. `mounted()` is deliberately a no-op — recovery is a reconnect concern, not a mount concern
3. Storage key is `brando:block-recovery:{entry-id}:{element-id}`; snapshots older than the TTL are discarded unread
4. The snapshot is removed **only** after the server replies, never before the push — it is the sole copy of blocks that exist nowhere else

### Server Handler (`block_field.ex: handle_event("recover_blocks")`)
1. Receives `rootUids`, `missingUids`, `forms` (params keyed by form ID), `childOrder`
2. For each missing UID:
   - Creates base struct with empty associations (vars, refs, table_rows, children, block_identifiers)
   - Grafts the captured child subtree onto the block params from `childOrder`, preserving order (sequence is derived from list position)
   - Runs `block_module.changeset(base_struct, params_with_entry, user_id, true)` — the **recursive** cast. The 3-arity variant has no `cast_assoc(:children)` and drops the subtree silently
   - Sets `action: :insert`
3. Merges recovered forms with existing forms in original root_uids order
4. Replies `%{recovered: uids}` so the client can drop its snapshot

Form field values — vars, refs, table_rows — are preserved because the recovered
params go through the same changeset pipeline as normal validation. What is *not*
preserved is anything that had no DOM input to capture in the first place.

---

## 10. Live Preview

### Enable/Disable
Cascades through entire block tree:
```
Form → BlockField (event: "enable_live_preview", cache_key: ...) →
  for each block_uid: send_update(Block, event: "enable_live_preview", cache_key: ...)
    → Block: assigns live_preview_active?: true, cascades to children
    → maybe_render_module() — renders Liquex template
```

### Rendering
- **`render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?)`** — renders a child block's Liquex template, puts `rendered_html` and `rendered_at` into changeset
- **`render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?, force_render?)`** — same but navigates through the entry_block wrapper to the nested block
- `force_render?` — set true when container flips from `active: false` to `active: true`

### Update Trigger
After validate_block: `maybe_update_live_preview_block()` sends rendered HTML to the form, which pushes it to the client.

### Reorder and preview
There is **no position-response tracker.** Earlier versions waited for every
block to confirm its new sequence before triggering a preview update; that
machinery is gone (no `position_response`/`pending_positions` anywhere in
`lib/` or `assets/src/`). Under the single-owner op store, reorder is a store
mutation the BlockField applies in one place, so there is no fan-out of
per-block confirmations left to await.

---

## 11. Common Pitfalls

### Duplicate PK Warnings
When using `apply_changes()` followed by another changeset call, clear embedded associations with nil IDs for new records:
```elixir
if is_nil(block.id), do: Map.merge(block, %{vars: [], refs: []}), else: block
```

### NotLoaded Guards
Always check for `%Ecto.Association.NotLoaded{}` before passing to `put_assoc` or `Enum`:
```elixir
case block_cs.data.block_identifiers do
  %Ecto.Association.NotLoaded{} -> []
  nil -> []
  identifiers -> identifiers
end
```

### Filter `:replace`/`:delete` Actions
Changesets from `get_assoc` after `cast_assoc` may have `action: :replace` or `:delete`. Filter them out before reusing in `put_assoc`:
```elixir
|> Enum.reject(fn cs -> cs.action in [:replace, :delete] end)
```

### Use `changeset.data` as Base for validate_block (Entry Blocks)
Using `apply_changes` as base causes `cast_assoc` to not detect changes (they're already baked in). Use `changeset.data` (original DB values) and let params drive change detection.

### Store `original_block_identifiers`
Stored at mount via `assign_new`. Used in validate_block so `cast_assoc` can match existing records by ID instead of seeing nil-ID duplicates.

### New Records in `put_assoc`
Use **maps** (not nil-ID changesets/structs) for multiple new records. Ecto creates distinct insert changesets for each map.

### Drop Association Keys When Converting Structs to Maps
When building maps for `put_assoc`, drop association keys (`:block`, `:module`, `:parent`) that might contain `NotLoaded` values.

---

## 12. DOM ID Conventions

| Element | ID Pattern |
|---------|------------|
| Block component | `"block-#{uid}"` |
| Child block component | `"#{parent_id}-child-#{child_uid}"` |
| Entry block form | `"entry_block_form-#{uid}"` |
| Child block form | `"child_block_form-#{uid}"` |
| Entry block wrapper | `"base-#{uid}"` |
| Child block wrapper | `"child-#{uid}"` |
| Block field container | `"block-field-#{block_field}"` |
| Module picker | `"block-field-#{block_field}-module-picker"` |
| BlockField wrapper | `"#{id}-wrapper"` (with `phx-hook="Brando.BlockField"`) |

**Rule**: Never use database IDs for DOM identification — always use UIDs. New records don't have database IDs yet, and using nil IDs causes component remounting.

---

## 13. JS Hooks

### `Brando.BlockField` (`assets/src/hooks/BlockField/index.js`)
- **Purpose**: Recovery of never-persisted root blocks after the LiveView process dies (see §9 for what this does *not* cover)
- **`disconnected()`**: Serializes all block forms' `FormData`, root UID order and `childOrder` to `sessionStorage`
- **`reconnected()`**: Compares stored UIDs vs current DOM, sends `recover_blocks` with the missing roots and their descendants. `mounted()` is a no-op
- Storage key: `brando:block-recovery:{entry-id}:{wrapper-element-id}`, TTL-stamped
- The snapshot is cleared on the server's reply, not before the push

### `Brando.Block` (`assets/src/hooks/Block/index.js`)
- **Purpose**: Auto-resize textareas
- Uses `autosize` library on elements with `[data-autosize]` attribute
- Re-runs on `mounted()` and `updated()`

### `Brando.SortableBlocks` (`assets/src/hooks/SortableBlocks/index.js`)
- **Purpose**: Drag-and-drop reordering via SortableJS
- Config: `handle: '.sort-handle'`, `animation: 150`
- **`onEnd`**: Pushes `reposition` event with `{old: oldIndex, new: newIndex, ...item.dataset}`
- Prevents `phx-blur` from firing during drag (`focusout` stopImmediatePropagation)
- Optional grouping via `data-blocks-wrapper-type` for cross-container drag

---

## 14. Module Saves Are Site-Wide Migrations

Saving a module re-syncs **every block that uses it, in every entry**:

`Content.update_module/3` → `mutation :update, Module` → `Blocks.render_entries_with_module_id/2`
→ `list_block_ids_using_module/2` → `sync_and_render_blocks/3` → `Blocks.sync_module/2`
(one `Repo.update/1` per block, outside a transaction).

### Rules

- **Nothing is deleted.** Refs and vars the module no longer defines are
  retained. A removal cannot be told apart from a rename here, and the data
  belongs to the editor. Orphans lie dormant — the template does not reference
  them — until an explicit upgrade resolves them.
- **`Module.version` counts definition revisions**, bumped by
  `Brando.Trait.ModuleVersioned` when `Brando.Content.ModuleDiff` says the change
  was effective. It is also an optimistic lock: a save over a revision the editor
  never saw raises `Ecto.StaleEntryError`.
- **`Block.module_version` is how far that block got.** `sync_module/2` stamps it
  only when every ref and var the block holds still has a definition of a
  compatible type behind it. Anything else — an orphan, a retyped ref, or a
  failed write — leaves the block behind, findable via
  `Blocks.list_stale_block_ids/2` and `count_stale_blocks/2`.
- **A `media` module ref is a slot, not a type.** It legitimately drives
  picture / video / gallery / svg block refs, each of which has a `MediaBlock`
  clause in `apply_ref/3`. Use `Brando.Villain.Blocks.ref_types_compatible?/2`
  rather than comparing structs — treating that as a retype puts a warning in
  front of every media module edit.
- **Never trust `module_version` from params.** It is not in `@block_attrs`. An
  entry editor opened before a migration must not be able to save its way to
  claiming it is current.

### Classifying a pending module change

`ModuleDiff.diff(old_module, new_module_or_changeset)` → `:none` | `:metadata` |
`:render` | `:compatible` | `:destructive` (most severe wins). `destructive?/1`
gates the module editor's confirmation dialog; `summary/1` gives the lines it
shows.

`Module.uid` is lineage identity for import replacement (not yet built). Export
and import mint a fresh one at v1, so import produces copies.

---

## Block Editor: single-owner state & ops (Phase 3 architecture)

Each block is its own `live_component` and **owns its editing state exclusively** —
after first mount, a parent re-render can never overwrite a block's form (`Block.update/2`
drops incoming `:form`/`:children` assigns once initialized). Forms never travel between
components. The parent (`BlockField`) owns **order + structure + a uid-keyed param-diff
store** (`BlockField.Ops` — a pure, unit-tested reducer over
`{order, parents, child_order, diffs, statuses, db_ids, deleted}`).

- **Every mutation is a named op applied by the reducer.** Children emit
  `{:update, uid, params_diff}`, `{:insert_child, parent, uid, at, params}`,
  `{:reorder_children, parent, uids}`, `{:delete, uid}` etc. via `Block.emit_block_op/2`;
  BlockField applies its own ops for root-level structure. Ops carry **param diffs, never
  changesets or forms** (`Ops.block_diff_params/1`: persisted records diff by changes, NEW
  records snapshot full applied state — builders pre-populate changeset *data*, so a
  changes-only diff would drop `module_id`/vars/refs).
- **The chokepoint: `Block.assign_block_form/2`.** Every handler that rebuilds a block's
  form MUST assign it through this helper — it assigns `:form` AND emits the
  `{:update, uid, diff}` op, keeping the store save-complete. Assigning `:form` directly
  is reserved for render-artifact stamping (`rendered_html`/`rendered_at`).
- **Save/preview/share materialize from the store** (`Ops.materialize_root/2`): sequence
  derives from list order (never from diff `"sequence"` keys), db ids re-attach so
  `cast_assoc` matches rows, untouched blocks reduce to id-only params (no SQL), render
  artifacts are stripped. There is NO gather protocol, NO propagate flag, NO position-ack
  handshake — do not reintroduce them.
- **Blocks receive their position as the `list_index` prop** from the keyed `:for`
  (`:key` on uid). Read `socket.assigns.list_index` for insert-at/paste-at positions —
  never a form's `sequence` field (stale by design).
- **Rendering derives from the store, seed forms are maps.** BlockField's keyed `:for`
  iterates `@root_order` (the store's projection, assigned ONLY via `assign_ops/2`);
  parent blocks iterate their `@block_list`. `@seed_forms`/`@children_forms` are
  uid-keyed maps read once at a component's first mount — put on insert, drop on
  delete, never reordered, never reconciled. There is no parallel ordered form list —
  do not reintroduce one.
- **The ONLY sanctioned parent→child form handoff after mount is `replace_form`**
  (cascades down the tree): used post-save (re-seed with fresh db ids) and on remote-sync
  apply. Anything else re-introduces the historical clobber/FK-wipe class.
- **Media commits: use `Block.commit_ref_data/2`** for one-shot ref commits
  (picker select / reset / upload-complete / image-editor) — never raw
  `send_update(..., event: "update_ref_data", ...)`. Not for per-keystroke updates.
  Related helpers: `Block.current_block_data_map/3` (ref_data payloads),
  `Block.resolve_ref_association/4` (display-media resolution),
  `Block.push_image_editor_init/3` (image editor from blocks).
- **Multi-user sync ships op snapshots** (`Ops.subtree_snapshot/2` →
  `Ops.apply_remote_snapshot/3`), never changesets. Ships fire on focus-settle
  (any focusout, via the Block JS hook), focus switch, pre-save force-ship and
  immediately on child structural ops; snapshots carry delete tombstones (child
  deletes have no structural broadcast of their own). Receivers DEFER a snapshot
  for the root they're editing (`pending_remote_snapshots`, applied on blur) —
  never drop it — and `ship_or_flush/2` suppresses unchanged re-broadcasts
  (`last_synced_snapshots`) so stale state can't clobber newer remote edits.
  Late joiners broadcast `{:blocks_sync_request, ...}`; diverged editors
  (`blocks_changed?`) replay state as the standard sync messages.
- **Delete undo is store replay**: local deletes stash `Ops.bin_snapshot/2` (structure +
  diffs + statuses + db ids + location) BEFORE the delete op; undo replays it via
  `Ops.restore_snapshot/2` — restored roots mount fresh from a re-materialized seed form,
  restored children reach their mounted root via the `replace_form` cascade. Restores
  broadcast `{:block_restored, ...}` (a uid left in a remote `deleted` list would kill the
  rows again on that editor's save); the bin clears on save (stashed db ids go stale).
