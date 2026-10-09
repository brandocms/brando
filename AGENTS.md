# Brando CMS - Agent Commands and Style Guide

## Build & Test Commands
- Fresh worktree: `scripts/worktree-setup` (deps, private test DB, pnpm 10 installs, Git hooks; prints the env to use)
- Before pushing: `mix check` (CI's fast gates; the pre-push hook runs `--fast`, `SKIP_CHECK=1` bypasses)
- Wait for CI: `scripts/ci-wait <PR>` (background; silent until a summary line, then one line per failed job: known flake from `.github/known-flakes.txt` or real failure; `--rerun-flakes` reruns flakes once)
- Start e2e project server (for use with MCP): `cd e2e && ./run_e2e.sh` - the server starts on port 4444
- End to end tests: the whole E2E suite green is the bar for done (CI runs it on every PR). While working, run the single specs that cover your change (below); for the whole suite locally, `cd e2e && source .envrc && ./test_e2e_parallel.sh 2 --reset`
- E2E login credentials: email `admin@brandocms.com`, password `brandocms`
- E2E test workflow:
  - **CRITICAL**: Always `source .envrc` in the `e2e/` folder before running any e2e commands
  - **E2E logger level**: Default is `:warning` in `e2e/config/e2e.exs`. Change to `:debug` when troubleshooting server-side issues, then change back.
  - **If JS/CSS changed**: Rebuild assets first: `cd e2e/assets/backend && pnpm build`
  - **Frontend asset validation boundary**: Do not run or report a standalone build from Brando's root `assets/` directory as a validation gate. Brando's frontend assets are consumed by the actual applications through Yalc and compiled by each consumer application's Vite build. For repository work, validate JS/CSS with the E2E consumer build above and the relevant E2E tests. Only investigate a standalone root asset build if the user explicitly asks for it.
  - **Full suite with reset**: `cd e2e && source .envrc && ./test_e2e.sh --reset`
  - **Single test with reset**: `cd e2e && source .envrc && ./test_e2e.sh --reset tests/path/to/test.spec.js`
  - **When troubleshooting/fixing failing tests**: Always run only the specific failing test, not the full suite. Use the single test command above.
  - **Individual tests** (server already running): `cd e2e/playwright && pnpm playwright test tests/path/to/test.spec.js`
  - **Start server manually**: `cd e2e && source .envrc && MIX_ENV=e2e PORT=4444 mix phx.server`
  - **Seeding**: `cd e2e && source .envrc && BRANDO_SEEDING=true MIX_ENV=e2e mix run priv/repo/e2e_seeds.exs`
  - **Screenshots**: use `e2e/scripts/server.sh`, `e2e/scripts/shoot.mjs` and `scripts/pr-shots` (see "Screenshot tools" in the [Admin UI design guide](docs/admin-ui-design.md)); never `pkill` a server or seed with SQL.
  - **E2E migrations**: `e2e/priv/repo/migrations` is a **symlink** to `priv/repo/migrations/`. The e2e project shares the same test migration file as unit tests. Any schema changes to the monolithic test migration file automatically apply to both.
- Test coverage (Elixir's built-in `:cover`; CI runs it weekly via `.github/workflows/coverage.yml`):
  - Unit only: `mix test --cover`
  - Unit + E2E merged: `mix test --cover --export-coverage unit`, then an E2E run with `BRANDO_E2E_COVER=1` (the server exports `cover/e2e.coverdata` on shutdown), then `mix test.coverage` in the Brando root
  - lcov for Codecov (after the above): `MIX_ENV=test mix run --no-start .github/scripts/coverage_lcov.exs` writes `cover/lcov.info`
- Translations: add strings in code, run `mix gettext.extract --merge` (never add or remove catalogue entries by hand), translate the new Norwegian entries; see [TRANSLATIONS.md](TRANSLATIONS.md), which also covers the merge driver for rebases.
- Code analysis:
  - Refactoring opportunities: `mix credo suggest --format json --all --only refactor`
  - Design: `mix credo suggest --format json --all --only design`
  - Readability: `mix credo suggest --format json --all --only readability`
  - Warnings: `mix credo suggest --format json --all --only warning`
  - Check single check example: `mix credo --format json --all --checks Credo.Check.Refactor.LongQuoteBlocks`

## Scope
- Ask when a request is ambiguous or leaves a product decision open, rather than guessing.
- Keep a change to its task: fix bugs and optimise without changing behaviour or unrelated code, and propose the rest.

## Reviewing
- Review a change (yours before pushing, or a PR) against [CODING_STANDARDS.md](CODING_STANDARDS.md): tests, field sync, `:has()`, UI.
- Independent bug hunt on a branch or PR: the read-only `reviewer` subagent ([.claude/agents/reviewer.md](.claude/agents/reviewer.md)).
- Second opinion from another model family, in parallel with the reviewer:
  `scripts/sol-audit "<intent of the change>"` (OpenAI Codex, `gpt-6.1-sol`, read-only, same
  reviewer instructions; Codex CLI ≥ 0.162). The two miss different things: on the 0.55 module renames,
  Codex found scoping bugs four Claude rounds had passed, and each found one the other missed.
  Merge both lists before fixing. Codex reviews statically, so reproduce each finding with a
  failing test first.

## Admin UI design
- **Admin screens** follow the [Admin UI design guide](docs/admin-ui-design.md). Read its index first, then only the sections the screen needs; its Utilities example is the reference alongside existing components.
- **Scope `:has()` to a row, card or modal**, whose subject cannot contain the block editor. A `:has()` on an ancestor of the editor (`body`, `#brando-main`, the layout's `.content`) is re-checked for every node LiveView inserts, and one took a heavy entry from 8s to 61s. Page-level state comes from the server as a class; open widgets style from their trigger's `aria-expanded`. Details and how to verify: CODING_STANDARDS.md.

## Subsystem skills and docs
Load only what the change touches:
- **Blocks** (block state, ops, refs, vars, containers, block changesets): [brando-blocks](.claude/skills/brando-blocks/SKILL.md). Read it before touching block state.
- **Uploads and media fields** (asset browser, pickers, UploadManager): [brando-uploads](.claude/skills/brando-uploads/SKILL.md); architecture and transports in `docs/UPLOADER.md`.
- **Admin form state** (parent/component state, transformers, save collection, recovery): [brando-admin-forms](.claude/skills/brando-admin-forms/SKILL.md). Before reading the 7,000-line `components/form.ex`, find the area in its [section map](.claude/skills/brando-admin-forms/form-map.md).
- **Live preview** (caches, transport, iframe recovery): [brando-live-preview](.claude/skills/brando-live-preview/SKILL.md).
- **Deploying** (Florist releases, server layout, where assets and media live): [florist-deploy](.claude/skills/florist-deploy/SKILL.md).
- **Changesets with associations or embeds** (`put_assoc`, copied structs, adding rows to a LiveView form): [Ecto changeset patterns](docs/ecto-changeset-patterns.md).
- **Blueprint DSL**: `guides/blueprints.md` and the guides it links; authorization: `guides/authorization.md`; tenant job context: `Brando.Tenant.Job`. Before adding a skill, read [the skill audit](docs/agent-skill-audit.md).

## LiveView components
- **Stable component IDs**: a live_component `id` must be stable (not nil, not derived from rebuilt form internals). LiveView raises for a nil ID; a changed ID, a fresh random UID included, mounts a new component with a new CID.
- **`form.index` for DOM IDs** in nested forms: new records have no database ID yet.
- **CID stability**: a remounted component gets a new `@myself`; stored references to the old CID go dead.
- **Constants in templates**: assign a constant list once in `mount/1` with `assign_new/3` and reference the assign (`opts={[options: @my_options]}`) rather than calling `my_options()` in HEEx. The gain is an explicit dependency and no rebuild per component invocation; a call with no assign dependencies is already skipped in tracked patches.
- **Derived assigns in function components are always "changed"**: a function
  component's assigns hold only what the caller passed, so `assign(assigns, :uid, …)`
  marks `:uid` changed on every render and re-sends every expression reading it.
  Expressions reading an `inputs_for` `:let` variable are never tracked either. In the
  block editor this re-sent each block's whole form for an unrelated entry-field change
  (320 KB per keystroke at 115 blocks). Use `assign_derived/3` and `nested_block_form/1`
  in `Block.Render`, or pass precomputed values from the LiveComponent.
- **Sticky JS for persistent client-side decorations**: DOM state that must survive
  LiveView patches (field presence, etc.) goes through the hook's `this.js()`
  commands (`addClass`/`setAttribute`/… → `DOM.putSticky`); plain
  `classList`/`setAttribute` mutations are wiped on the next morphdom pass of that
  element. Inline styles and injected child nodes are not sticky-covered: express
  them in CSS keyed on a sticky data attribute (see `assets/src/Presence/fieldPresence.js`
  and the presence palette in `Block.css`). Transient state (drag hover, dropdown open)
  is fine as plain mutations.

## Code style
- Prefer aliases over imports, and import only what's needed: `import Ecto.Query, only: [from: 2]`.
- Arrange Blueprint files as attributes, assets, relations, listings, forms.
