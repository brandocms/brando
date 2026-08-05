# Form Core Architecture Audit

Scope read: `lib/brando_admin/components/form.ex` (6257 lines, read in full via
chunked passes), `lib/brando_admin/live_view/form.ex`, `lib/brando_admin/live_view/form/hooks.ex`
(read in full, 1370 lines), `lib/brando_admin/live_view/form/compiler.ex` (read in
full), `lib/brando/blueprint/forms.ex` + `forms/legacy.ex` + `forms/component_resolver.ex`
(read in full), `lib/brando_admin/components/form/fieldset.ex`, `fieldset/field.ex`,
`tab.ex`, `subform.ex`, `subform/field.ex` (read in full), `input.ex` (partial —
first 150/1057 lines, pattern sampled), `lib/brando_admin/live/pages/page_form_live.ex`
(read in full).

Not read in this pass (budget): `lib/brando/blueprint/forms/dsl.ex`, `fieldset.ex`,
`input.ex`, `tab.ex`, `subform.ex`, `verifier.ex`, `alert.ex` (Blueprint DSL side),
`input/subform_helpers.ex`, `lib/brando_admin/live/users/user_form_live.ex`,
`assets/src/hooks/Form/index.js`, and ~5100 of `input.ex`'s 1057 lines and ~4500
of `form.ex`'s middle section (upload/drawer/block handlers) beyond what's quoted
below. Findings below are everything VERIFIED by direct reading; anything else is
explicitly marked INFERRED.

## Top Findings (ranked by user impact)

### 1. PERF — Static per-schema metadata recomputed on every parent send_update, not just mount
`lib/brando_admin/components/form.ex:978-1039` (`update/2` catch-all) and
`:1399-1421` (`assign_addon_statuses/1`)

```elixir
def update(assigns, socket) do
  ...
  cond do
    socket.assigns.entry_loading? -> {:ok, socket}
    socket.assigns.initial_update && socket.assigns.entry_id -> {:ok, start_entry_load(socket)}
    true -> {:ok, socket |> assign_entry() |> finish_form_update()}
  end
end

defp assign_addon_statuses(%{assigns: %{schema: schema, entry: entry}} = socket) do
  transformers = extract_transformers(socket.assigns.form_blueprint)
  ...
  assign(socket,
    has_blocks?: schema.has_trait(Brando.Trait.Blocks),
    ...
    has_live_preview?: check_live_preview(schema),   # Code.ensure_compiled!/1 every call
    transformer_changesets: Map.new(transformers, fn {name, _, _} -> {name, nil} end)
  )
end
```

`finish_form_update/1` (line 1044) runs `assign_addon_statuses |> assign_default_params
|> extract_tab_names |> assign_form |> maybe_assign_uploads |> maybe_assign_block_map
|> maybe_assign_entry_for_blocks` on *every* `update/2` call that isn't the initial
load and isn't mid-async-load — i.e. every time the parent LiveView re-renders and
passes new props to this `live_component` (e.g. `presences={@presences}` in
`page_form_live.ex:23`, which changes on every Presence diff). `assign_addon_statuses`
uses plain `assign/2` (not `assign_new/2`), so `schema.has_trait/1` (×5),
`check_live_preview/1` → `Code.ensure_compiled!/1`, and `Map.new/2` over transformers
are re-executed on data that cannot change after mount for a given schema/entry.
`extract_tab_names/1` and `assign_form/1` do correctly use `assign_new`, showing the
codebase already knows the pattern — `assign_addon_statuses` is the outlier.
**Fix direction**: switch the 7 `assign_addon_statuses` keys and
`transformer_changesets` to `assign_new`, or hoist the whole block behind an
`initial_update?` guard like the sibling helpers.

### 2. STRUCTURE — `form.ex` fuses ≥7 unrelated concerns into one 6257-line LiveComponent
`lib/brando_admin/components/form.ex` (whole file)

