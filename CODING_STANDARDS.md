# Coding standards

The judgement calls to check when reviewing a change, yours before you push
or someone else's PR. Each rule is the target, the reason, and an example.
CI enforces the mechanical rules (`.github/workflows/ci.yml`); `AGENTS.md`
and the subsystem skills hold what you need while implementing, and apply
here too. For an independent second review of a branch or PR, run the
read-only `reviewer` subagent (`.claude/agents/reviewer.md`); its checklist
covers the bug classes that have reached review here.

## Tests

### Isolated from global state

A test leaves the global state it found. Shared state outlives the database
sandbox, so a leak shows up as another test failing, by suite order.

- **Put back every shared cache a test changes.** Call
  `preserve_cache([:identity, :seo])` (`Brando.Test.Support`) in `setup`, or
  snapshot the entry and write it back in `on_exit`. ServicesTest refreshed the
  identity cache through `Sites.update_identity`, and a later JSON-LD graph
  grew a Service node (`e2539f7fa`). The `TestCacheRestore` Credo check
  (`credo/checks/`, run on `test/` in CI) catches direct writes:
  `Cachex.clear`, `Brando.Cache.put`, `Brando.Cache.SEO.set()` and the like.
  It cannot see a context function that refreshes a cache (`update_identity`,
  `update_seo`, `create_global_set`), so check those by hand: a test that
  calls one needs the restore too.
