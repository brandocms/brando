# Code Review: form-audit Phase 3 (`git diff HEAD~5`, branch `next`)

## Summary
- **Status**: ⚠️ Changes Requested
- **Issues Found**: 5 (1 blocker, 2 warnings, 2 suggestions)
- Scope: only code changed in the Phase 3 diff. Pre-existing issues listed as one-liners at the end.

Verified-clean areas (checked, no finding): the `Dsl.transform_form/1` compile-time
`ComponentResolver.resolve/1` move; the `block_field.ex` `connected?/1` PubSub gating; the
`Options.expand/1` extraction; `blocks.ex` `reject_deleted/2`; dropping `Map.put(:action, :validate)`.
Details under "Checked and clear".

---

## BLOCKER

### 1. `palette_options` is now `[]` where the template needs `nil` — the palette hidden input goes dead

`block.ex:1290-1296` and `block.ex:1307-1323` both return `[]` from every non-rendering branch:

```elixir
|> assign_new(:palette_options, fn assigns ->
  if container.allow_custom_palette and renders_palette_options?(assigns) do
    Brando.Content.list_palettes!(opts)
  else
    []            # <-- truthy
  end
end)
```

The only consumer is `block/render.ex:1173`:

```elixir
<%= if @palette_options do %>
  <.live_component module={Input.Select} field={@block[:palette_id]} opts={[options: @palette_options]} ... />
<% else %>
  <Input.hidden field={@block[:palette_id]} />
<% end %>
```

`[]` is **truthy in Elixir**. After this change there is no code path in `maybe_assign_container/1`
that can produce `nil` or `false` for `:palette_options`, so the `else` branch at `:1182` is
**unreachable dead code**.

**Concrete failure:** a container block whose `container.allow_custom_palette == false`
(`block.ex:1308`). It now renders a `<select>` for `palette_id` with **zero options** instead of the
hidden input. `Input.Select` with an empty option list submits nothing for `block[palette_id]`, so on
the next `validate_block` an already-set `palette_id` is dropped from params — the exact
"value lives only in the changeset, no DOM backing" shape Phase 0 §B1 was written to close. The user
sees an empty Palette dropdown in the config modal and silently loses the palette on save.

**Fix** — return `nil`, not `[]`, from the non-rendering branches (both clauses), or invert the
template to `:if={@palette_options not in [nil, []]}`. Prefer the former; it keeps the hidden-input
carrier that `container_config/1` relies on.

```elixir
# Suggested
|> assign_new(:palette_options, fn assigns ->
  if container.allow_custom_palette and renders_palette_options?(assigns) do
    Brando.Content.list_palettes!(opts)
  else
    nil
  end
end)
```

Same change in the `container_id: nil` clause (`:1290`).

---

## WARNINGS

### 2. The `belongs_to == :root` half of the container/palette scoping is based on a false premise — the perf win is not delivered

`block.ex:934-936` and `block.ex:1280-1285` justify keeping the lists for **every root block** with:

> `@containers` reaches `container_block` (`:211`) and the `container_config` that every ROOT block
> renders (`:528`)

That is **factually wrong**, and it is worth correcting because the plan (§Phase 3 E, plan.md:906-908)
records it as a *verified* fact that shaped the design. Traced in the current tree:

- `render.ex:520` (`<.container_config …>`) sits inside `def container(assigns)` (`render.ex:451`).
- `<.container` is invoked from exactly one place: `render.ex:200`, inside
  `def render(%{type: :container} = assigns)` (`render.ex:197`).
- Grep confirms only two `container_config` occurrences in the tree (`render.ex:520`, `:1148`) and
  only one `<.container` call site (`:200`).

So `container_config` is rendered **only by container blocks**, never by a root `:module` or
`:fragment` block. `renders_palette_options?/1` and the `:containers` guard should be
`type == :container` alone.

**Cost of leaving it:** on a page with N root module blocks, every one of them still does
`Brando.Content.list_containers!/1` **and** `Brando.Content.list_palettes!/1` — two ETS reads,
each copying the full term onto the LiveView process heap, plus both lists retained in that
component's assigns and walked by change tracking on every diff. That is precisely the cost the item
set out to remove; on a typical page of module blocks the change removes nothing.

**Fix:**

```elixir
# Current
defp renders_palette_options?(%{type: type, belongs_to: belongs_to}),
  do: type == :container or belongs_to == :root

# Suggested
defp renders_palette_options?(%{type: type}), do: type == :container
```

