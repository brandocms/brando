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

- **EntryBlock** is auto-generated per `module: :blocks` relation by `Brando.Blueprint.maybe_build_blocks_modules/3`, named after the relation (e.g. `Brando.Pages.Page.Blocks` for `relation :blocks`). It joins an entry to a `Block` and holds `sequence` and `entry_id`.
- **Block** holds the actual content: type, module/container/fragment references, vars, refs, children (recursive), table_rows. Slots (`type: :slot`) are children too.
- Blocks live **OUTSIDE** the main `<.form>` tag for performance — avoids sending all block data on every keystroke in the main form.
- Each block has its own `<.form phx-change="validate_block" phx-target={@target}>`.
- Changing footnotes, named block regions or `type: :slot` blocks: read [footnotes.md](footnotes.md) first.

---

## 2. Key File Paths

### Schemas
| File | Description |
|------|-------------|
| `lib/brando/content/block.ex` | Block schema (Blueprint): attributes, relations, `block_changeset`, `recursive_block_changeset` |
| `lib/brando/content/var.ex` | Var schema: typed variables (boolean, string, text, html, image, video, gallery, color, select, file, link, form, date, datetime) |
| `lib/brando/content/ref.ex` | Ref schema: polymorphic embed `data` field + media associations (image, video, gallery, file) |
| `lib/brando/content/container.ex` | Container schema |
| `lib/brando/content/module.ex` | Module schema: defines block templates with vars/refs |
| `lib/brando/content/table_row.ex` | TableRow schema for tabular data in blocks |
| `lib/brando/content/block_identifier.ex` | Join table between blocks and identifiers |
| `lib/brando/content/var/option.ex` | Options for select-type vars |
| `lib/brando/content/template.ex` | Block template schema |
| `lib/brando/content/table_template.ex` | Table template schema |
| `lib/brando/pages/fragment.ex` | Fragment schema |
| `lib/brando/content/blocks.ex` | `Brando.Content.Blocks`: build, duplicate, module sync, render fan-out |
| `lib/brando/content/block_slots.ex` | Slot policy (regions, footnotes); see [footnotes.md](footnotes.md) |

### LiveView Components
| File | Description |
|------|-------------|
| `lib/brando_admin/components/form/block_field.ex` | BlockField component: manages root entry_blocks, builds blocks/containers/fragments, handles recovery, reposition, save cascade |
| `lib/brando_admin/components/form/block.ex` | Block component: renders individual blocks, manages children, validate_block, refs, live preview |
| `lib/brando_admin/components/form/block/events.ex` | Event handlers: validate_block, duplicate, delete, reposition, table_row, identifier events |
| `lib/brando_admin/components/form/block/render.ex` | `Block.Render`: block markup, `block/1` with its `carried_config` |
| `lib/brando_admin/components/form/block_field/ops.ex` | `BlockField.Ops`: the pure op reducer and materialization |
| `lib/brando_admin/components/form/block_field/replica.ex` | `BlockField.Replica`: the field's replica of the edit session |
| `lib/brando/edit_session.ex` | `Brando.EditSession`: one process per open entry, orders and broadcasts ops |
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
| `lib/brando_admin/components/form/input/render_var.ex` | Var rendering component |
| `lib/brando_admin/components/form/input/blocks/utils.ex` | Block rendering utilities |

**Ref config fields must be listed in `carried_config`.** A ref's config
values have to reach every `validate_block`, but while the modal is closed
only the fields listed in the type's `carried_config` (on
`Block.Render.block/1`) are sent, as bare hidden inputs. Adding a field to a
`<:config>` slot without listing it drops its value on the next validate.
Use the kind its widget submits as: plain (`""` when nil), `{:radio, f}`,
`{:checkbox, f}` (`Input.toggle`) or `{:override, f}`
(`Input.override_toggle_group`). Hidden-only config that is a list or a nested
form belongs in the block body, not the slot.
`e2e/playwright/tests/blocks/block-ref-config-carried.spec.js` compares what
each ref type submits with its config closed and open; add new ref types there.