Concretely: main entry-field lifecycle (mount/update/validate/save, lines 1-110,
2976-3320), file/image/video drawer state machines (`update/2` clauses lines
175-500+, `handle_event` clauses 3667-4069), live preview (`update/2` clauses
499-553, `handle_event` clauses 4151-4232), revisions (`store_revision/2` line
4481, `handle_event("store_revision"...)` 4097), block-field orchestration
(`assoc_all_block_fields/2` 4462, `handle_event("save"...)` with
`has_blocks?: true` 3161-3320), gallery asset delivery (`append_gallery_object/5`
1196, `gallery_at/2` 1239), and ~35 function components for field chrome
(`field_base/1` 5363, `error_tag/1` 5877, `input/1` 5472, live_preview markup
5276-5346). Each concern already has *some* separation at the call-site level
(image/file/video drawer helpers are grouped; block-save is one big clause), but
they share one `handle_event`/`update` dispatch table and one module namespace,
so every drawer bugfix risks touching the same file as block-save logic.
**Concrete seams that would not break behavior if split**: (a) the video-upload
protocol handlers (`update/2` clauses 365-459, `handle_event` 3549-4069) into a
`Form.VideoDrawer` live_component — they already send/receive via `send_update`
so the wire protocol is already message-passing, not shared state; (b) the
file/image drawer `update/2` clauses (175-330) similarly; (c) the ~35 function
components after `## Function components` (line 5274 onward, ~980 lines) into a
`Form.Chrome` module — they take only `assigns`, no `@myself`-coupled state.
Gallery/entry-relation delivery (`commit_entry_field_asset/4`,
`update_entry_with_relation/3`, `append_gallery_object/5`) is more entangled with
the live changeset (`socket.assigns.form.source`) and would need a shared-state
extraction strategy, not a pure split.

### 3. IDIOM — form's action is force-set to `:validate` at every fresh-assign, bypassing `used_input?`'s intended gate for those code paths
`lib/brando_admin/components/form.ex:4847-4874` (`assign_form/1`),
`:4876-4883` (`assign_refreshed_form/1`), `:924-933` (`refresh_entry`)

```elixir
def assign_form(%{assigns: %{entry: entry, ...}} = socket) do
  assign_new(socket, :form, fn ->
    entry |> schema.changeset(%{}, current_user) |> Map.put(:action, :validate) |> to_form()
  end)
end
```
Every fresh form (create and edit) gets `action: :validate` unconditionally,
before the user has touched anything. The codebase's own `error_tag/1` (line
5877) and `has_error/2` (line 5459) correctly gate on `Phoenix.Component.used_input?/1`
before showing errors — that's the actual safety net, and it works for regular
inputs. This is not a live bug given that safety net, but it *is* dead weight:
`Map.put(:action, :validate)` in `assign_form/1`, `assign_refreshed_form/1`, and
the `refresh_entry` handler (line 926) achieves nothing beyond what plain
`to_form(changeset)` (no `:action`) plus a real `:validate` action set from the
`validate` handle_event already provides — `to_form/2`'s `errors` param controls
that display, not a pre-set `:action`. Low priority; flag for cleanup during any
touch of these functions, not a standalone fix.

### 4. DEAD CODE candidate — `save_video_authorized` handler is an unreachable no-op
`lib/brando_admin/components/form.ex:4069`
```elixir
def handle_event("save_video_authorized", _params, socket), do: {:noreply, socket}
```
Grep across `assets/src` for a client-side `push_event`/`phx-click` targeting
`"save_video_authorized"` is needed to confirm this is genuinely unreachable —
NOT verified by reading JS in this pass. Flagging as a DEAD-code candidate for
the next pass rather than a confirmed finding.

### 5. IDIOM — inline SVG icon duplication instead of `<.icon>` throughout `render/1`
`lib/brando_admin/components/form.ex:1906-1972` and similar blocks through the
function-component section (5274+)

Several toolbar buttons hand-roll `<svg>` markup (meta, revisions, scheduled
publishing, alternates, live-preview, share-link icons, lines 1906-1972) while
`subform.ex` and other files use `<.icon name="hero-..."/>` for the same visual
language (`subentry_sequence/1` line 228-234, `subentry_remove/1` line 278-284).
Not a bug, but it's inconsistent with the codebase's own convention and adds
~70 lines of inline markup that could be five `<.icon>` calls — low-cost cleanup,
not urgent.

### 6. VERIFIED GOOD — no Iron Law violations found in the read portion
- `mount/1` (form.ex:55) does no DB queries; `connected?/1` gates both PubSub
  subscriptions (lines 61-64).
- `hooks.ex` on_mount clauses gate every `PubSub.subscribe` behind `connected?(socket)`
  (lines 12, 35) — including the deferred `maybe_arm_entry_scope/3` handle_params
  hook for create→update transitions (lines 208-220), which correctly re-arms
  subscriptions exactly once (`assigns: %{entry_id: nil}` guard prevents double-sub).