and drop `or belongs_to == :root` from the `:containers` `assign_new` at `block.ex:940`.

Do this **after** finding 1 — with the `[]`/`nil` bug fixed, narrowing the guard is safe, because
the only reader of both assigns is unreachable for non-container blocks.

### 3. `maybe_assign_container/1`'s not-found branch leaves `:container` / `:palette_options` unassigned — `KeyError` on a container block with a deleted container

`block.ex:1299-1303`:

```elixir
def maybe_assign_container(%{assigns: %{container_id: container_id}} = socket) do
  case get_container(container_id) do
    nil -> assign(socket, :container_not_found, true)   # <-- no :container, no :palette_options
    container -> ...
  end
end
```

Unlike `module_not_found` (`render.ex:23`, which has a dedicated `render/1` clause that short-circuits),
there is **no `render/1` clause matching `%{container_not_found: true}`** — grep finds
`container_not_found` only at `block.ex:54` (mount seed `false`) and `block.ex:1302`. Rendering
therefore falls through to `render(%{type: :container})` (`render.ex:197`), which reads
`@palette_options` (`:209`), `@container` (`:210`) and `@containers` (`:211`).

**Concrete failure:** admin deletes a container that an existing block references → on the next mount
of that block, `update/2` never assigns `:container`/`:palette_options` → `KeyError` in the block
component render → the editor LiveView dies, taking every unsaved block edit with it. Same class as
Phase 0 A1/A2.

This branch is **pre-existing**, but the diff changed both lines that surround it and moved
`palette_options` into it, so it is in scope. Two options, either is cheap:

1. Add a `render(%{container_not_found: true} = assigns)` clause mirroring `module_not_found`
   (`render.ex:23-35`); **or**
2. Fall through to the nil-container clause's assigns before setting the flag:
   `socket |> maybe_assign_container(%{socket | assigns: %{socket.assigns | container_id: nil}}) |> assign(:container_not_found, true)` — or more simply, assign `:container`/`:palette_options` in the
   not-found branch too.

Same shape at `block.ex:1333` for `fragment_not_found`: it leaves `:fragment` unassigned while
`render(%{type: :fragment})` reads `@fragment` (`render.ex:277`).

---

## SUGGESTIONS

### 4. `Input.Options.tokens/0` is dead — the three call sites still hardcode the token list

`input/options.ex:16-19` exports `tokens/0`, but all three consumers guard on a literal:

- `input.ex:288` — `token when token in [:languages, :admin_languages] ->`
- `input/select.ex:337` — same literal
- `input/multi_select.ex:579` — same literal

The stated goal ("the next reader sees one contract instead of three copies", `options.ex:9-13`) is
only half met: adding a fourth token to `@tokens` still requires editing three other files, and
`Options.expand/1`'s own guard would then diverge from the callers' — a new token would silently fall
through to the caller's `nil`/passthrough arm rather than expanding.

Guards can't call a remote function, so the fix is a shared compile-time attribute or a dispatching
helper, e.g. give `Options` an `expand_or/2`:

```elixir
# options.ex
def expand(token) when token in @tokens, do: ...
def expand(other), do: other   # or {:error, :not_a_token}
```

and let each caller do `Keyword.get(opts, :options) |> Options.expand()` with the non-token arms
unchanged. Alternatively `@option_tokens Options.tokens()` in each caller — one line each, and the
guard then tracks `@tokens` automatically.

### 5. `hooks.ex:429` unsubscribe means the `image-picker` refresh stops for that image

`hooks.ex:320-322` runs `maybe_unsubscribe_from_image(image)` **before**
`send_update(ImagePicker, refresh_images: true)`. Correct for the current message, but after the first
`:processed` broadcast the form process no longer receives `brando:image:<id>` at all. Any *later*
update to that image that does not originate from this form — another admin re-cropping it, a
re-process triggered from the image list — no longer refreshes this form's picker or its
`update_entry_relation` path. Previously the subscription lived for the session and did.

