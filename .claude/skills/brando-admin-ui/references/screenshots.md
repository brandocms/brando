## Screenshot tools

Use these instead of writing a Playwright script, restarting servers by hand or
inserting rows with SQL. The in-app preview browser cannot reach localhost.

```sh
cd e2e
export BRANDO_E2E_INSTANCE=my_task           # own database and port
scripts/server.sh start                      # migrates, seeds if empty, waits for the port
node scripts/shoot.mjs --label before --locales en,no \
  --shot dashboard=/admin --shot utilities=/admin/config/utils
node scripts/shoot.mjs --label after --spec shots.json
scripts/server.sh stop                       # stops only the server it started
```

- `e2e/scripts/server.sh start|stop|restart|status|log` runs `mix phx.server`
  for the instance in the background, with a pidfile under
  `e2e/tmp/instances/<instance>/`. `start --reset` reseeds and `--assets`
  rebuilds the admin assets first; the server has no code reload, so `restart`
  after Elixir, JS or CSS changes. Never stop servers with `pkill -f`: other
  worktrees run theirs on the same machine.
- `e2e/scripts/shoot.mjs` logs in as the E2E admin, waits for LiveView to
  connect and settle, and writes `<name>-<locale>-<width>.png` to
  `<out>/<label>/` at 1440 and 390 px by default, with font hinting off. A JSON
  or JS spec adds actions (click, fill, hover, wait for, scroll, press Escape),
  element or clip shots and setup data. `--help` prints the spec format.
- Element and full-page shots come out clean of overlays by default, so no
  `evaluate` steps are needed for them: sticky elements (the entry toolbar)
  go back into the flow, element shots also hide fixed elements (headers,
  floating buttons), and full-page shots start from the top of the page and
  keep the sidebar. Modals, drawers, dialogs and popovers stay as they
  are. Add selectors to leave alone with `"keep"`; `"unstick": false` on
  a shot (or `--no-unstick`) takes it exactly as rendered. Viewport and clip
  shots are never changed.
- `scripts/pr-shots <shots-dir> <name> --worktree <pr-screenshots checkout>`
  copies `before/` and `after/` to the `pr-screenshots` branch layout and prints
  the before/after table for the PR body; `--push` commits and pushes.

**Data for a shot.** Every locale and width runs in its own SQL sandbox, like an
E2E test, so nothing persists and the seeded database stays clean. Put the
rows a screen needs in the spec's `setup`, never in SQL:

- `{"factory": "<Schema>", "attributes": {…}, "as": "x"}` creates an entry
  through the Blueprint factory (`/__e2e/db/factory`); use `{x.id}` in paths.
- `{"fixture": "<name>"}` runs a named scenario from
  `e2e/test/support/e2e_fixture_controller.ex`, such as
  `assistant-applied-copy`, `mcp-proposals`, `content-transfer`,
  `revision-panel` or `markdown-source`. Add a scenario there when a state
  needs more than a few factory rows, so specs and shots share it.
- `{"post": "/e2e/admin-workspace-fixtures"}` calls the other E2E endpoints in
  `e2e/lib/e2e_project_web/router.ex`.

The seeds (`e2e/priv/repo/e2e_seeds.exs`) already provide the Index page
(`/admin/pages/update/1`), the example modules and a few projects.

`e2e/playwright/scripts/admin-ui-references.mjs` retakes the committed reference
images linked from these docs: with the server running, `cd e2e && source
.envrc && node playwright/scripts/admin-ui-references.mjs`; `--list` prints the
catalogue and `--only <name>` retakes one image. Take the committed references
on a Mac: Linux renders the admin's text differently.