- `assign_schema/2` (hooks.ex:1327) correctly uses `assign_new` (schema is
  compile-time constant), while `assign_action/2` (hooks.ex:1356) and
  `set_admin_locale/1` (hooks.ex:1348) correctly use plain `assign` every mount —
  exactly per the "never assign_new for lifecycle values" rule.
- The main `"save"` handler (form.ex:3295) matches `{:error, %Ecto.Changeset{}}`
  explicitly, not a bare `{:error, _}`.
- Large entry loads are deferred via `start_async` (form.ex:1084,
  `start_entry_load/1`) with a synchronous fallback only for the SQL-sandboxed
  e2e case (line 1066-1071) — correctly commented as a deliberate exception, not
  an accidental blocking load.
- `error_tag/1` (form.ex:5877) and `has_error/2` (form.ex:5459) both gate on
  `Phoenix.Component.used_input?/1` before surfacing errors, with an explicit
  comment explaining why (avoids red dots on a blank create form).
- `live_component` ids for subforms/transformers are built from stable
  `form.id` + `input.name` (fieldset/field.ex:38,53,65) — not from index or
  regenerated UUIDs, so CIDs stay stable across remounts.
- `append_gallery_object/5` (form.ex:1196-1236) correctly slims existing gallery
  objects to plain maps before `put_assoc` with a new struct-backed object,
  exactly matching the AGENTS.md "put_assoc with multiple new records" rule
  (comment at line 1191-1195 cites this directly).

### 7. INFERRED, not verified — `commit_entry_field_asset/4`'s apply_changes→change round trip
`lib/brando_admin/components/form.ex:1166-1189`
```elixir
defp commit_entry_field_asset(socket, field, path, asset) do
  relation_key = String.to_existing_atom("#{field}_id")
  full_path = path ++ [relation_key]
  updated_changeset =
    socket.assigns.form.source
    |> apply_changes()
    |> change()
    |> EctoNestedChangeset.update_at(full_path, fn _ -> asset.id end)
  ...
end
```
This is exactly the `apply_changes → change()` round trip AGENTS.md warns about
("duplicate PK" class of bug), but the in-code comment (lines 1160-1165) states
it is deliberate: baking in-flight changes as new "data" so the main save's cast
against the entry still diffs correctly, and a call to `ship_all_field_changes/1`
immediately after (line 1184) is noted as required *because* this rebake clears
what there is to ship. This looks intentional and well-reasoned given the
comment, but I did not trace `ship_all_field_changes/1` or every call site to
independently verify no pending multi-field edit is lost when two asset fields
are set back-to-back before a blur event ships them. Flagging as
**INFERRED-safe, not fully verified** — worth a targeted test if the audit
continues into this component's collaborative-editing path.

## Not yet audited (recommend a follow-up pass)
- `lib/brando_admin/components/form/input.ex` beyond line 150 (907 more lines) —
  first pass showed idiomatic function-component structure (`prepare_input_component/1`,
  `Form.field_base` wrapper) with no obvious constant-in-HEEx violations in the
  sampled portion, but the file is too large to have been fully verified.
- `lib/brando/blueprint/forms/dsl.ex`, `verifier.ex`, `fieldset.ex`, `input.ex`,
  `tab.ex`, `subform.ex` (the Blueprint DSL definitions, as opposed to the admin
  render layer already covered).
- `lib/brando_admin/components/form/input/subform_helpers.ex` — not opened.
- `lib/brando_admin/live/users/user_form_live.ex` — not opened; only
  `page_form_live.ex` was read as the consumer example, and it is a trivial
  6-line wrapper with no independent logic to compare against.
- `assets/src/hooks/Form/index.js` — not skimmed; client-side recovery/validate
  wiring (`phx-auto-recover`, `b:validate` push targets) referenced from Elixir
  but not cross-checked.
- The full middle section of `form.ex` (roughly lines 400-1120 and 2000-2976,
  3320-4456) — upload progress handlers, live-preview fetch helpers, block-save
  assembly (`build_entry_for_blocks/2`, `render_blocks_for_entry/3`) — was
  skimmed via targeted greps for specific functions rather than read
  sequentially; a full pass could surface more N+1/perf issues in the block
  rendering pipeline specifically.
