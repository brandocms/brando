# Form Architecture Audit — Pass 2: input.ex, Blueprint DSL, render components

Scope: `form/input.ex:150-1057`, `blueprint/forms/*.ex`, `live_view/form/compiler.ex`,
`components/form/{fieldset,fieldset/field,tab,subform,subform/field}.ex`,
`components/form/input/{select,multi_select,entries,link,vars}.ex`,
`components/form/input/subform_helpers.ex`, and the middle sections of `form.ex`
(live-preview, block-save assembly, `save_video_authorized`).

## Findings

### 1. DEAD — `Brando.Blueprint.Forms.Legacy.fieldset/2` is unreachable
`lib/brando/blueprint/forms/legacy.ex:1-7`
```elixir
defmodule Brando.Blueprint.Forms.Legacy do
  @deprecated "use fieldset/1 instead"
  defmacro fieldset(_, _) do
    nil
  end
end
```
Still imported into every Blueprint form DSL scope: `lib/brando/blueprint/forms/dsl.ex:273`
(`imports: [Brando.Blueprint.Forms.Legacy]`). Grepped the whole repo for a 2-arg
`fieldset "...", ...` call site inside any `forms do` block — none exist. The
`@fieldset` Spark entity (dsl.ex:152) is the only live `fieldset` macro reachable
in that scope. Remove the module and the `imports:` line.

### 2. RESOLVED (from pass 1) — `save_video_authorized` no-op clause IS reachable, not dead
`lib/brando_admin/components/form.ex:4069`
```elixir
def handle_event("save_video_authorized", _params, socket), do: {:noreply, socket}
```
Grepped `assets/` — confirmed no JS ever pushes `"save_video_authorized"` directly;
it is only reached internally from `handle_event("save_video", ...)` at
form.ex:3985, which re-dispatches to `"save_video_authorized"` with
`video_save_authorized?: true` injected into assigns. The clause at 4069 is the
**fallback pattern-match arm** for when the guarded clause at form.ex:3989-4005
doesn't match (e.g. `edit_video` assign missing `:video`/`:path`/`:field`, or the
authorization flag absent) — it's a deliberate no-op safety net, not dead code.
No action needed; pass-1's open question is closed.