The reasoning at `hooks.ex:419-424` ("every form-side subscribe sits immediately before a processing
round is queued, so a later round re-subscribes itself") holds for rounds *this* form starts. It does
not hold for rounds started elsewhere. Whether that matters is a product call — but the comment
should say the subscription is now scoped to *locally initiated* processing rounds, since the next
reader will otherwise read it as unconditional.

Note also that `refresh_images: true` (`hooks.ex:322`) now costs a **full `list_images/1` query**
(`image_picker.ex:502`, reached via `assign_folder_state/2`) on every `[:image, :updated]`, whether or
not the picker is open — and that fires once per image during a bulk upload. Previously the cached
`:images` assign meant the same thing, so this is not a regression, but it is the one place where the
`image_picker.ex` tradeoff compounds: N images uploaded → N full-library queries. Worth a
`if socket.assigns.picker_open?` guard on the `refresh_images` update, in a later pass.

---

## Checked and clear

Recorded so the next reviewer does not re-derive these.

- **`Dsl.transform_form/1` compile-time `resolve/1`** (`dsl.ex:275-309`) — no runtime path expects an
  unresolved token. `%Forms.Form{}` / `%Forms.Subform{}` are never constructed outside the Spark DSL
  (grep across `*.ex`: only pattern matches in `forms.ex`, `verifier.ex`, `ai/translation.ex`,
  `blueprint/dsl.ex`). `Fieldset.Field.render/1:28` now reads the pre-resolved value. Sub-fields of a
  Subform are rendered by a *different* module (`subform.ex:124,166` → `Subform.Field.render`) which
  never resolved components, so not visiting `sub_fields` in `resolve_fieldset_components/1` preserves
  behaviour. `resolve_field_component/1`'s catch-all is correct: `Forms.Input` does carry a
  `:component` key (`forms/input.ex:6`) but the `@input` entity schema never populates it, so it is
  always `nil` and `resolve(nil)` returns `nil` — the `{:live_component, Mod}` tuple lives on `:type`,
  not `:component`, so `resolve/1` cannot be handed a tuple.
- **The `transformers` comprehension** (`dsl.ex:287-292`) reads the *resolved* tabs and matches
  `component: nil`. `resolve(nil) == nil`, so a token-free transformer subform still matches. No drift.
- **`block_field.ex` `connected?/1` gating** (`:657-663`, `:674-681`) — subscribe and
  `request_blocks_sync/1` are gated symmetrically, and both call sites
  (`maybe_arm_blocks_topic/1:644,648` and `initialize_blocks/2:700,716`) go through the gated helpers.
  `blocks_topic` is still assigned on the dead render, which is what the connected mount needs.
  No subscribe/unsubscribe asymmetry: `block_field.ex` has no unsubscribe, and does not need one —
  the topic dies with the process.
- **`reject_deleted/2`** (`blocks.ex:915-946`) — the deleted `mark_as_deleted` clause was genuinely
  dead. `%{action: :delete}` and `%{action: :replace}` cover the reachable states; `:ignore` never
  reaches here because `put_assoc` skips it. Recursion into children is preserved on both the root and
  child branches.
- **Dropping `Map.put(:action, :validate)`** — no top-level branch on form/changeset action found in
  the changed files. `Phoenix.Component.used_input?/1` reads `form.params`, not `form.source.action`.
  The `.action` reads that remain in the tree are all on *nested* changesets testing
  `:replace`/`:delete` (e.g. `block.ex`, `subform_helpers.ex`), which are set by Ecto's relation
  machinery, not by the dropped `put`.
- **`legacy.ex` deletion** — no remaining reference to `Brando.Blueprint.Forms.Legacy` or an
  `imports:` entry in `dsl.ex:269-272`.
- **`assign_new` conversions in `block.ex:902-981`** — `:uid`, `:type`, `:multi`, `:module_id`,
  `:parent_id` etc. are all block *identity*, invariant for the life of the component; a block's type
  cannot change without a remount. `:active`, `:deleted`, `:form_has_changes`, `:form_is_new`
  (`:898-901`) correctly stayed plain `assign/3` — they track the changeset. No second
  `transformer_changesets`-shaped bug found in the changed files.

## Pre-existing (not deep-analysed, per scope)

- `lib/brando_admin/components/form/block.ex:906-924` — `try/rescue` around `Changeset.get_assoc/2` for
  `has_vars?`/`has_table_rows?` is rescue-as-control-flow; a `case` on the relation type would be
  explicit. Untouched by this diff.
- `lib/brando_admin/components/form/block/render.ex:295` — inline `style=` on the unknown-block-type
  debug render, against the repo's no-inline-styles rule.