### Villain (Rendering & Block Types)
| File | Description |
|------|-------------|
| `lib/brando/villain.ex` | Rendering engine (`parse/3`, `render_block/3`); block data management lives in `Brando.Content.Blocks` |
| `lib/brando/villain/parser.ex` | Parser behaviour: per-type render callbacks, `process_refs`, `render_block_slot/2` |
| `lib/brando/villain/block.ex` | Base block behaviour and macros |
| `lib/brando/villain/blocks.ex` | Block type registry (lists all available block types) |
| `lib/brando/villain/blocks/*.ex` | Individual block type implementations (text, picture, video, header, gallery, etc.) |

### Context & Traits
| File | Description |
|------|-------------|
| `lib/brando/content.ex` | Content context: CRUD for Block, Container, Module, etc. |
| `lib/brando/traits/blocks.ex` | Blocks trait for Blueprint schemas |
| `lib/brando/traits/blocks/prevent_circular_references.ex` | Stops a fragment from embedding itself |
| `lib/brando/blueprint/villain.ex` | Blueprint villain integration |

### JS Hooks
| File | Description |
|------|-------------|
| `assets/src/hooks/BlockField/index.js` | Recovery: captures forms to sessionStorage on disconnect, restores missing blocks on reconnect; renumbers footnotes on update |
| `assets/src/hooks/Block/index.js` | Autosize textareas via `autosize` library; block-level field presence |
| `assets/src/hooks/SortableBlocks/index.js` | Drag-and-drop via SortableJS, fires `reposition` event |

### Tests
| File | Description |
|------|-------------|
| `test/brando/content_test.exs` | Content context tests |
| `test/brando/villain/villain_test.exs` | Villain rendering tests |
| `test/brando/villain/blocks/ref_apply_test.exs` | Ref apply_ref tests |
| `test/brando_admin/components/form/block_field/` | Ops reducer, field ops, preview root, reload after save |
| `e2e/playwright/tests/blocks/` | E2E tests (recovery, reorder, copy/paste, live preview, edit session, footnotes, media, …) |
| `test/support/edit_session_rejoin.ex` | Edit-session crash and rejoin through two real block fields (late rejoiner, unconfirmed ops, rows fixture); a rejoin test goes through it, never `EditSession.join/4` with built state |

---

## 3. Block Types

| Type | Description |
|------|-------------|
| `:module` | Standard block backed by a Module (template + vars + refs). Most common type. |
| `:container` | Groups child blocks. Has a container_id pointing to a Container record that defines allowed children and layout. |
| `:fragment` | References a shared Fragment. Read-only embed — edits happen on the Fragment itself. |
| `:module_entry` | Module block used within multi-blocks (when `multi: true`). Children of a `:module` block. |
| `:slot` | Owned collection under a module block or a rich-text field: a named region or a footnote. See [footnotes.md](footnotes.md). |

---

## 4. Schema Quick Reference

### Block Fields
```
uid, type (:module/:container/:fragment/:module_entry/:slot), active, collapsed,
description, anchor, multi, datasource, rendered_html, rendered_at,
source (Brando.Type.Module), identifier_metas (JSON), module_version, sync_uid,
slot_name, slot_kind (:region/:footnote), slot_module_set, slot_remap (virtual),
sequence, creator_id, module_id, container_id, fragment_id, parent_id, palette_id,
module_origin, container_origin, palette_origin (:local/:shared)
```

`module_version` and `sync_uid` are server-controlled and deliberately absent from
`@block_attrs` — see section 14.

### Block Relations
```
belongs_to: container, fragment, module, palette, parent (self-ref)
has_many: children (self-ref), vars, refs, table_rows, block_identifiers
has_many through: identifiers (via block_identifiers)
```

