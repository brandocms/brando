# Brando CMS - Commands and Style Guide

## Build & Test Commands
- Install dependencies: `mix deps.get`
- Compile project: `mix compile`
- Run Elixir tests: `mix test`
- Run specific test: `mix test path/to/test_file.exs:line_number`
- Start e2e project server (for use with MCP): `cd e2e && ./run_e2e.sh` - the server starts on port 4444
- Run end to end tests: `cd e2e && source .envrc && ./test_e2e.sh --reset` (user will ask Claude to run these)
- E2E login credentials: email `admin@brandocms.com`, password `brandocms`
- E2E test workflow:
  - **CRITICAL**: Always `source .envrc` in the `e2e/` folder before running any e2e commands
  - **E2E logger level**: Default is `:warning` in `e2e/config/e2e.exs`. Change to `:debug` when troubleshooting server-side issues, then change back.
  - **If JS/CSS changed**: Rebuild assets first: `cd e2e/assets/backend && pnpm build`
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

### Block Editor: single-owner state & ops (Phase 3 architecture)

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

## Deployment (Florist)

Brando projects are deployed using [Florist](https://github.com/brandocms/florist) (`/Users/trond/dev/elixir/florist`), a zero-downtime deployment tool for Elixir applications.

### Deployment flow

```
Local: Docker build → OTP release tarball → Florist uploads via SSH → unpacks on server
```

1. `florist prod release:build` — Docker builds the OTP release (Vite builds CSS/JS inside the container, `mix brando.digest` runs, everything is baked into `priv/static/` inside the release)
2. `florist prod release:copy_from_docker` — extracts tarball from Docker image
3. `florist prod release:upload` — SSH uploads to server
4. `florist prod release:unpack` — extracts to `releases/{version}/`, symlinks `current → releases/{version}`
5. Service restarts via systemd

### Server directory structure (single deployment)

```
/sites/prod/{project_name}/
├── current → releases/x.y.z/   ← symlink to active release
├── releases/
│   ├── 1.0.0/
│   └── 1.1.0/                  ← priv/static/ is inside the release
├── media/                       ← persistent, NOT inside the release
├── log/
├── sql/
└── etc/
```

### Server directory structure (blue/green deployment)

```
/sites/prod/{project_name}/
├── blue/
│   ├── current → releases/x.y.z/
│   └── releases/
├── green/
│   ├── current → releases/a.b.c/
│   └── releases/
├── active-environment           ← contains "blue" or "green"
├── media/                       ← shared between blue and green via symlink
├── log/
├── sql/
└── etc/
```

- Blue and green each run their own systemd service on different ports
- Media is shared: `blue/current/media → ../../media` (symlink created by Florist)
- Traffic switching: Florist updates Traefik/nginx config to point to the new port
- Health check polls the inactive environment before switching traffic
- Keeps last 5 releases per environment, cleans up older ones

### Key implications for Brando development

- **Assets are baked into the release** — `priv/static/` is built during Docker build and included in the tarball. There is no separate asset upload step.
- **Media lives outside the release** — `media/` is persistent on the server and symlinked into the release. Never assume `media/` is inside `priv/`.
- **Blue/green means two running instances** — both share the same database and media directory, but each has its own release with its own `priv/static/`.
- **Rollback is instant** — switch traffic back to the other color. No rebuild needed.
- **`priv/static/` is ephemeral** — it gets rebuilt from scratch in every Docker build. Don't store persistent state there.

<!-- Content Refs Architecture is documented in the brando-blocks skill:
     .claude/skills/brando-blocks/SKILL.md §4 "Schema Quick Reference" -->