- **An unshared sandbox.** Start the owner with `Sandbox.start_owner!/1` and
  `Sandbox.allow/3` the processes that need it; in shared mode a process left
  over from an earlier test can take the connection and lock rows (#3119).
  Shared mode belongs only in an `async: false` case template, for processes
  that do not carry the test in their `$callers` (a GenServer in the
  application's supervision tree); a LiveView mounted with `live/2` and the
  Tasks it starts do carry it. The `TestSandboxShared` Credo check enforces
  this against the allowlist, with reasons, in `.credo.exs`.
- **Application env through `put_test_env/2`**, which restores an absent key
  as absent; a restored `nil` breaks the next `get_env/3` default.
- **Unique values against unique indexes.** Take ids and keys from
  `System.unique_integer([:positive])` or a factory sequence, not `1`. An async
  test inserting `(entry_id: 1, schema)` waited for another test's identical
  row to roll back and timed out in CI (`item_derive_key_test`, `ed7196b30`).
- **Order by `sequence`, then `id`.** Rows that share a sequence come back in
  Postgres' physical order, which changes between loads (the `set_field_test`
  flake, `30670e35c`). The same tie-break belongs in the code's own queries.
- **Build the state the test depends on.** A test holds whatever it needs
  about time, history or the database itself. The archive tests compared
  against migrations recorded when the test database was built, so they passed
  on an old database and failed on CI's fresh one (`f78340461`).
- **A process registry entry can outlive its process.** After killing or
  stopping a process, wait for its `:DOWN`, or make the code treat a dead
  registered pid as absent. The edit session lookup returned a pid the
  Registry had not yet removed (`d06740f1d`).

### Async unless something shared says otherwise

A synchronous module runs alone, after every async one, so the unit suite
takes as long as its longest chain of synchronous modules. A new module is
`async: true`, `Brando.LiveCase` included, unless it touches one of these:

- **Application env other than `:tenancy_mode` and `:authorization_mode`.**
  `put_test_env/2` sets those two for the test and the Tasks, LiveViews and
  channels it starts (`Brando.Test.ScopedEnv`); every other key, and either
  of the two with `global: true` for a GenServer to see, is global. So are
  helpers that save and restore it (`AIStub.configure/0`,
  `AnalyticsStub.configure/1`, `MCPHelpers.setup_fetcher/0`): two at once
  restore each other's values.
- **A singleton cache refreshed from the sandbox**: identity, SEO, global
  sets, palettes, navigation (`Sites.update_identity/2`,
  `create_global_set/2`, and the admin forms that save them). The query
  cache is not one: each test reads only its own entries.
- **DDL or `LOCK TABLE`**: migration tests, `MigrationTemplates`,
  `BlockAudit`, the definition importer. A lock taken in the sandbox lasts
  until the test ends, and blocks every test that writes the table.
- **Igniter tasks that format**: Igniter puts the project's config into the
  application environment while it formats.
- **The whole VM or a shared topic**: atom or process counts, a telemetry
  handler that does not check `self()` against the test and its `$callers`,
  the next broadcast on `"lobby"`.

A module that waits on a fixed row or lock (the authorization lock
`Groups.lock!/0`, the proposal and transfer advisory locks, ProposalFixtures'
pages, the media folders a list or picker creates) is
`async: true, group: :shared_locks`: one at a time with the others in that
group, beside everything else. Run a new async module's file with
`--repeat-until-failure`, and the suite with a few `--seed`s.

### Flaky means broken

A test that fails intermittently has a bug in the test or in the code: find
the shared state, race or ordering, fix it, and name the cause in the commit.
Rerun only to reproduce: each example above began as an intermittent failure.

### E2E specs drive the UI in the locale

Switch the admin to Norwegian (`POST /e2e/setup_fixtures/norwegian-admin-user`)
and let the locators name the translated labels:
`getByRole('button', { name: 'Konfigurer' })`. The click fails if a label
falls back to English or the wrong word, which is the coverage that matters.
Assertions whose only job is to match translated prose catch nothing (copy
changes are deliberate) and bill maintenance on every wording fix; leave them
out. Assert on roles, test ids and structure.

## Entry form fields

Every server-side write to an entry form field goes through the form's
local-change path, the one that marks the field as changed for field sync
(`put_local_form/2` in `lib/brando_admin/components/form.ex` once #3071 lands),
so it ships to the other editors in the entry. A write that bypasses it shows
on one screen only, and the next field another editor ships puts the old value
back. #3071 adds the coverage, `test/brando_admin/live/entry_field_sync_test.exs`.

## Upgrade migration templates are history once shipped

Applications copy `priv/templates/brando.upgrade/migrations/*` once and keep
that copy; a later fix to a template reaches only applications that have not
copied it yet (`mix brando.migrations.check` flags unrun copies). Restoring an
archive replays a single-environment template (`case prefix() do`) only over
a copy whose code is a version Brando shipped, so each of those keeps every
shipped version in `priv/templates/brando.upgrade/history/<name>/`.
`test/brando/environments/archive_upgrade_history_test.exs` fails, naming the
file to add, when a template's code changes without a new version there. Add
it; never edit or remove an earlier one.

## CSS: `:has()` never on an ancestor of the block editor

A `:has()` whose subject contains the entry form is re-evaluated for every node
LiveView inserts below it. The block editor inserts tens of thousands, so the
cost is quadratic and lands on pages the rule was never written for.

`e8e3777fa` styled listings with

```css
:is(.admin-workspace, :where(#brando-main > .content):has(> .content-list-wrapper)) { … }
```

`#brando-main > .content` is the shared layout container, so opening an entry
with 155 rich-text editors went from 8s to 61s, and the socket dropped mid-load
("Mainframe connection was dropped") because the main thread never yielded.
Deleting every `:has()` rule at runtime brought the page back to 4.9s.

- Derive page-level state on the server. The container above is marked by
  `BrandoAdmin.LiveView.Listing` (`:admin_workspace?`, a class in
  `layouts/live.html.heex`).
- Mirror body-level state as a class where it is toggled, as
  `body.sidebar-hidden` in `live/nav.ex` does, instead of `body:has(…)` or
  `#brando-main:has(…)`.
- Style open/closed widgets from the trigger's own `aria-expanded`, which
  `floatingDropdowns.js` maintains, instead of
  `:has(.dropdown-content:not(.hidden))` on their common parent.
- `:has()` scoped inside a row, card or modal is fine: its subject does not
  contain the editor.

Verify with the block editor, not a listing: open the heaviest entry available
and time it. A few seconds is normal; tens of seconds means a selector is being
re-checked against the whole document.

## Admin UI and accessibility

Screens follow the [brando-admin-ui skill](.claude/skills/brando-admin-ui/SKILL.md):
its rules for every change (spacing, controls, keyboard focus, accessible
names, copy, the rendered-result checks) and the references for the components
touched. Review against the skill and the PR's screenshots at 1440px and 390px.
