# Block editor form audit (04-blocks)

Scope: `block_field.ex`, `block.ex`, `block/events.ex`, `block/render.ex`,
`block_field/ops.ex`, `block_changeset_list.ex`, `outline.ex`, `module_picker.ex`,
`Brando.Content.Block/Var/Ref`, `input/vars.ex`, `input/blocks/render_var.ex`,
checked against `.claude/skills/brando-blocks/SKILL.md`.

Verification legend: **[verified]** = proven by running code (`mix run` probe) or by an
unambiguous read of both sides; **[inferred]** = read-only reasoning, no runtime proof.

---

## Ranked findings

### 1. DATA-LOSS — a persisted CHILD block only ever stores its *last* edit in the op store [verified]

`Events.handle_block_event("validate_block", %{"child_block" => params})` rebuilds the
child changeset on top of `apply_changes`:

`lib/brando_admin/components/form/block/events.ex:717`
```elixir
applied_block = Changeset.apply_changes(changeset)
```
`lib/brando_admin/components/form/block/events.ex:738-740`
```elixir
updated_changeset =
  block_for_changeset
  |> Brando.Content.Block.block_changeset(params, current_user_id)
```

The resulting form goes through the chokepoint, which diffs by **changes**:

`lib/brando_admin/components/form/block.ex:1700-1704`
```elixir
def assign_block_form(socket, form) do
  socket
  |> assign(:form, form)
  |> emit_block_op({:update, socket.assigns.uid, Ops.block_diff_params(form.source)})
end
```
`lib/brando_admin/components/form/block_field/ops.ex:603-604`
```elixir
def block_diff_params(%Changeset{data: %{id: nil}} = changeset), do: snapshot_params(changeset)
def block_diff_params(%Changeset{} = changeset), do: changes_to_params(changeset)
```

and the reducer **replaces** the stored diff wholesale (documented + unit-tested:
`ops.ex:187-194`, `test/brando_admin/components/form/block_field/ops_test.exs:54`
`"replaces the diff wholesale"`).

Because the base is `apply_changes`, every previous edit is baked into `data`, so the
next keystroke's changeset carries **only the newest field**. Proven with a probe against
the real `Block.block_changeset/3`:

```
diff after edit 1 (description): %{"description" => "abc"}
diff after edit 2 (anchor):      %{"anchor" => "z"}     # description is gone
```