### Var Types
`:boolean`, `:string`, `:text`, `:html`, `:image`, `:video`, `:gallery`, `:datetime`, `:color`, `:select`, `:file`, `:link`, `:form`, `:date`

### Ref Structure
- `name` (text) — matches `{% ref refs.name %}` in Liquex templates
- `data` — PolymorphicEmbed (types from `Brando.Villain.Blocks.list_blocks()`: text, picture, video, header, media, gallery, svg, map, etc.)
- Media associations: `image`, `video`, `gallery`, `file` (each belongs_to with `on_replace: :nilify`)
- Standard preloads: `Brando.Content.Ref.preloads()` → `[:image, :file, video: [:thumbnail, :file], gallery: [gallery_objects: [:image, video: [:thumbnail, :file]]]]`

### EntryBlock Structure (auto-generated)
```elixir
# e.g. Brando.Pages.Page.Blocks — table "<owner table>_<relation>"
schema "pages_blocks" do
  belongs_to :entry, Brando.Pages.Page  # or whichever schema
  belongs_to :block, Brando.Content.Block, on_replace: :update
  field :sequence, :integer
  field :marked_as_deleted, :boolean, default: false, virtual: true
end
# changeset(entry_block, attrs, user, recursive? \\ false)
```

---

## 5. Component Lifecycle

### BlockField
1. `mount/1` — assigns defaults (`outline_items`, `undo_stack`, slot drawer state, `live_preview_active?: false`)
2. `update(assigns, socket)` — catch-all: `initialize_blocks/2` (guarded by `blocks_initialized` so it runs once), then joins the edit session
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
   - `maybe_assign_children` → `maybe_assign_module` → `maybe_parse_module`
   - Parent updates do not render preview HTML; validation selects the required
     preview transport before rendering.
   - Sets `block_initialized: true`

**Key guard**: `assign_new` plus the `Map.drop` above are what stop a parent re-render from
clobbering local editing state (the clobber/FK-wipe class of bug).

---

## 6. Form & Changeset Patterns

### `to_change_form` vs `to_form`
- **`to_change_form(block_module, entry_block_or_cs, params, user_id)`** — runs `block_module.changeset(entry_block, params, user_id)` before wrapping in `to_form`. Used when you want the changeset pipeline to run (casting, validation).
- **`to_form(changeset, as: ..., id: ...)`** — wraps an existing changeset directly. Used when you've already built the changeset manually (e.g. after `build_block`).

### Building New Blocks
```elixir
BlockField.build_block(module_reference, user_id, parent_id, source, type)   # :module or :module_entry
BlockField.build_container(user_id, parent_id, source)
BlockField.build_fragment(user_id, parent_id, source)
```
`build_block/5` delegates to `Brando.Content.Blocks.build_module_block/5` (`module_reference`
is a module id or `{origin, id}`) and returns a changeset with `action: :insert`, stamped with
the module's current version. `build_container/3` and `build_fragment/3` return a plain
`Changeset.change/2` (no action); the caller sets `:insert` on the entry-block wrapper.

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

`recursive_block_changeset/4` adds `cast_assoc(:children)` (recursive) and
`BlockSlots.validate/2`. Both first drop row params that name a saved row the block no
longer has (`drop_vanished_rows/3`). For new blocks (nil ID): filters out `:replace` action
from refs/vars, sets `sync_uid`, forces `:insert` action.

### validate_block — Two Variants

**Child block** (`"child_block"` params):
1. `apply_changes(changeset)` to get struct with in-memory modifications
2. Filter table_rows to persisted only (with IDs)
3. Restore `original_block_identifiers` from socket assigns
4. Clear vars/refs for new blocks (nil ID) to avoid duplicate PK warnings
5. `Block.block_changeset(block_for_changeset, params, user_id)`
6. `should_force_live_preview_update?/3` (see below)
7. `render_and_update_block_changeset` → `Block.assign_block_form/3` with `target:` (assigns `:form`, emits the field op)

