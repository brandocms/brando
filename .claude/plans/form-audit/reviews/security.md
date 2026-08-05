# Security Review: commit 2c26cb31b (block var/ref media cast widening)

Scope: the 7 changed files only. Threat model as stated — all actors are
authenticated CMS staff; the meaningful boundary is **entry/field**, not tenant,
because Brando has no tenant column on assets (`lib/brando/images` has zero hits
for `organization_id|tenant_id|site_id`) and every admin can already browse every
image/video/gallery through the pickers.

## Verdict

**No BLOCKER.** This commit does **not** widen the C5 class. The two mechanisms
that look like C5 (`restore_programmatic_ref_media/2` and `find_block_by_uid/2`)
are both bounded to server-side state belonging to the block/entry the socket
already owns. Three WARNINGs and two SUGGESTIONs below, all
"exploitable by an authenticated admin", none cross-entry.

---

## Cleared (checked, no issue)

### `String.to_existing_atom/1` — CLEAN
`lib/brando_admin/components/form/block/events.ex:1062`

```elixir
@ref_media_fk_params ["image_id", "video_id", "gallery_id", "file_id"]   # :1025
Enum.reduce(@ref_media_fk_params, ref_params,
  &Map.put_new(&2, &1, Map.get(applied, String.to_existing_atom(&1))))
```

The atom source is a compile-time module attribute of four literals. The
client-controlled value (`ref_params`) is only the *accumulator*, never the atom
argument. No path exists for a client key to reach `to_existing_atom/1`. No atom
exhaustion. Iron Law #3 satisfied.

### `restore_programmatic_ref_media/2` — CLEAN, no cross-block pull
`events.ex:1027-1042`, `:1052-1067`

`applied_by_id` is built from `Changeset.apply_changes(socket.assigns.form.source)`
(`events.ex:717` for child blocks, `:783` for root blocks) — the server-side
changeset for **this block only**. Attempted exploit: client sends
`entry_block[block][refs][0][id]=<ref id owned by another block/entry>`. Result:
`Map.get(applied_by_id, "…")` misses → `ref_params` returned unchanged. No FK is
pulled in. Belt-and-braces: `:id` is *not* in `ref_changeset/3`'s cast list
(`lib/brando/content/block.ex:283-299`), so the forged id also cannot re-point
the cast at another row — `cast_assoc` matches param ids against `data.refs`,
which is again this block's own preloaded list.

The asymmetry is in the safe direction: `Map.put_new` means client params always
win, so a client can *suppress* restoration (clear a ref's media by sending
`image_id=""`) but can never *widen* it. Clearing media on a block you may edit
is within admin authority.

### PubSub block sync — CLEAN
`block_field.ex:677` scopes the topic to `brando:blocks:#{entry_id}:#{field}`;
subscription only happens in `initialize_blocks/2` after the entry form mounted
through the normal route auth. `Ops.apply_remote_snapshot/3` (`ops.ex:346`)
rejects unknown uids. Snapshots are not client-forgeable.

---

## WARNING 1 — Media FKs cast with no `foreign_key_constraint` → LiveView crash
**Severity**: Low-Medium (availability, authenticated admin)
**Location**: `lib/brando/content/block.ex:69-70` (`:video_id`, `:gallery_id` in
`@var_attrs`), `lib/brando/content/block.ex:298` (`:gallery_id` in `ref_changeset/3`)

Both columns carry real DB references
(`priv/repo/migrations/20260715000000_add_video_and_gallery_to_content_vars.exs:6-7`,
`20160219000000_test_migrations.exs:331-332`), but neither `var_changeset/3,4`
(`block.ex:268-279`) nor `ref_changeset/3` adds `foreign_key_constraint/2`.
Before this commit those keys were dropped by the cast, so a bogus value was
inert; now it reaches the INSERT.

Exploit: DevTools-edit the hidden input rendered by
`Render.carried_var/1` (`render.ex:2060`) to
`entry_block[block][vars][0][gallery_id]=999999999` and save. Postgres raises
23503, Ecto turns it into `Ecto.ConstraintError`, the LiveView process dies and
the editor reloads — taking the admin's unsaved block edits with it. Self-inflicted
for the attacker, but it is an unhandled 500 on a client-controlled value, and a
concurrent editor on the same entry (blocks sync) is collateral.