Failure scenario: inside a multi block or container, edit a child's description, then
edit any other field of that same child, save → the description reverts to the DB value.
Root blocks are safe: the entry-block clause rebases on `changeset.data`
(`events.ex:779 original_data = changeset.data`), which keeps the diff complete —
this asymmetry is exactly what SKILL.md §6 "Critical difference" describes, but the doc
never notices it breaks the store invariant it states in the Phase-3 section
(`ops.ex:26-28`: *"diffs hold the latest params snapshot of a block's changes vs. its
persisted data"*). **DOC-DRIFT as well.**

Surgical fix (pick one):
* make `Ops` merge instead of replace for `:update` (deep-merge params), or
* emit `snapshot_params/1` for child blocks (`block_diff_params` currently keys off
  `data.id == nil`; key it off the *rebase strategy* instead), or
* rebase the child clause on the original persisted struct the way the entry clause does
  and keep the accumulated diff as the params source.

### 2. DATA-LOSS — picking media on a **persisted** ref is discarded by the next keystroke [inferred, high confidence]

Ref media commits write to the changeset's *changes* only:

`lib/brando_admin/components/form/block.ex:750-756`
```elixir
updated_ref =
  updated_ref
  |> put_change_if_key_exists(:image_id, params)
  ...
```

but the ref's identity carrier deliberately stops emitting the FKs once the ref is saved:

`lib/brando_admin/components/form/block/render.ex:1241-1249`
```elixir
<%= if ref_form[:id].value in [nil, ""] do %>
  <Input.input type={:hidden} field={ref_form[:description]} />
  ...
  <Input.input type={:hidden} field={ref_form[:image_id]} />
```

and the entry-block validate clause rebases on `changeset.data`
(`events.ex:779`), which still holds the *old* `image_id`. So: params don't carry it,
data doesn't carry it → the rebuilt changeset has no `image_id` change → the wholesale
diff replacement (finding 1's mechanism) drops it from the store → save keeps the old
image, and the form itself reverts.

The var side already solved exactly this and documents why
(`render.ex:2034-2039` `value_fields/1`: *"an edit made while the config modal was open
lives in the changeset's changes … a value missing from the params is an edit lost"*).
Refs never got the same treatment.

Fix: move `image_id`/`video_id`/`gallery_id`/`file_id` out of the `if unsaved` branch in
`render.ex:1241` (keep `name`/`uid`/`description` gated) — mirrors `carried_var_value/1`.
Note `Ref` cast list lacks `:gallery_id` (`lib/brando/content/block.ex:271-287`), so add it
there if the gallery FK is meant to round-trip.

### 3. BUG (crash) — three block-config actions call `get_embed`/`put_embed` on `:refs`, which is a `has_many` in this branch [verified]

`refs` moved from `embeds_many` to `has_many` (`lib/brando/content/block.ex:111-115`),
but events.ex still uses embed APIs:

`lib/brando_admin/components/form/block/events.ex:252` (also `:271`, `:310`, `:330`, `:366`, `:369`)
```elixir
Changeset.get_embed(changeset, :refs)
```

Probe result:
```
get_embed(:refs) RAISES: expected `refs` to be an embed in `get_embed`, got: `assoc`
```

The three buttons that reach this are live in the UI: `render.ex:1046` (`reset_ref`),
`:1055` (`fetch_missing_refs`), `:1058` (`reset_refs`). Clicking any of them crashes the
LiveView process (all block state lost, recovery kicks in). Fix: `get_assoc`/`put_assoc`.

### 4. BUG — root-block config actions rebuild the form with `uid = nil` [verified]

`events.ex:242` / `:295` / `:353` / `:390` / `:443` / `:480` / `:536`
```elixir
uid = Changeset.get_field(changeset, :uid)
```
For `belongs_to == :root`, `changeset` is the **entry_block** changeset, which has no
`:uid` field (`lib/brando/blueprint.ex:308-313` — schema is entry/block/sequence/
marked_as_deleted). Probe: `get_field(:uid)` returns `nil` silently.

So `fetch_missing_vars` / `reset_vars` / `reset_var` / `delete_var` (and the three
crashers above) build `to_form(..., id: "entry_block_form-")` on root blocks. Effects:
every input id inside the block changes, the `<form>` element id changes (morphdom
replaces the subtree, focus lost), and the JS recovery hook — which keys on
`entry_block_form-${uid}` (`assets/src/hooks/BlockField/index.js`) — can no longer
recover that block. Fix: use `socket.assigns.uid` (what `validate_block` already does).

### 5. DATA-LOSS — block recovery drops every child block [verified]

`lib/brando_admin/components/form/block_field.ex:1176-1178`
```elixir
entry_block_cs =
  block_module.changeset(base_struct, params_with_entry, user_id)
  |> Map.put(:action, :insert)
```
3-arity ⇒ `recursive? = false` ⇒ `Block.maybe_cast_recursive/3` uses `block_changeset`,
which has **no** `cast_assoc(:children)` (`lib/brando/content/block.ex:149-166`). Compare
the save path, which is explicit about this being load-bearing
(`block_field.ex:394-395`: *"recursive?: true is load-bearing — the default block cast
drops \"children\" params entirely"*).

The JS hook compounds it: it captures every block form, then throws the children away
before sending:
```js
if (formId === `entry_block_form-${uid}`) { missingForms[formId] = formData }
```
Scenario: LV process dies with an unsaved container/multi block ⇒ on reconnect the root
comes back **empty**; all its unsaved children are gone. SKILL.md §9 claims recovery
"preserves ALL form field values" — **DOC-DRIFT**.
Fix: pass `true` as the 4th arg and nest the captured `child_block_form-*` params under
the root's `block[children][]` in the hook (child uid → parent is derivable from the
DOM's `data-parent_uid`).

### 6. SECURITY — `recover_blocks` casts client params straight into inserts [verified]

`block_field.ex:1140-1177`. Only `entry_id` is forced:
```elixir
params_with_entry = Map.put(entry_block_params, "entry_id", to_string(entry_id))
```
Everything else is attacker-controlled, and the two cast lists are permissive:
* `blueprint.ex:318` — `cast(attrs, [:entry_id, :block_id, :sequence])`: a crafted
  payload with `"block_id" => <other entry's block>` and no `"block"` key attaches an
  existing foreign block row to this entry (join row insert; the unique index on
  `[entry, block]` is the only guard).
* `lib/brando/content/block.ex:18-35` `@block_attrs` — includes `:parent_id`,
  `:creator_id`, `:module_id`, `:source`, `:identifier_metas`. A recovered block can be
  parented under an arbitrary block id (cross-entry child injection) and attributed to
  another user.
* Nothing validates that `missingUids` were ever rendered for this entry, and the uid used
  is read back out of the params (`:1181`), not from `missing_uids` — a mismatch inserts a
  seed under an unrelated uid (or `nil`, which then flows into `seed_forms`/`ops.order`).

Attacker is an authenticated admin, so severity is "privilege boundary within admin", not
anonymous RCE — but it is unvalidated client input reaching `Repo.insert`.
Fix: reject params whose `uid` is not in `missing_uids`; drop `block_id`/`parent_id`/
`creator_id` from the recovered params (force `creator_id` to `current_user.id`); cap the
number of recovered blocks.

### 7. DATA-LOSS — outline cross-parent move ships the child's **mount-time seed**, not its current state [verified by read]

`lib/brando_admin/components/form/block.ex:198-219`
```elixir
# Get the child changeset from the seed form (changesets list may have nil values)
child_form = Map.get(children_forms, uid)
child_changeset = child_form && child_form.source
...
send_to_ref(socket.assigns.parent_ref, %{event: "insert_extracted_child", ... child_changeset: child_changeset, ...})
```
`children_forms` is, by design, a *mount seed map* ("read once at a child's first mount,
never reconciled" — `block.ex:1588-1593`). The target parent then re-registers the store
diff from that stale changeset:

`block.ex:157`
```elixir
|> emit_block_op({:insert_child, socket.assigns.uid, uid, sequence, Ops.block_diff_params(block_cs)})
```
For a known uid, `Ops.apply_op` does `move_to_parent` **and** `register_params`
(`ops.ex:177-181`) — so the child's accumulated diff is overwritten with the seed's
(empty for a persisted child; mount-state for a new one). Every edit made since mount is
lost, and the remounted component renders the stale seed.

`test/brando/content/blocks_cross_parent_move_test.exs:118-119` asserts the opposite
("the diff ships the child's current content, as the extract path does") by hand-building
a diff — the production path does not do this.
Fix: don't ship a changeset. Have `BlockField` apply `{:move_to_parent, uid, target, seq}`
and hand the target parent a form materialized from the store
(`Ops.materialize_root` + `replace_form`), which is the sanctioned handoff.

### 8. BUG — `:video` / `:gallery` block vars and every var `config_target` cannot survive a cast [verified by read]

`lib/brando/content/block.ex:37-66` `@var_attrs` has `:image_id` and `:file_id` but **not**
`:video_id`, `:gallery_id`, `:config_target`, `:gallery_allowed_types`,
`:gallery_image_config_target`, `:gallery_video_config_target` — all of which exist on
`Brando.Content.Var` (`lib/brando/content/var.ex:26-55`) and all of which the editor
renders and commits:
* `render_var.ex:836` `<Input.hidden field={@var[:video_id]} …/>`, `:870` `gallery_id`
* `block.ex:988-1000` writes `:"#{type}_id"` for `type in [:file, :image, :video, :gallery]`

Both the DOM round-trip and the store diff therefore reach `var_changeset/4`, which drops
them. A video/gallery var picked in a block is silently lost on the next validate and at
save. `config_target` is only rendered under `@edit` (`render_var.ex:784-791`, `:820-827`,
`:852-859`, `:886-896`), i.e. never in the block editor, so an **unsaved** block's var
(where validate clears `vars` and rebuilds from params — `events.ex:730-736`) loses its
upload config target on the first keystroke.
Fix: add the six fields to `@var_attrs`; add hidden carriers for `config_target` and the
gallery config fields in the unsaved-var branch (`render_var.ex:573-582`).

### 9. DATA-LOSS (conditional) — refs the template does not reference are deleted on the first keystroke [inferred]

`render.ex:1204-1252` only emits inputs for refs whose name matches a `{:ref, name}` split,
and the splits come from module code that has already been stripped:

`block.ex:2130-2136` `liquid_strip_logic/1` removes `{% if %}…{% endif %}`,
`{% unless %}`, `{% for %}…{% endfor %}` and `{% hide %}` regions **entirely**.

So a `{% ref refs.x %}` inside an `if`/`for` produces no form inputs. With
`relation :refs, :has_many, on_replace: :delete_if_exists` + `cast_assoc(:refs)`, a params
list that omits an existing ref marks it `:replace` ⇒ the row is deleted at save (and
`Ops.changes_to_params` drops `:replace` changesets, so the store agrees). The
"Fetch missing refs" button and the "Ref … is missing!" panel exist precisely because
refs go missing.
Caveat: if *no* ref renders at all the `"refs"` key is absent and `cast_assoc` is a no-op,
so only *partially* referenced modules are affected. Worth an e2e reproduction before
fixing.
Fix: emit an identity-only hidden carrier (id + `_persistent_id`) for every ref not
rendered by a split — same shape as `carried_var_value/1`.

### 10. PERF (mount) — every block copies the containers, fragments and palette lists into its own assigns

`lib/brando_admin/components/form/block.ex:926-937` (generic `update/2`, runs for **all**
block types):
```elixir
|> assign_new(:containers, fn -> Brando.Content.list_containers!(%{... cache: {:ttl, :infinite}}) end)
|> assign_new(:fragments, fn -> Brando.Pages.list_fragments!(%{... cache: {:ttl, :infinite}}) end)
```
`block.ex:1179-1185` — the `container_id == nil` clause (i.e. every module block):
```elixir
|> assign_new(:palette_options, fn -> Brando.Content.list_palettes!(%{cache: {:ttl, :infinite}}) end)
```
`cache:` is Cachex/ETS (`lib/brando/cache.ex`), and an ETS read **copies** the term into
the calling process. With 50 root blocks that is 50 copies of every container, every
fragment and every palette held for the session, for markup only `container_config/1` and
`fragment_config/1` ever read. Fix: move `:containers`/`:palette_options` into the
`maybe_assign_container` container-branch and `:fragments` into the `fragment_id != nil`
branch of `maybe_assign_fragment`. This is the cheapest mount win in the file.

### 11. PERF/IDIOM — PubSub subscribe + a global sync broadcast happen on the dead render

`block_field.ex:656-658`
```elixir
if blocks_topic do
  Phoenix.PubSub.subscribe(Brando.pubsub(), blocks_topic)
end
```
`block_field.ex:672` `|> request_blocks_sync()`

`update/2` on a LiveComponent runs during the static HTTP render too, so every page load
subscribes a soon-dead process **and** broadcasts `{:blocks_sync_request, …}`. Each
connected editor whose store diverged then replays its whole state
(`block_field.ex:546-593`), which on the receivers means `replace_form` + a
`b:component:remount_block` push per root — i.e. a stranger loading the page can remount
your tiptap widgets. Iron law: check `connected?/1`. Fix: guard both calls with
`Phoenix.LiveView.connected?(socket)`.

### 12. BUG (minor) — `has_vars?` is latched at mount and then lied to by the renderer

`block.ex:905-911` (`assign_new(:has_vars?, …)`) is never updated, yet
`block.ex:1960-1969`
```elixir
defp reset_empty_vars(block, false, true), do: put_in(block, [Access.key(:block), Access.key(:vars)], [])
```
forcibly blanks vars before rendering. After "Fetch missing vars"/"Reset all variables" on
a block that mounted with no vars, live preview renders the block with no vars forever.
(`has_table_rows?` *is* refreshed — `events.ex:945`.) Fix: re-assign `has_vars?` in the
var handlers.

### 13. BUG (minor) — `liquid_splits` are never rebuilt on `replace_form`

`block.ex:561-593` (`replace_form`) reassigns form/children but not `liquid_splits`, and
`maybe_parse_module` is guarded by `block_initialized` (`block.ex:1378-1382`). After a
remote-sync apply or an undo restore, the in-editor liquid preview keeps showing the
previous editor's variable values. Fix: recompute splits (or call
`update_liquid_splits_entry_variables`-style refresh) inside `replace_form`.

### 14. DEAD — `reject_deleted` matches a field name that does not exist

`lib/brando/content/blocks.ex:923`
```elixir
%{changes: %{mark_as_deleted: true}}, acc -> acc
```
The field is `marked_as_deleted` (`lib/brando/blueprint.ex:312`). The clause can never
match. Related dead weight: `marked_as_deleted` is rendered as a hidden input twice per
block (`render.ex:644`, `:926`) but is not in `@block_attrs`, so it is never cast — the
delete path is the op store now. Fix: delete the clause (or spell it correctly) and drop
the hidden inputs.

### 15. IDIOM — three parallel child structures that can drift

A parent block keeps `@block_list` (order truth), `@children_forms` (seed map) **and**
`@changesets` (the legacy `[{uid, cs|nil}]` duplication tracker), each mutated separately
in six handlers (`block.ex:142-228`, `:233-319`, `:475-524`, `events.ex:636-664`). Two
concrete smells:
* `block.ex:174-179` and `events.ex:651-656` rebuild `changesets` with
  `Enum.map(new_block_list, &Enum.find(changesets, …))`, which yields `nil` entries when
  the two lists disagree; the duplication path then calls `elem(&1, 1)` on them
  (`block.ex:388-389`) and would raise.
* `extract_child` (`block.ex:203-224`) updates `block_list`/`changesets`/`children_forms`
  but emits **no** op — the store only catches up when the target parent's
  `insert_child` arrives.
Fix (non-architectural): derive `changesets` from `block_list` at use-time (it only exists
to gate the duplication gather), or key it as a map.

### 16. IDIOM / robustness — client-supplied indices and ids used unguarded

* `block_field.ex:274` `String.to_integer(module_id)` and `build_block/5` →
  `get_module/1` returns `nil` for an unknown id → `module.refs` raises.
* `block.ex:164-172` and `events.ex:644-647` use `List.delete_at(old_idx)` from the
  client instead of `List.delete(list, uid)`; a wrong index removes the wrong sibling.
* `block_field.ex:1122` `sequence: length(order) + 1` is off by one (harmless only
  because `Ops.clamp/2` clamps).
* `block_field.ex:80` / `:113` `Enum.find_index(...) + 1` raises `ArithmeticError` if the
  uid has already been removed (duplicate of a deleted block).

### 17. DOC-DRIFT — SKILL.md still documents the position-response tracker

SKILL.md §10 ends with a "### Position Response Tracker … waits for all blocks to confirm
their new sequence" paragraph, contradicting §8's own note ("There is **no**
position-response tracker … removed with it") and the code
(`block_field.ex:1213-1223` `refresh_live_preview/1` fires immediately). Also §9's
recovery claim (finding 5) and §6's statement that new-block filtering happens in
`block_changeset` should mention `finalize_new_block/2` by name. Fix: delete §10's last
paragraph, correct §9.

---

## Answers to the specific audit questions

**Changeset handling.** `block_changeset/3` and `recursive_block_changeset/3`
(`lib/brando/content/block.ex:153-208`) are consistent; `finalize_new_block/2` correctly
strips `:replace` refs/vars and forces `:insert` for pk-less blocks. AGENTS.md rules:
* *maps not nil-id changesets for multiple new records* — respected in the paths that
  matter (`events.ex:411-414` `var_struct_to_map`, `events.ex:875-881`,
  `block.ex:2462-2487` gallery objects). The one place multiple nil-id **changesets** are
  passed to `put_assoc` is the save itself
  (`form.ex:4470 put_assoc(changeset, :"entry_#{field}", updated_block_cs)`), where each
  changeset carries a distinct `data` struct, so Ecto's pk matching is not what
  disambiguates them. No failure observed in tests; leaving as a watch item, not a finding.
* *NotLoaded guards* — present (`block.ex:944-951`, `events.ex:1007-1013`,
  `ops.ex:629-631`, `block.ex:569-573`).
* *avoid duplicate PK after `apply_changes`* — implemented in both validate clauses
  (`events.ex:730-736`, `:809-814`).
* *`on_replace` for belongs_to* — `Ref` uses `:nilify` on image/video/gallery/file
  (`lib/brando/content/ref.ex:42-45`); entry_block `belongs_to :block` uses `:update`
  (`blueprint.ex:310`). Correct.
* `Ref` cast list omits `:gallery_id` (`block.ex:271-287`) while the form renders it —
  see finding 2.

**Single-owner model.** Holds structurally: `BlockField` owns `block_ops`/`root_order`
(`assign_ops/2` is the only writer), blocks drop `:form`/`:children` on re-entry
(`block.ex:883-888`), and content travels as param diffs. The leaks are (a) finding 1 —
the child validate rebase makes the store's diffs incomplete, (b) finding 7 —
`extract_child` reads another component's seed and overwrites its diff, (c) the
`@changesets` tracker (finding 15), and (d) `set_multi_children_collapsed`
(`block_field.ex:1521`) reads `seed_forms` to decide which blocks are multi — stale after
any post-mount structural change, exactly the failure mode `rebuild_outline_items`
(`block_field.ex:1488-1491`) documents and avoids.

**validate_block cost per keystroke (50 root blocks).** Flat and bounded — confirmed, no
rewrite argument here:
1. Client posts only the edited block's form (its own hidden + visible inputs);
   unaffected blocks send nothing.
2. Server rebuilds **one** changeset: `cast/4` over `@block_attrs` + `cast_assoc` over
   that block's vars/refs/table_rows/block_identifiers (the polymorphic ref `data` cast is
   the expensive part, O(refs)).
3. Villain render only when live preview is on (`render_html?` flag,
   `block.ex:1811-1813`).
4. One `send_update` to BlockField → `Ops.apply_op` → `Map.put` in `diffs`.
5. BlockField's `render/1` runs, but `root_order` and `seed_forms` are reference-equal, so
   the shells comprehension is skipped in the diff (`assign_ops/2`'s comment is accurate).
   Siblings are not re-rendered and receive no messages.
So cost is O(1) in the number of blocks and O(vars+refs) in the edited block. The only
per-keystroke fan-out is `maybe_update_live_preview_block` → Form (one message).

**Mount cost.** The dominant terms, in order: (a) per-block ETS copies of
containers/fragments/palettes (finding 10) — the clearest win; (b) rendered hidden inputs
(already heavily optimised: `carried_var`, `carry_persisted`, `module_config` deferral,
ref identity-only — with the correctness holes noted in 2/8/9); (c) `@seed_forms` in
BlockField holds one changeset per root — initially the *same term* the Block assigns as
`:form`, so it is free until the block is edited, after which it pins the pre-edit tree
for the session; (d) `maybe_parse_module` regex-splits the module code once per block.

**Save cascade.** `Form.handle_event("save")` → `send_update_after(..., 150)` →
`BlockField.update(%{event: "fetch_root_blocks"})` materializes every root from the store
in one pass and answers → `event_tag_received(:save)` pushes `b:submit` once every field
has answered. Ordering: sequence derives from list position
(`ops.ex:503-526`), children rebuilt from `child_order` and always emitted
(`ops.ex:551-556`) so removals persist. Deleted roots are expressed by absence +
`on_replace: :delete` on `entry_#{field}` (`blueprint.ex:396-403`); deleted children by
absence + `on_replace: :delete_if_exists`. Transaction: whatever
`context.update_#{singular}/2` wraps — the block tree is one `put_assoc` on the entry
changeset, so it is atomic with the entry. Two notes:
* deleting a root deletes only the **join row**; `content_blocks` is orphaned (the FK
  cascade points the other way — `priv/repo/migrations/20160219000000_test_migrations.exs:376`).
  Known and deliberate: `Brando.Content.Blocks.list_orphaned_blocks/0` +
  `test/brando/content/orphaned_blocks_test.exs` document that deleting orphans breaks
  revision restore. Informational.
* the 150 ms `send_update_after` is a delay, not a barrier — it works because ops are
  already in the mailbox, but a client-side `phx-debounce` on a block input
  (`render.ex:1729`, `:1824` use 300 ms) can still be in flight when the block field
  materializes. A block whose last 300 ms of typing has not been flushed saves stale text.
  Consider force-flushing block forms client-side before `b:submit` (there is already a
  `:force_ship_focused_block` message for the sync side — `form.ex:3311`).

**Recovery.** See findings 5 and 6. It restores top-level fields, vars, refs and
table_rows through the normal pipeline, but **not** children, and it trusts the payload.

---

## Quick-fix list (surgical, ordered by value/effort)

1. `events.ex:252,271,310,330,366,369` — `get_embed`/`put_embed` → `get_assoc`/`put_assoc`.
2. `events.ex:242,295,353,390,443,480,536` — `uid = socket.assigns.uid`.
3. `render.ex:1241` — always emit ref `image_id`/`video_id`/`gallery_id`/`file_id`.
4. `block.ex` (`Brando.Content.Block`) `@var_attrs` — add `:video_id`, `:gallery_id`,
   `:config_target`, `:gallery_allowed_types`, `:gallery_image_config_target`,
   `:gallery_video_config_target`; add `:gallery_id` to `ref_changeset`'s cast list.
5. `block_field.ex:1177` — `block_module.changeset(base_struct, params, user_id, true)`
   + nest child forms in the JS hook; whitelist recovered params.
6. `block.ex:926-937,1179-1185` — gate `containers`/`fragments`/`palette_options` on type.
7. `block_field.ex:656,672` — `connected?/1` guard.
8. Finding 1 — make `{:update, …}` merge, or snapshot child diffs. Needs a decision;
   everything else above is mechanical.
