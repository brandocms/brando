# Brando CMS - Commands and Style Guide

## Build & Test Commands
- Install dependencies: `mix deps.get`
- Compile project: `mix compile`
- Run Elixir tests: `mix test`
- Run specific test: `mix test path/to/test_file.exs:line_number`
- Run end to end tests: `cd e2e/e2e_project && ./test_e2e.sh --reset` (user runs these, not Claude)
- Start e2e project server (for use with MCP): `cd e2e/e2e_project && ./run_e2e.sh` - the server starts on port 4444
- Code analysis:
  - Refactoring opportunities: `mix credo suggest --format json --all --only refactor`
  - Design: `mix credo suggest --format json --all --only design`
  - Readability: `mix credo suggest --format json --all --only readability`
  - Warnings: `mix credo suggest --format json --all --only warning`
  - Check single check example: `mix credo --format json --all --checks Credo.Check.Refactor.LongQuoteBlocks`
- Type checking: `mix dialyzer`
- Format code: `mix format`
- Reset database: `mix ecto.reset`
- Watch tests: `mix test.watch`

## Core Principles
- Write clean, concise, functional code using small, focused functions.
- **Explicit Over Implicit**: Prefer clarity over magic.
- **Single Responsibility**: Each module and function should do one thing well.
- **Easy to Change**: Design for maintainability and future change.
- **YAGNI**: Don't build features until they're needed.
- If any of my requests are not clear, ask me to clarify.
- If you have better suggestions, feel free to suggest them.

## LiveView, Phoenix and Ecto (+ Forms & Changesets)
- Use these technologies as intended

### LiveView Component Patterns
- **Stable Component IDs**: live_component `id` props must be stable (not nil or derived from rebuilt form internals). If nil, a random ID is generated on each render, causing remounting and new CIDs.
- **Form Index for DOM IDs**: Use `form.index` (not database ID) for DOM element identification in nested forms. New records don't have database IDs yet.
- **CID Stability**: When a component remounts, its `@myself` CID changes. Any stored references to the old CID become invalid.
- **Constant Options in Templates**: Never call functions that return constant lists directly in HEEx templates (e.g., `opts={[options: my_options()]}`). Instead, assign constants once in `mount/1` using `assign_new/3` and reference via assigns (e.g., `opts={[options: @my_options]}`). This avoids re-evaluating the function on every render.

### Ecto Changeset Patterns
- **put_assoc handles FK automatically**: Don't mix `put_change(:gallery_id, nil)` with `put_assoc(:gallery, ...)`. Let `put_assoc` manage the foreign key.
- **on_replace for belongs_to**: Use `:nilify` when you need to disassociate (set FK to nil). Default `:raise` prevents any association changes.
- **NotLoaded associations**: Always check for `%Ecto.Association.NotLoaded{}` before passing associations to `put_assoc`. NotLoaded structs are truthy but cause changeset errors.
- **Marking structs as new**: When copying a SINGLE struct for insertion, set `__meta__.state` to `:built` so Ecto knows it's a new record. **Note**: This does NOT work for `put_assoc` with multiple nil-ID structs - use maps instead (see below).

```elixir
# Mark as new record (not loaded with nil ID)
struct
|> Map.merge(%{id: nil, parent_id: nil})
|> put_in([Access.key(:__meta__), Access.key(:state)], :built)
```

- **put_assoc with multiple new records**: When passing multiple new records to `put_assoc`, use maps (not changesets from nil-ID structs). Ecto creates distinct insert changesets for each map.

```elixir
# ❌ BAD: Multiple changesets from nil-ID structs - all have same nil ID
objects
|> Enum.map(fn obj ->
  if is_nil(obj.id), do: Ecto.Changeset.change(obj), else: ...
end)
|> then(&Ecto.Changeset.put_assoc(parent, :objects, &1))

# ✅ GOOD: Maps for new records - each is distinct
objects
|> Enum.map(fn obj ->
  if is_nil(obj.id) do
    %{field1: obj.field1, field2: obj.field2}
  else
    Ecto.Changeset.change(obj, %{...})
  end
end)
|> then(&Ecto.Changeset.put_assoc(parent, :objects, &1))
```

- **Avoiding duplicate primary key warnings**: When using `apply_changes()` followed by another changeset call, don't pass embedded associations with nil IDs to the next changeset. See [Ecto #3514](https://github.com/elixir-ecto/ecto/issues/3514).

```elixir
# ❌ BAD: Passes vars/refs with nil IDs to changeset
applied = Changeset.apply_changes(changeset)
Block.changeset(applied, params)  # ← Ecto sees vars/refs as existing, warns about duplicates

# ✅ GOOD: Clear vars/refs for new records before passing to changeset
applied = Changeset.apply_changes(changeset)

struct_for_changeset =
  if is_nil(applied.id) do
    # New record - clear embedded associations so Ecto treats params as inserts
    Map.merge(applied, %{vars: [], refs: []})
  else
    # Existing record - keep associations for matching
    applied
  end

Block.changeset(struct_for_changeset, params)
```

**Why this happens**: When `apply_changes()` creates a struct with embedded associations (vars/refs) that have `nil` IDs, and you pass that struct to a changeset function, Ecto assumes those are existing associations and tries to match them with incoming params. Multiple associations with `nil` IDs trigger "duplicate primary key" warnings. Clearing them for new records tells Ecto to treat all incoming params as fresh inserts.