**Fix** (in `block.ex`, both changesets):

```elixir
|> foreign_key_constraint(:image_id)
|> foreign_key_constraint(:file_id)
|> foreign_key_constraint(:video_id)
|> foreign_key_constraint(:gallery_id)
```

**OWASP**: A04:2021 Insecure Design (missing failure-path handling).

## WARNING 2 — Client-settable `config_target` selects any blueprint's upload config
**Severity**: Low (authenticated admin; no cross-entry impact)
**Location**: `lib/brando/content/block.ex:72-74` (`:config_target`,
`:gallery_image_config_target`, `:gallery_video_config_target` now cast from params)

Resolution itself is sound — I traced it and found **no injection and no path
traversal**:

- `Brando.Assets.ConfigTarget.schema_module/1` (`config_target.ex:66-76`) uses
  `String.to_existing_atom` inside a `rescue ArgumentError -> :error` **and**
  requires `Brando.Blueprint.blueprint?/1`. No atom minting, no arbitrary module.
- `blueprint_asset/2` (`:137`) and `field_atom!/2` (`:154`) route through the
  same guarded `existing_atom/1`.
- `Brando.Uploads.resolve_config/3` (`uploads.ex:593-609`) falls back to
  `"default"` on any raise (`safe_get_config/2`, `:621`). Upload directories,
  size limits and mimetype lists all come from the **server-side blueprint asset
  config**, never from the target string — a `"../.."` segment cannot survive
  `schema_module/1` and would degrade to `"default"`.

The residual risk is *selection*, not injection: a client-authored
`config_target` can point a var at **any** blueprint asset field's config, so an
admin can pick a config with looser `size_limit`/`allowed_mimetypes` than the
module author intended. If any blueprint in a consuming app declares a file/image
config that permits `image/svg+xml` or `text/html`, this is a route to stored XSS
served from the media host. That is one step removed from this repo, so it is a
WARNING rather than a blocker.

**Suggested hardening**: restrict which config targets a *block var* may name —
e.g. accept only targets already declared by the owning module's var definition,
or `validate_change(:config_target, …)` against
`Brando.Assets.ConfigTarget.blueprint_asset/2` returning `{:ok, _}` — and reject
rather than silently degrade. Also worth confirming the app-level asset configs
never allow SVG/HTML.

Secondary note (pre-existing, `config_target.ex:97-109`, file not in this diff):
the `"<type>:<schema>:function:<fn>"` form calls **any exported 0-arity function
on any loaded blueprint** selected by a string. Bounded (result must pass
`normalize_resolved_value!/3`), but it is arbitrary-function-selection from
client data and deserves a comment or an allowlist.

## WARNING 3 — `carried_var/1` puts the whole cast surface in client-editable hidden inputs
**Severity**: Low (authenticated admin), but it is C5's exact shape
**Location**: `lib/brando_admin/components/form/block/render.ex:2060`

```elixir
<.carried_var_field :for={field <- ContentBlock.var_attrs()} field={@var[field]} />
```

For an unsaved var this renders a hidden input for **every** entry in
`@var_attrs` — which includes `:creator_id`, `:module_id`, `:block_id`,
`:page_id`, `:global_set_id`, `:table_template_id`, `:identifier_id`
(`block.ex:56-63`) — and all of them are cast back unvalidated. This is the same
"client params are trusted as ownership metadata" pattern the audit already
flagged as C5 for `recover_blocks`, now applied to vars.

Exploit: on a block's first save, set `…[vars][0][creator_id]` to another user's
id (creator spoofing, defeats attribution/audit) or `…[vars][0][block_id]` /
`[page_id]` to a row in a **different entry** — the var then carries a parent
pointer the acting user never touched. The var is still written under the
current block by `cast_assoc`'s parent FK, so this is misattribution and dangling
metadata rather than a real cross-entry write, but it is exactly the surface C5
warns about and it got wider here.