**Entry block** (`"entry_block"` params):
1. Use `changeset.data` (original DB values) as base — NOT `apply_changes`
2. Same filtering: persisted table_rows, original block_identifiers, clear vars/refs for new
3. `block_module.changeset(block_for_changeset, params, user_id)` — runs full pipeline including `cast_assoc(:block)`
4. `should_force_live_preview_update?/3`: a block that owns children (container, slot, multi, or one with children) flipping `active: false` → `true` forces a full render
5. `render_and_update_entry_block_changeset` → `Block.assign_block_form/3` with `target:` (assigns `:form`, emits the field op)

**Critical difference**: entry_block uses `changeset.data` as base; child_block uses `apply_changes`. This is because `cast_assoc` for entry_blocks compares params against `data` — using `apply_changes` would bake in previous edits and `cast_assoc` wouldn't detect them.

---

## 7. Event Flows

### Validation Flow
```
User types in a block form
  → phx-change="validate_block" (target: the block's @myself)
  → Events.handle_block_event("validate_block", params, socket)
  → build the changeset from params
  → Block.assign_block_form/3   ← the chokepoint: assigns :form AND emits
                                   the changed fields as an op to BlockField's reducer
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
After the save completes, `reload_all_blocks/2` hands mounted roots a fresh form via
the `replace_form` cascade, so blocks stop diffing against pre-save nil-id data. It skips
a root only when `holds_persisted?/2` proves its mounted form already equals the saved row
(no store diff in its subtree, seeded row and materialized state both snapshot-equal to the
reload); everything else is re-seeded. Other reloads (hard reset, failed cross-parent move)
re-seed every root.

### Duplication Flow
```
Events.handle_block_event("duplicate_block")
  → has children: send "fetch_changeset_for_duplication" to each child, which reply with
    "provide_changeset_for_duplication" until the parent is `populated: true`
  → then: duplicate via ContentBlocks.duplicate_block/2, put a seed form, and apply an
    {:insert, uid, sequence, diff} op (a parent block emits {:insert_child, ...} instead)
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
  Root and container paste buttons are shown by CSS from `data-paste-allow`, which is
  rendered from `clipboard_meta`, so without that hydration a freshly opened entry shows
  no paste buttons.
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
All are **ops applied to the store** (`Ops.apply_op/2`), not list surgery:
`{:insert, uid, at, diff}`, `{:insert_child, parent, uid, at, diff}`, `{:move, uid, to}`,
`{:reorder, uids}`, `{:reorder_children, parent, uids}`, `{:move_to_parent, uid, parent, at}`,
`{:remap_slot, uid, destination, params}`, `{:delete, uid}`. Root-level
structure is applied by BlockField directly; everything else arrives from blocks through
`Block.emit_block_op/2`. Blocks read their position from the `list_index` prop supplied by
the keyed `:for` — never from a form's `sequence` field, which is stale by design.

---

## 8. Parent-Child Communication

### Upward (Child → Parent)
- **`block_op`** — the main channel. Carries a named op with **param diffs, never changesets
  or forms** (`Ops.block_diff_params/1`).
- **`provide_changeset_for_duplication`** — duplication only, as above.
- **`register_block_wanting_entry`** — sent to the Form, not the parent: a block whose module
  reads `entry.*` registers for the targeted entry fan-out.

### Downward (Parent → Child)
- **`replace_form`** — the ONLY sanctioned form handoff after mount. Used post-save and on
  applying other editors' ops, and it cascades down the tree. Anything else re-introduces the clobber
  class.
- Structural and UI messages: `set_collapsed`, `set_children_collapsed`, `insert_block`,
  `insert_pasted_block`, `paste_block`, `paste_child_block`, `outline_reorder_child`,
  `extract_child`, `update_ref`, `update_ref_data`, `update_block_var`,
  `update_entry_field`, `replace_entry`, `module_updated`.