### Dynamic Associations in LiveView (The "Append Changeset" Pattern)
- **Goal**: Add new child records (e.g., table rows) without losing existing form state or causing "Duplicate PK" errors.
- **Anti-Pattern**: Converting existing changesets to maps/params. This wipes out pending user input.
- **Pattern**:
  1. **Get State**: `current = Ecto.Changeset.get_assoc(parent_changeset, :items)`
  2. **Create New**: `new_item_cs = change(%Item{}) |> Map.put(:action, :insert)`
  3. **Append**: `put_assoc(parent_changeset, :items, current ++ [new_item_cs])`
  * **Note**: If `new_item_cs` has its own nested items (e.g. `vars`), pass them as **MAPS** to `put_assoc` inside the changeset config, to avoid "Duplicate PK" errors (see "put_assoc with multiple new records" above).
- **Validation compatibility**: In your validate handler, continue to strip non-persisted structs from `data` before casting. The `params` (populated by hidden inputs from the new changeset) will correctly recreate the new item.

### Safe Ecto Association Handling in Block Events
- **Problem**: `Ecto.Changeset.get_assoc(changeset, :assoc)` returns `%Ecto.Association.NotLoaded{}` if the association is not preloaded and not in changes, causing `Enum` functions to crash.
- **Solution**: Always guard or wrap retrieval. Use a helper like `get_assoc_list` to convert `NotLoaded` -> `[]`.
- **Problem**: Passing maps to `put_assoc` that contain `NotLoaded` values in association keys will crash `put_assoc`.
- **Solution**: When converting structs to maps for `put_assoc` (e.g. nested items), explicitly DROP association keys (e.g. `:block`, `:module`, `:parent`). Safe pattern: `Map.from_struct() |> Map.drop(association_keys)`.

### Reusing Changesets from get_assoc in put_assoc
- **Problem**: Changesets returned from `get_assoc` after a `cast_assoc` operation may have `action: :replace` or `action: :delete`. Passing these to another `put_assoc` causes: `RuntimeError: cannot replace related %Schema{...}`.
- **Solution**: Filter out changesets with `:replace` or `:delete` actions before reusing them in `put_assoc`.

```elixir
# When appending a new item to an existing association:
current_rows =
  changeset
  |> Ecto.Changeset.get_assoc(:table_rows)
  |> Enum.map(fn
    %Ecto.Changeset{} = cs -> cs
    struct -> Ecto.Changeset.change(struct)
  end)
  # Filter out rows that were already processed by cast_assoc
  |> Enum.reject(fn cs -> cs.action in [:replace, :delete] end)

# Now safe to use in put_assoc
Ecto.Changeset.put_assoc(changeset, :table_rows, current_rows ++ [new_row_changeset])
```

**Why this works**: Rows with `:delete` action will be re-marked for deletion by `on_replace: :delete_if_exists` when they're not in the new list. Rows with `:replace` action should not be reused as they've already been processed.

### Table Rows and validate_block Pattern
- **Problem**: In `validate_block`, using `apply_changes(changeset)` as the base for the next changeset causes edits to multiple rows to not persist. Only the last edited row's changes are saved.
- **Root Cause**: `cast_assoc` compares params against `changeset.data`. When `apply_changes` is used, previous edits are baked into the data, so `cast_assoc` doesn't detect them as changes.
- **Solution**: Use `changeset.data` (original DB values) as the base, but filter `table_rows` to only include persisted rows (those with IDs). The params contain all current form values, so `cast_assoc` will properly detect all changes.

```elixir
# In validate_block for entry_block:
original_data = changeset.data
applied_block = Changeset.apply_changes(changeset)

# For the inner block, use original data but filter table_rows to persisted only
inner_block = original_data.block
persisted_rows = Enum.filter(inner_block.table_rows || [], & &1.id)
inner_block = Map.put(inner_block, :table_rows, persisted_rows)

# Use this as the base for the new changeset
block_module.changeset(put_in(original_data.block, inner_block), params, user)
```

## Code Style Guidelines
- Follow Elixir style conventions
- Line length: 122 characters max (see .formatter.exs)
- Use descriptive variable and function names: e.g., `user_signed_in?`, `calculate_total`.
- Prefer higher-order functions and recursion over imperative loops.
- Use snake_case for variables and functions
- Module names in PascalCase
- Prefer pattern matching over conditionals
- Prefer using aliases over imports.
- Modules should have @moduledoc
- Public functions should have @doc
- Use explicit returns with :ok/:error tuples
- Import only what's needed with `import Ecto.Query, only: [from: 2]`
- Arrange Blueprint files with attributes, assets, relations, listings, forms
- Follow DSL conventions defined in .formatter.exs
- Follow standard Elixir practices and let `mix format <filename>` take care of formatting (run before committing code).

## Documentation and Quality
- Describe why, not what it does.
- **Document Public Functions**: Add `@doc` to all public functions.
- **Examples in Docs**: Include examples in documentation (as doctests when possible).
- **Cautious Refactoring**: Propose bug fixes or optimizations without changing behavior or unrelated code.
- **Comments**: Write comments only when information cannot be included in docs.

## Content Refs Architecture
- **Two-Layer Approach**: Refs use both block data (configuration/overrides) and asset associations (direct media references)
- **Polymorphic Data**: Ref's data field can contain various block types with specific configurations
- **Media Associations**: Refs can have direct associations to :image, :video, :gallery, and :file
- **Override Mechanism**: Block data overrides take precedence over base asset attributes when merging
- **Preloading Pattern**: Always preload refs with their associations: `preload: [:image, :video, gallery: [gallery_objects: [:image]]]`
- **Apply Ref Pattern**: Each block type implements `apply_ref` to handle syncing with module changes while preserving local customizations
- **Picture Block Merging**: Picture refs merge image data with block overrides (:title, :credits, :alt, :picture_class, :img_class, etc.)