**Fix**: drive the carried set off a `@carried_var_attrs` list that is
`@var_attrs -- [:creator_id, :module_id, :block_id, :page_id, :global_set_id,
:table_template_id, :table_row_id, :menu_item_id]`, and stamp `creator_id` from
`socket.assigns.current_user.id` server-side in `var_changeset/4` via
`put_change/3` instead of casting it. (Same treatment C5 will need for
`recover_blocks`.) Note `var_struct_to_map/1` in `events.ex:980-1008` already
drops most of these FKs when seeding from module defaults — the DOM path should
match it.

## SUGGESTION 1 — `find_block_by_uid/2` is bounded; document the invariant
**Severity**: Low, intra-entry only
**Location**: `block_field.ex:715-721`, via `child_base_struct/2` (`:704`) and
`update(%{event: "insert_extracted_child"})` (`:263-293`)

Traced the full path: client `handle_event("outline_reposition", params, …)`
(`:1126`) → `send_update(Block, event: "extract_child")` (`:1144`) →
`Block.update/2` (`block.ex:191`) → `send_to_ref(parent_ref, %{event:
"insert_extracted_child", child_uid: uid})` (`block.ex:214`). The uid is
client-supplied end to end.

Two things bound it, and they hold:

1. `Ops.materialize_child/2` (`ops.ex:550-563`) runs **first** and returns
   `{:error, {:unknown_uid, uid}}` unless `known?(state, uid) and uid not in
   state.order` — so the uid must already be a child in this field's op store.
2. `find_block_by_uid/2` walks only `socket.assigns.entry_blocks`, i.e. the
   preloaded tree for **this entry and this block field**.

So a forged uid buys at most "move a different block of the same entry+field
under another parent" — an action the drag UI grants anyway. No arbitrary
`Repo.get`, no other entry's struct can become the cast base. **Not an IDOR.**
Worth a comment stating that `materialize_child/2`'s `known?` check is the
authorization gate for `child_base_struct/2`, so a later refactor that reorders
them doesn't quietly remove it.

## SUGGESTION 2 — `Block` component ids are not namespaced by block field
**Severity**: Low (correctness + intra-entry structural surprise)
**Location**: `block_field.ex:275`, `:434`, `:447`, `:891`, `:1136`, `:1145`

Every `send_update(Block, id: "block-#{uid}")` uses a field-global id. On a form
with two block fields, a client-forged `outline_reposition` carrying
`to.parentUid` read from the *other* field's DOM will route the extracted child
into a Block component owned by that other field. Same entry, same user's edit
rights, so not a privilege issue — but it is a state-corruption path that a
namespaced id (`"block-#{block_field}-#{uid}"`) would close for free, and it also
makes the `find_block_by_uid/2` invariant above easier to reason about.
Additionally, `handle_event("outline_reposition", …)` (`:1126`) never validates
that `from_parent_uid`/`to_parent_uid` are `known?` in the op store — an unknown
id makes `send_update` a silent no-op, so failures are invisible. Consider
rejecting unknown parent uids explicitly and logging, matching the
`apply_block_op/2` error style at `:744-751`.

---

## Not applicable / clean in this diff

Checked and found nothing in the changed files for: SQL injection (no raw SQL,
no `fragment` interpolation), `raw/1`/XSS in the changed HEEx, CSRF, secrets,
`binary_to_term`, path traversal, session config. `lib/brando_admin/components/form.ex`
and `.../input/subform_helpers.ex` contain no atom-minting, no `Repo` calls with
client ids, and no raw output.

## Tools the user should run (this agent has no Bash access)

- `mix sobelow --exit medium`
- `mix deps.audit`
- `mix hex.audit`

## Priority

1. WARNING 3 (`carried_var` FK surface) — same class as C5, fix alongside Phase 1.
2. WARNING 1 (`foreign_key_constraint`) — one-line fix, removes an unhandled 500.
3. WARNING 2 (`config_target` selection) — needs a product decision on whether
   block vars may name arbitrary asset configs.
4. SUGGESTIONs 1-2 — hardening/comments.