> Blocks never hand forms upward and never confirm positions: position comes from the
> `list_index` prop. See "Block Editor: single-owner state & ops" at the end of this file.

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
1. Receives `rootUids`, `missingUids`, `forms` (params keyed by form ID), `childOrder`.
   Missing UIDs the store or the seed forms already know are dropped (`recoverable_uids/2`),
   and params are whitelisted and scrubbed of server-owned fields (`sanitize_recovered_params/4`)
2. For each missing UID:
   - Creates base struct with empty associations (vars, refs, table_rows, children, block_identifiers)
   - Grafts the captured child subtree onto the block params from `childOrder`, preserving order (sequence is derived from list position)
   - Runs `block_module.changeset(base_struct, params_with_entry, user_id, true)` — the **recursive** cast. The 3-arity variant has no `cast_assoc(:children)` and drops the subtree silently
   - Sets `action: :insert`
3. Merges recovered seed forms, applies an `:insert` op per recovered root, then one
   `{:reorder, uids}` to the pre-disconnect root order (`apply_recovered_block_ops/3`)
4. Replies `%{recovered: uids}` so the client can drop its snapshot

Form field values — vars, refs, table_rows — are preserved because the recovered
params go through the same changeset pipeline as normal validation. What is *not*
preserved is anything that had no DOM input to capture in the first place.

---

## 10. Live Preview

### Enable/Disable
`live_preview_active?` and `live_preview_cache_key` are attributes, rendered down
the tree in one pass:
```
Form (assigns) → BlockField attrs → root Block attrs → child Block attrs
  → no local HTML render; the initial full-page render already supplies it
```
Do not reintroduce a `send_update` per block for this: each one is its own
render and diff frame, which made opening the preview at 115 roots take 115
frames over ~0.8 s. A newly mounted block receives the attributes like any
other, so it needs no status query.

### Rendering
- **`render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?, force_render? \\ false, render_html? \\ true)`** — renders a child block's template, puts `rendered_html` and `rendered_at` into changeset
- **`render_and_update_entry_block_changeset(...)`** — same arguments, but navigates through the entry_block wrapper to the nested block
- `force_render?` — from `should_force_live_preview_update?/3`: a block that owns children flips from `active: false` to `active: true`
- The final `render_html?` argument comes from `render_live_preview_block?/1`.
  Slots, blocks in slots and single modules with children have their root
  rendered from the store and patched instead (`BlockField` "preview_root"), so
  their local validation skips HTML rendering. Media ref changes skip it before a reload.
  Entry-field updates refresh editor splits; Form renders the full preview.

### Update Trigger
After validate_block: `maybe_update_live_preview_block()` sends incremental HTML
or requests a full refresh. Form coalesces full refreshes before collecting
BlockField state; save/share collection remains separate.

### Reorder and preview
Reorder is a store mutation the BlockField applies in one place, so a preview
update after it waits on nothing: blocks do not confirm their new positions.

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

### Blocks Decoded From Old Revisions
A decoded revision holds blocks, vars and table rows as they were stored: fields added since (`module_version`, `sync_uid`) are missing keys, and `block.sync_uid` raises `KeyError`. Read them with `Map.get/2`; see the `Brando.Revisions` moduledoc, "Old snapshots".

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
- **Purpose**: Auto-resize textareas, and block-level field presence for root blocks
- Uses `autosize` library on elements with `[data-autosize]` attribute
- Re-runs on `mounted()` and `updated()`
- Pushes `block_focused` (`{uid, field, label}`) on focusin/pointerdown and `block_blurred`
  (`{uid, still_inside}`) once focus settles; `.ref_block` elements skip both

### `Brando.SortableBlocks` (`assets/src/hooks/SortableBlocks/index.js`)
- **Purpose**: Drag-and-drop reordering via SortableJS
- Config: `handle` from `data-sortable-handle` (default `'.sort-handle'`), `animation: 150`, `forceFallback: true`
- **`onEnd`**: Pushes the `data-drop` event (default `reposition`) with `{old: oldIndex, new: newIndex, to: to.dataset, from: from.dataset, ...item.dataset}`, then renumbers footnotes
- Prevents `phx-blur` from firing during drag (`focusout` stopImmediatePropagation)
- Optional grouping via `data-blocks-wrapper-type` for cross-container drag