### 3. PERF/IDIOM — `ComponentResolver.resolve/1` re-run on every fieldset field render
`lib/brando_admin/components/form/fieldset/field.ex:28`
```elixir
|> assign(:custom_component, ComponentResolver.resolve(Map.get(assigns.input, :component)))
```
Called unconditionally in `render/1` (not `assign_new`), so every re-render of
every fieldset field pays a map lookup + `Module.concat/1`. `assigns.input` is
the compile-time `Forms.Subform`/`Forms.Input` struct from the Blueprint DSL —
`component` is a static atom known at compile time. This is exactly the
"resolved at runtime that could be resolved at compile time" pattern the DSL
layer is supposed to avoid: `Dsl.transform_form/1` (dsl.ex:276) already does one
compile-time pass over subforms; a second transform could resolve
`custom_component` once and store the module on the `Forms.Subform` struct.
Impact is low (single map lookup), but it's live on every field in every
fieldset render, including non-subform inputs where `Map.get(assigns.input, :component)`
is always `nil` (Forms.Input has no `:component` key — this call also silently
relies on `Map.get`'s default rather than the struct actually having the field).

### 4. IDIOM — `:languages`/`:admin_languages` option resolution duplicated 3x, re-run at runtime
`lib/brando_admin/components/form/input.ex:286-296` (radios), and identically in
`lib/brando_admin/components/form/input/select.ex:336-345` and
`multi_select.ex:578-587`:
```elixir
:languages ->
  languages = Brando.config(:languages)
  Enum.map(languages, fn [{:value, val}, {:text, text}] -> %{label: text, value: val} end)
```
`Brando.config/1` reads Application env — static for the life of the node, not
per-request data — yet this is recomputed every time `radios/1` renders (no
`assign_new` guard in input.ex, unlike select.ex/multi_select.ex which do cache
via `assign_new(:input_options, ...)`). `radios/1` in input.ex has no such cache;
it's a plain function component invoked fresh from `fieldset/field.ex` on every
parent render, so `Brando.config(:languages)` and the `Enum.map` run on every
keystroke that re-renders the fieldset. Low-cost individually, but three
duplicate implementations is a DRY problem worth collapsing into one
`Brando.Blueprint.Forms` helper — and the `radios/1` one specifically has no
render-frequency guard the other two have.

### 5. DATA-LOSS (narrow scope, UNVERIFIED severity) — video-drawer sub-tabs use `:if`-based unmount instead of CSS toggle
`lib/brando_admin/components/form/tab.ex:44-49`
```elixir
def tab_content(assigns) do
  ~H"""
  <div :if={@active_tab == @id} class="tab-panel" id={"tab-panel-#{@id}"}>
    {render_slot(@inner_block)}
  </div>
  """
end
```
Used only for the video-edit drawer's Upload/External-URL tabs
(`form.ex:2743,2818`) — confirmed the **main** form tabs use CSS class toggling
(`form.ex:2231-2233`, DOM stays mounted), so this is not the widespread
tab-switch data-loss vector the audit brief worried about. But within this
narrow drawer: `Tab.tab_content` removes the entire subtree from the DOM when
switching between "Upload" and "External URL". If a user is mid-edit in the
`source_url` text input (`form.ex:2838`, no explicit `phx-debounce` shown but
inherits LiveView's default change-event batching) and clicks the other tab
before the browser has dispatched the `input`/`change` event, the field's DOM
node is destroyed and any un-flushed value never reaches the server —
silently reverting to the last-known value if the user switches back. Low
blast radius (2-field drawer), but worth a fix: switch `tab_content` to CSS
`hidden` attribute/class instead of `:if`, matching the main-tab pattern.
UNVERIFIED: didn't trace whether Phoenix.HTML input change events fire
synchronously on blur before the DOM removal (click handlers run after
blur in browsers, which would mitigate this) — flagging as a real but
lower-confidence finding.

### 6. UNVERIFIED — `put_change/3` (not `put_assoc`/`put_embed`) used with raw `%Ecto.Changeset{}` values for polymorphic `Var` fields
Three call sites do the same thing:
- `lib/brando_admin/components/form/input/vars.ex:118` — `Ecto.Changeset.put_change(changeset, field_name, updated_field)` where `updated_field` is `current_globals ++ [new_entry_changeset]` (a list mixing applied structs and one raw `%Ecto.Changeset{}`)
- `lib/brando_admin/components/form/input/link.ex:69` — `put_change(changeset, field_name, default_link)` where `default_link` is a raw `%Ecto.Changeset{}`
- `lib/brando_admin/components/form/input/subform_helpers.ex:18,39` — same pattern for remove/reorder

`put_change/3` does not run association/embed casting the way `put_assoc/3` and
`put_embed/3` do — it just stores the raw value under `:changes`. This is safe
*only if* the target field's Ecto type (presumably a `PolymorphicEmbed` custom
type, given `inputs_for_poly` helper usage) has a `cast/1` implementation that
accepts `%Ecto.Changeset{}` structs directly. Did not verify
`polymorphic_embed`'s cast implementation or confirm `Brando.Content.Var`'s
field type. If it does NOT accept raw changesets in that position, every
add/remove/reorder on Vars/Link fields would silently no-op or crash at
dump-time. Given 3 independent call sites use the identical pattern
consistently, this is very likely intentional/working — flagging as
UNVERIFIED rather than a bug, but worth a 1-line confirmation against
`deps/polymorphic_embed/lib/polymorphic_embed/type.ex` `cast/1`.

### 7. Confirmed correct — `add_subentry`/block-save assembly follow the Append-Changeset pattern
- `subform.ex:317-356` (`handle_event("add_subentry", ...)`) appends a single
  new struct (not converted-changeset) to `Ecto.Changeset.get_field/2`'s result
  and calls `put_assoc`/`put_embed` — matches AGENTS.md guidance; only one new
  nil-id entry is appended per event, so the "multiple nil-id changesets from
  the same struct" duplicate-PK trap doesn't apply.
- `form.ex:4462-4472` (`assoc_all_block_fields/2`, the block-save assembly)
  builds each block field's changeset list via `Brando.Content.Blocks.reject_deleted/2`
  + `strip_render_artifacts/1` + `Brando.Utils.set_action/1` before `put_assoc`,
  and the `"save"` handler's `{:error, %Ecto.Changeset{}}` branch
  (form.ex:3295-3304) explicitly re-assigns `:form` and calls `push_errors/3` —
  no swallowed errors, no bare `{:error, _}` match. Failure path preserves
  `block_changesets`/`transformer_changesets` assigns untouched, so a retry
  after a validation failure doesn't lose in-progress block edits.

### 8. Not a bug — checkbox/hidden/text inputs in input.ex (150-1057) are idiomatic
Reviewed `datetime`, `email`, `number`, `password`, `phone`, `radios`,
`rich_text`, `slug`, `hidden`, `input/1` (checkbox/textarea/default clauses),
`status`/`status_compact`, `i18n_text`/`i18n_textarea`, `text`, `override_text`,
`override_toggle_group`, `textarea`, `toggle`. All use `to_form`-derived
`FormField`, pattern-match on `assigns.type` in function heads (no
if/case-as-dispatch), and correctly guard AI-button rendering behind
`Brando.AI.configured?/1`. No constant-list-in-template violations beyond
finding #4. `password/1`'s dynamic atom build
(`:"#{assigns.field.field}_confirmation"`) is safe — `field.field` is a
compile-time-known Blueprint/Ecto field atom, not external user input.

## Not reached (budget)
- `blueprint/forms/{fieldset,input,tab,alert}.ex` struct definitions — skimmed
  via `form.ex`/`subform.ex`/`verifier.ex` reads, all plain `defstruct`, no
  logic to audit.
- `handle_progress` (upload-progress) section of form.ex was grepped for but
  not found under that literal name — likely lives in a Hooks module
  (`hooks_progress_popup` in compiler.ex:23) outside this file; not traced.
- Did not verify `polymorphic_embed` cast behavior for finding #6.
