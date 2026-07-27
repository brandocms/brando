# Brando CMS - Agent Commands and Style Guide

## Build & Test Commands
- Start e2e project server (for use with MCP): `cd e2e && ./run_e2e.sh` - the server starts on port 4444
- Run end to end tests: `cd e2e && source .envrc && ./test_e2e.sh --reset` (user will ask Claude to run these)
- E2E login credentials: email `admin@brandocms.com`, password `brandocms`
- E2E test workflow:
  - **CRITICAL**: Always `source .envrc` in the `e2e/` folder before running any e2e commands
  - **E2E logger level**: Default is `:warning` in `e2e/config/e2e.exs`. Change to `:debug` when troubleshooting server-side issues, then change back.
  - **If JS/CSS changed**: Rebuild assets first: `cd e2e/assets/backend && pnpm build`
  - **Frontend asset validation boundary**: Do not run or report a standalone build from Brando's root `assets/` directory as a validation gate. Brando's frontend assets are consumed by the actual applications through Yalc and compiled by each consumer application's Vite build. For repository work, validate JS/CSS with the E2E consumer build above and the relevant E2E tests. Only investigate a standalone root asset build if the user explicitly asks for it.
  - **Full suite with reset**: `cd e2e && source .envrc && ./test_e2e.sh --reset`
  - **Single test with reset**: `cd e2e && source .envrc && ./test_e2e.sh --reset tests/path/to/test.spec.js`
  - **When troubleshooting/fixing failing tests**: Always run only the specific failing test, not the full suite. Use the single test command above.
  - **Individual tests** (server already running): `cd e2e/e2e/playwright && pnpm playwright test tests/path/to/test.spec.js`
  - **Start server manually**: `cd e2e && source .envrc && MIX_ENV=e2e PORT=4444 mix phx.server`
  - **Seeding**: `cd e2e && source .envrc && BRANDO_SEEDING=true MIX_ENV=e2e mix run priv/repo/e2e_seeds.exs`
  - **E2E migrations**: `e2e/priv/repo/migrations` is a **symlink** to `priv/repo/migrations/`. The e2e project shares the same test migration file as unit tests. Any schema changes to the monolithic test migration file automatically apply to both.
- Code analysis:
  - Refactoring opportunities: `mix credo suggest --format json --all --only refactor`
  - Design: `mix credo suggest --format json --all --only design`
  - Readability: `mix credo suggest --format json --all --only readability`
  - Warnings: `mix credo suggest --format json --all --only warning`
  - Check single check example: `mix credo --format json --all --checks Credo.Check.Refactor.LongQuoteBlocks`

## Core Principles
- If any of my requests are not clear, ask me to clarify.
- If you have better suggestions, feel free to suggest them.

## LiveView, Phoenix and Ecto (+ Forms & Changesets)

### LiveView Component Patterns
- **Stable Component IDs**: live_component `id` props must be stable (not nil or derived from rebuilt form internals). If nil, a random ID is generated on each render, causing remounting and new CIDs.
- **Form Index for DOM IDs**: Use `form.index` (not database ID) for DOM element identification in nested forms. New records don't have database IDs yet.
- **CID Stability**: When a component remounts, its `@myself` CID changes. Any stored references to the old CID become invalid.
- **Constant Options in Templates**: Never call functions that return constant lists directly in HEEx templates (e.g., `opts={[options: my_options()]}`). Instead, assign constants once in `mount/1` using `assign_new/3` and reference via assigns (e.g., `opts={[options: @my_options]}`). This avoids re-evaluating the function on every render.
- **Sticky JS for persistent client-side decorations**: DOM state that must survive
  LiveView patches (presence locks, etc.) MUST go through the hook's `this.js()`
  commands (`addClass`/`setAttribute`/… → `DOM.putSticky`) — plain
  `classList`/`setAttribute` mutations are wiped on the next morphdom pass of that
  element. Inline styles and injected child nodes are NOT sticky-covered: express
  them in CSS keyed on a sticky data attribute (see `assets/src/Presence/blockLocks.js`
  + the presence palette in `Block.css`). Transient state (drag hover, dropdown open)
  is fine as plain mutations.

### Block Editor: single-owner state & ops (Phase 3 architecture)

<!-- The full Phase 3 single-owner/ops architecture (reducer ops, the
     `assign_block_form/2` chokepoint, store materialization, `replace_form`,
     op-snapshot sync, delete-undo replay) lives in the brando-blocks skill:
     .claude/skills/brando-blocks/SKILL.md — read it before touching block state. -->

### Media asset fields, browsers, and uploads

<!-- The asset browser / picker / UploadManager contracts live in the
     brando-uploads skill: .claude/skills/brando-uploads/SKILL.md.
     Architecture and transport matrix: docs/UPLOADER.md. -->

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

- **Avoiding duplicate primary key warnings**: When using `apply_changes()` followed by another changeset call, don't pass embedded associations with nil IDs to the next changeset — clear them first so Ecto treats params as fresh inserts. See [Ecto #3514](https://github.com/elixir-ecto/ecto/issues/3514).

### Dynamic Associations in LiveView (The "Append Changeset" Pattern)
- **Goal**: Add new child records (e.g., table rows) without losing existing form state or causing "Duplicate PK" errors.
- **Anti-Pattern**: Converting existing changesets to maps/params. This wipes out pending user input.
- **Pattern**:
  1. **Get State**: `current = Ecto.Changeset.get_assoc(parent_changeset, :items)`
  2. **Create New**: `new_item_cs = change(%Item{}) |> Map.put(:action, :insert)`
  3. **Append**: `put_assoc(parent_changeset, :items, current ++ [new_item_cs])`
  * **Note**: If `new_item_cs` has its own nested items (e.g. `vars`), pass them as **MAPS** to `put_assoc` inside the changeset config, to avoid "Duplicate PK" errors (see "put_assoc with multiple new records" above).
- **Validation compatibility**: In your validate handler, continue to strip non-persisted structs from `data` before casting. The `params` (populated by hidden inputs from the new changeset) will correctly recreate the new item.

<!-- Block-specific Ecto patterns (NotLoaded guards, reusing changesets from get_assoc,
     validate_block base selection) are documented in the brando-blocks skill:
     .claude/skills/brando-blocks/SKILL.md §11 "Common Pitfalls" -->

## Code Style Guidelines
- Prefer higher-order functions and recursion over imperative loops.
- Prefer using aliases over imports.
- Import only what's needed with `import Ecto.Query, only: [from: 2]`
- Arrange Blueprint files with attributes, assets, relations, listings, forms

## Documentation and Quality
- **Cautious Refactoring**: Propose bug fixes or optimizations without changing behavior or unrelated code.

## Deployment (Florist)

<!-- Florist deployment flow, server directory layout, blue/green, and the
     priv/static + media implications live in the florist-deploy skill:
     .claude/skills/florist-deploy/SKILL.md -->

<!-- Content Refs Architecture is documented in the brando-blocks skill:
     .claude/skills/brando-blocks/SKILL.md §4 "Schema Quick Reference" -->