---

## 14. Module Saves Are Site-Wide Migrations

Saving a module re-syncs **every block that uses it, in every entry**:

`Content.update_module` (generated by `mutation :update, Module`) → `Blocks.render_entries_with_module_id/2`
→ `list_block_ids_using_module/2` → `sync_blocks/3` → `Blocks.sync_module/2`
(one `Repo.update/1` per block, outside a transaction), then the entries holding those
blocks are queued for re-render.

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
  picture / video / gallery / svg / file block refs, each of which has a `MediaBlock`
  clause in `apply_ref/3`. Use `Brando.Villain.Blocks.ref_types_compatible?/2`
  rather than comparing structs — treating that as a retype puts a warning in
  front of every media module edit.
- **Never trust `module_version` from params.** It is not in `@block_attrs`. An
  entry editor opened before a migration must not be able to save its way to
  claiming it is current.

### Classifying a pending module change

`ModuleDiff.diff(old_module, new_module_or_changeset)` returns a `%ModuleDiff{}`;
`classify/1` gives `:none` | `:metadata` | `:render` | `:compatible` | `:destructive`
(most severe wins) and `effective?/1` is `classify/1 != :none`. `destructive?/1`
gates the module editor's confirmation dialog; `summary/1` gives the lines it
shows.

`Module.uid` is lineage identity for definition imports and saved-content
transfers. Configuration → Content transfer resolves lineage to a
destination-local ID and stamps new blocks with the destination module version.
The module list's own Import / export (copy/paste of definitions) mints fresh UIDs
at version 1.
See [Content import and export](../../../guides/content_transfer.md) for the
archive, dependency, permission and recovery contracts.

---

## Block Editor: single-owner state & ops

Each block is its own `live_component` and **owns its editing state exclusively** —
after first mount, a parent re-render can never overwrite a block's form (`Block.update/2`
drops incoming `:form`/`:children` assigns once initialized). Forms never travel between
components. The parent (`BlockField`) owns **order + structure + a uid-keyed param-diff
store** (`BlockField.Ops` — a pure, unit-tested reducer over
`{order, parents, child_order, diffs, statuses, db_ids, rel_ids, row_order, keys, deleted}`).

- **Every mutation is a named op applied by the reducer.** Children emit
  `{:update, uid, params_diff}`, `{:insert_child, parent, uid, at, params}`,
  `{:set_field, uid, path, value, rev}`, `{:reorder_children, parent, uids}`, `{:delete, uid}` etc.
  via `Block.emit_block_op/2`;
  BlockField applies its own ops for root-level structure. Ops carry **param diffs, never
  changesets or forms** (`Ops.block_diff_params/1`: persisted records diff by changes, NEW
  records snapshot full applied state — builders pre-populate changeset *data*, so a
  changes-only diff would drop `module_id`/vars/refs).
- **The chokepoint: `Block.assign_block_form/2,3`.** Every handler that rebuilds a block's
  form MUST assign it through this helper — it assigns `:form` AND emits the op for the
  fields that changed (see "An event sends the fields it changed" below), keeping the
  store save-complete. Assigning `:form` directly
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
  (cascades down the tree): used post-save (re-seed with fresh db ids) and when other
  editors' ops arrive. Anything else re-introduces the clobber/FK-wipe class.
- **Media commits: use `Block.commit_ref_data/2`** for one-shot ref commits
  (picker select / reset / upload-complete / image-editor) — never raw
  `send_update(..., event: "update_ref_data", ...)`. Not for per-keystroke updates.
  Related helpers: `Block.current_block_data_map/3` (ref_data payloads),
  `Block.resolve_ref_association/4` (display-media resolution),
  `Block.push_image_editor_init/3` (image editor from blocks).
