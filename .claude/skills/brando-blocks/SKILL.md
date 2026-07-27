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
source (Brando.Type.Module), identifier_metas (JSON),
sequence, creator_id, module_id, container_id, fragment_id, parent_id, palette_id
```

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
1. `mount/1` — minimal (just `{:ok, socket}`)
2. `update(assigns, socket)` — catch-all:
   - `assign(assigns)` → `initialize_blocks(assigns)` → `assign_templates()` → `assign_module_set()` → `reset_position_response_tracker()`
3. `initialize_blocks` — guarded by `blocks_initialized` assign:
   - Maps `entry_blocks` to forms via `to_change_form/4`
   - Creates `block_list` (list of UIDs), `root_changesets` (list of `{uid, nil}` tuples)
   - Sends initial position updates to all blocks

### Block
1. `mount/1` — sets `block_initialized: false`, empty `children_forms`, `position_response_tracker`, etc. Attaches `Events.attach_block_events/1` hook.
2. `update(assigns, socket)` — catch-all (runs on every update):
   - Assigns from parent, computes `uid`, `type`, `multi`, `has_vars?`, `has_table_rows?`, `has_children?`
   - Uses `assign_new` extensively — values set once on first render are NOT overwritten on subsequent updates
   - Calls `maybe_assign_children()`, `maybe_assign_module()`, `maybe_assign_container()`, `maybe_assign_fragment()`
   - `maybe_parse_module()` → `maybe_render_module()` → `maybe_get_live_preview_status()`
   - Sets `block_initialized: true`

**Key guard**: `assign_new` prevents re-initialization on validate. Changing a var triggers `validate_block` → new form → `update` → but `assign_new` preserves original values.

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
6. `render_and_update_block_changeset` → `send_form_to_parent`

**Entry block** (`"entry_block"` params):
1. Use `changeset.data` (original DB values) as base — NOT `apply_changes`
2. Same filtering: persisted table_rows, original block_identifiers, clear vars/refs for new
3. `block_module.changeset(block_for_changeset, params, user_id)` — runs full pipeline including `cast_assoc(:block)`
4. Check for container active status flip → force render
5. `render_and_update_entry_block_changeset` → `send_form_to_parent`

**Critical difference**: entry_block uses `changeset.data` as base; child_block uses `apply_changes`. This is because `cast_assoc` for entry_blocks compares params against `data` — using `apply_changes` would bake in previous edits and `cast_assoc` wouldn't detect them.

---

## 7. Event Flows

### Validation Flow
```
User types in block form
  → phx-change="validate_block" (target: block's @myself)
  → Events.handle_block_event("validate_block", params, socket)
  → Build changeset from params
  → render_and_update_*_changeset (renders Liquex template if module)
  → assign(:form, updated_form)
  → send_form_to_parent()  →  send_update(parent_cid, %{event: "update_block", form: form})
  → Parent (BlockField or Block) replaces form in entry_blocks_forms/children_forms by UID
  → maybe_update_live_preview_block()
```

### Save Flow (Changeset Collection Cascade)
```
Form sends: send_update(BlockField, event: "fetch_root_blocks", tag: :save)
  → BlockField: for each block_uid in block_list:
      send_update(Block, id: "block-#{uid}", event: "fetch_root_block", tag: :save)
        → Block (if has children): for each child:
            send_update(Block, id: "#{id}-child-#{uid}", event: "fetch_child_block")
              → Leaf Block: send_update(parent_cid, event: "provide_child_block", changeset: ...)
        → Block (if no children): send_update(parent_cid, event: "provide_root_block", changeset: ...)
  → provide_child_block: collects all child changesets, puts them via put_assoc(:children, ...)
    → When all collected: sends provide_root_block to BlockField
  → provide_root_block: BlockField collects into root_changesets
    → When all collected: sends provide_root_blocks to Form (via form_cid)
  → Form receives root_changesets, puts them into the main changeset for save
```

### Duplication Flow
```
Events.handle_block_event("duplicate_block")
  → If has children: send "fetch_changeset_for_duplication" to each child
    → Children cascade down, collecting changesets
    → When populated: parent receives "duplicate_block" with populated: true
  → duplicate_block (populated or no children):
    → apply_changes → clear IDs → generate new UID
    → Villain.duplicate_vars/duplicate_table_rows/duplicate_refs/duplicate_children
    → Insert into entry_blocks_forms/children_forms at sequence + 1
```

### Insert/Delete/Reposition
- **Insert**: `build_block`/`build_container`/`build_fragment` → insert into `block_list` and `entry_blocks_forms`/`children_forms` at sequence
- **Delete**: remove from `block_list`, reject from forms, update `root_changesets`/`changesets`
- **Reposition**: SortableJS fires `reposition` event → reorder `block_list`, `root_changesets`/`changesets`, forms to match new order → send position updates to all blocks

---

## 8. Parent-Child Communication

### Upward (Child → Parent)
- **`send_form_to_parent(socket)`** — after validate_block, sends updated form to parent via `send_update(parent_cid, %{event: "update_block", level: level, form: form})`
- **`provide_child_block`** / **`provide_root_block`** — during save cascade, child sends its changeset to parent
- **`signal_position_update`** — child confirms it received a position update

### Downward (Parent → Child)
- **`send_update(Block, id: ..., event: ...)`** — parent messages children for:
  - `fetch_root_block` / `fetch_child_block` (save cascade)
  - `update_sequence` (after reposition)
  - `enable_live_preview` / `disable_live_preview`
  - `clear_changesets`

### Position Response Tracker
Both BlockField and Block maintain a `position_response_tracker` — a list of `{uid, boolean}` tuples. After sending position updates to all children, it waits for all `signal_position_update` responses before triggering `update_live_preview` on the form.

---

## 9. Recovery Mechanism

### JS Hook (`BlockField/index.js`)
1. **`disconnected()`**: Captures all block form data from DOM (`FormData` → nested params) and root UIDs to `sessionStorage` keyed by `brando:block-recovery:{element-id}`
2. **`mounted()` / `reconnected()`**: Reads from sessionStorage, compares stored UIDs vs current DOM UIDs, sends `recover_blocks` event with missing UIDs + their form data

### Server Handler (`block_field.ex: handle_event("recover_blocks")`)
1. Receives `rootUids`, `missingUids`, `forms` (params keyed by form ID)
2. For each missing UID:
   - Creates base struct with empty associations (vars, refs, table_rows, children, block_identifiers)
   - Runs `block_module.changeset(base_struct, params_with_entry, user_id)` — full changeset pipeline
   - Sets `action: :insert`
3. Merges recovered forms with existing forms in original root_uids order
4. Reassigns `entry_blocks_forms`, `block_list`, `root_changesets`

This preserves ALL form field values (not just structure) because the recovered params go through the same changeset pipeline as normal validation.

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

### Position Response Tracker
After reposition, waits for all blocks to confirm their new sequence before triggering a preview update. Prevents partial/stale renders during reorder.

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
- **Purpose**: Block recovery after WebSocket disconnect
- **`disconnected()`**: Serializes all block forms' `FormData` + root UID order to `sessionStorage`
- **`mounted()` / `reconnected()`**: Compares stored UIDs vs current DOM, sends `recover_blocks` with missing block data
- Storage key: `brando:block-recovery:{wrapper-element-id}`

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