- **Multi-user editing goes through the entry's edit session** (`Brando.EditSession`,
  one process per open entry, Livebook's model). Each BlockField's store is a replica
  (`BlockField.Replica`): BlockField's `apply_block_op/3` applies a local op at once, records
  it as pending (`Replica.local/2`) and casts it to the session, which applies it with the SAME reducer, gives it a revision and broadcasts it;
  other editors' ops arrive as `{:edit_session, field, message}` (routed by the form
  hooks) and go onto the replica's confirmed state with this editor's unconfirmed ops
  replayed on top, so everyone converges on the session's order. There is no snapshot
  shipping and no late-joiner request: a joiner gets the session's state. Remote changes
  refresh affected roots through `replace_form` (coalesced); a root the local user works
  in (`@local_focus`) is refreshed without re-booting the focused input
  (`remount_js: :skip_focused`) and once more when they leave the field. Save, preview, share and recovery copies
  read `EditSession.fetch/3`; after a save the BlockField hands the saved rows to
  `EditSession.rebase/4`, which replays only the ops that arrived during the save and moves
  every replica onto the new rows. A revision loaded as a working copy (revisions drawer,
  Form `:load_working_copy`) is unsaved CHANGES on top of the current rows — never the
  form's data: the Form casts the revision's params (`Revisions.restore_params/2`) over the
  saved entry, and each BlockField (`"load_working_copy"`) replays its blocks through
  `restore_draft/3` (blocks the entry lost come back with fresh uids). The BlockField lets
  its replica go (no `:DOWN` rejoin) and calls `EditSession.detach/2`, which marks the
  session's revision; when that editor then writes the entry (activation, or a save, whose
  rejoin rebases even when the rows' ids did not change), the rebase keeps only ops after
  the mark instead of carrying the replaced work back. Anything that replaces the editor's blocks
  wholesale must go through the session as ops or detach like this — never leave the
  session holding work the editor no longer shows. Writes outside the editor (Assistant apply, revision
  activation in `Revisions.set_entry_to_revision`, content transfer, stale-block upgrades in
  `Brando.Content.StaleBlocks`) call
  `EditSession.sync_saved/1` (`Ops.carry/3`), which waits for the surrounding
  `Brando.Repo.transaction/2` to commit (`Brando.Repo.after_commit/1`) and is dropped on
  rollback — never sync from uncommitted rows. A rebase that reloads the Form's rows while a
  save has collected its blocks but not written them makes the Form collect again
  (`recollect_blocks/2`): blocks collected from the old rows would delete what the other
  write added. If the session
  dies, each replica rejoins with what it holds and the session CARRIES that onto its
  state (`Data.join/5` → `{:merged, conflicts}`) — never resend only pending ops. The
  session tracks the last op seq it handled per client and returns it with every
  state/rebase, so `Replica.reset/2` drops pending ops it already folded in. A carry
  conflict (another save removed a block this editor had unsaved work in) comes back to
  that editor as a new block (`<uid>-kept`, or `-kept-2` and on when taken; its refs with
  new uids) with a toast — keep
  conflicts explicit, never drop work silently. The session groups the conflicts by the
  top-most block the write removed (`group`) and asks ONE editor per group to bring back
  everything under it as one copy, `<group>-kept` (`rescues` in the rebase message): an
  editor here who changed them (it keeps each editor's changed uids, `Ops.op_uids/1`, also
  after they leave), else any editor here (`orphan?`). Excluded: a dead process, a read-only
  editor, and the caller whose replica moves on with the reply (a join, the replica's own
  `EditSession.rebase(..., replica: true)`) — but NOT the process behind `sync_saved/1`,
  whose block fields see the broadcast (activating a revision from one's own drawer).
  Every replica computes its payload; the rescuer inserts, then calls
  `EditSession.rescued/3`; the session confirms from its state (the copy is there,
  whoever's insert put it there), broadcasts `:rescued`, and each editor toasts for its
  own work (`owners`) or, if it was there at the removal (`present`), an orphan's. No copy
  after the ack, no answer within `rescue_timeout`, or the rescuer leaving: the next is
  asked (`:rescue`); with nobody left the session waits once more for a late insert, then
  reports failure; with nobody able at all, failure is reported at once. A copy is never
  made twice (no fresh uids). Work only a rejoining editor held comes back from the join's
  reply (`rescues` in `info`). Only the top-most removed block this
  editor worked in comes back (a child added to a removed container brings the container
  back with it), and the toast says so only for blocks that did come back. A rescued child
  goes back under its nearest ancestor that is still there (`{:insert_child, ...}`); removed
  ancestors in between come back as `-kept` shells holding only the path to it, and with no
  surviving ancestor the top shell is a root — a child is never brought back as a root on
  its own. Applying a recovery copy is a `{:carry, carried, base}` op (two `Ops` states) over the
  session state, not a state replacement. Editors without `:update` on the entry join
  read-only (the session refuses their ops). Ops must stay pure: the session and every
  replica must reach the same state from the same ops.
- **An event sends the fields it changed**: `Block.assign_block_form/2` compares the
  block's form before and after (`Ops.field_op/5`) and emits `{:set_field, uid, path,
  value, rev}` for one changed leaf, `{:set_fields, uid, [{path, value}], rev}` for
  several, nothing for none — never the whole diff, so another editor's in-flight change
  to a different field survives. List items are named by `id`/`uid`/`key`/`sync_uid`
  (never by index). A list that gained, lost or reordered items goes as `{:list, before,
  after}`, which the reducer merges by identity with the list as it is now
  (`Ops.merge_list/3`), so two editors each adding an item both keep it; a list whose
  items have no identity, or two items named alike, is set whole, last arrival wins. A row's
  `id` comes first; an item without one is named by what it holds: a select var's option by
  its `value`, a new gallery object by its `image_id`/`video_id` (`identity/2`). Nothing
  extra is stored. Within a
  second of a `replace_form` the event can carry the browser's old values for what that
  change touched: `@replaced` keeps the form before AND the one that replaced it, and a
  leaf is dropped only where the two differ and the event sets it back to the old value
  — never drop a field the remote change did not touch (a backspace, a toggle set back),
  nor the event's own `_target` field (`assign_block_form/3`'s `target:`), which is a
  deliberate change even when it restores the old value.
  A field op made while its rows were new names them by uid; the reducer
  matches uid- and id-named items through `rel_ids`, so both land on one row. `{:update,
  ...}` remains only for forms that cannot be compared. Last arrival wins per field. The
  replica's pending ops keep this editor's value until the session confirms it. Other
  editors' changes refresh a root even while it is in use (`remount_js: :skip_focused`);
  the input with the focus keeps its value (LiveView, and
  `Presence/pendingInputs.js` for rich text's hidden input) and takes another editor's
  value when the editor leaves it, if they did not type since. Server answers to this
  editor's own earlier keystrokes are never noted (`test/javascript/pending_inputs.test.mjs`).
- **Order is fractional keys in the session** (`BlockField.FractionalKey`, `Ops.keys`):
  local inserts and moves are rewritten to `{:key, key}` positions (`Ops.keyed/2`) so
  two inserts at one place both land there. Saves still write the integer `sequence`
  from list order; there is no key column.
- **Delete undo is store replay**: local deletes stash `Ops.bin_snapshot/2` (structure +
  diffs + statuses + db ids + keys + location) BEFORE the delete op; undo replays it as a
  `{:restore, snapshot}` op — restored roots mount fresh from a re-materialized seed form,
  restored children reach their mounted root via the `replace_form` cascade. The op reaches
  the other editors through the session (a uid left in a remote `deleted` list would kill
  the rows again on that editor's save); the bin clears on save (stashed db ids go stale).
