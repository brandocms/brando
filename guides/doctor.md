# System check

<!-- llms-description: `mix brando.doctor` finds what is misconfigured or out of date and says how to fix it; add checks of your own. -->

Most problems on a Brando site come from something out of date or
misconfigured: a migration not run, admin assets from an older BrandoJS,
images made before their settings changed, blocks on old module versions, a
missing sitemap. `mix brando.doctor` checks for all of these and says what to
do about each one.

```
$ mix brando.doctor
Brando 0.55.0-dev (git 12c2289, branch main) · Phoenix 1.8.16 · LiveView 1.2.13

✓ Versions                   Brando 0.55.0-dev (git 12c2289, branch main) · Elixir 1.20.3 · OTP 28
✓ Node.js                    v22.15.0
✓ Migrations                 up to date
✓ Oban queues                6 queues, 0 stuck
✓ Configuration              URL, mailer and media settings in place
✓ Admin routes               every Blueprint's admin route helpers exist
! Admin assets               .yalc brandojs 0.55.0-beta.0
                             expected 0.55.0-dev, run npx yalc update @brandocms/brandojs and pnpm install in assets/backend
! Image configs              2 configs changed since their images were made (14 images)
                             Utilities → Recreate changed images
! Modules                    4 blocks on outdated module versions
                             they hold refs or vars their module no longer defines: resolve them under Block modules, or with mix brando.modules resolve --uid UID --user ID
✗ Sitemap                    not generated
                             Utilities → Generate sitemap
✓ robots.txt                 served from SEO settings
✓ JSON-LD                    identity complete
! Alt text                   38 images without alt (en)
                             Images → Alt text drafts it with AI, for review before saving
✓ Deprecations               none in lib/
✓ Test database              my_app_test, not the development database

5 warnings, 1 error. Details: mix brando.doctor --verbose
```

The checks only read. Nothing is migrated, regenerated or recreated: each
failing check names the fix, and in the admin links to the screen for it. The
task starts the application without its web server and with Oban's queues
stopped, so it can run beside a running server and no job runs while it looks.

<!-- usage-rules:start topic="deployment" -->

## Options and exit status

| Option | Result |
| --- | --- |
| `--verbose` (`-v`) | Lists what each check found: the pending migrations, the stale modules, the files and lines of deprecated calls |
| `--json` | Prints the report as JSON for scripts (see below) |
| `--strict` | Fails on warnings as well as errors |
| `--offline` | Does not ask Brando's git remote for its latest commit (see below) |

The task exits with status 1 when a check finds an error, so CI can run it;
with only warnings it exits 0, unless `--strict` is given. A skipped check
never fails.

<!-- usage-rules:end -->

## Which Brando is running

The header and the Versions check name Brando's version and where it came
from, so you can tell whether a fix is live:

| Source | Shown as |
| --- | --- |
| A git dependency | `git 12c2289, branch main`: the locked commit, and its branch or tag. `--verbose` lists the full commit and the repository |
| A Hex package | `Hex` |
| A path dependency | `path ../brando`, relative to the application |
| Brando's own repository | `this checkout` |

The source is recorded when Brando is compiled, from what Mix gives the
dependency, so it is the code that runs, also in a release where there is no
`mix.lock`. Mix recompiles a git or Hex dependency from scratch when its lock
entry changes.

For a git dependency that follows a branch, `mix brando.doctor` also runs
`git ls-remote` against the repository. When the branch is now at another
commit, the Versions line says so (`main is now at a1b2c3d`) and `--verbose`
suggests `mix deps.update brando`. This is a note, not a warning. The lookup
gives up silently after three seconds, without network or for a repository
that asks for credentials; `--offline` skips it. A tag or a pinned `ref:` is
not looked up, and the admin never makes the call.

`--json` prints:

```json
{
  "status": "warning",
  "versions": {
    "brando": "0.55.0",
    "brando_source": {"type": "git", "url": "https://github.com/brandocms/brando.git", "commit": "12c2289e98fa058a8168720b802c13b42a2c21b4", "branch": "main", "tag": null, "ref": null},
    "elixir": "1.20.3", "otp": "28", "phoenix": "1.8.16", "live_view": "1.2.13"
  },
  "counts": {"ok": 9, "warning": 3, "error": 0, "skipped": 0},
  "checks": [
    {"id": "migrations", "label": "Migrations", "status": "ok", "summary": "up to date", "fix": null, "items": ["54 run"]}
  ]
}
```

`status` is `ok`, `warning`, `error` or `skipped`; `items` is what
`--verbose` lists. `brando_source.type` is `git`, `hex` (with `version`),
`path` (with `path`), `checkout` or `unknown`. The ids are stable; the labels
and summaries are prose.

## What is checked

| Check | Looks at |
| --- | --- |
| Versions | Brando's version and source, and Elixir, OTP, Phoenix and LiveView against the versions this Brando supports |
| Node.js | The `node` on the PATH, which builds the admin and frontend assets: an odd release, or one older than Brando is tested on (`Brando.Toolchain`), is a warning. Skipped in a release |
| Migrations | Public migrations not run (Brando's upgrade migrations included), tenant migrations not run in each environment, pending copies that differ from Brando's templates (as `mix brando.migrations.check`), and upgrade migrations Brando added since they were copied |
| Oban queues | The configured queues (in the admin, the running ones, so a paused queue shows), that the `content_events`, `webhooks` and `search_index` queues are among them, jobs waiting or executing for over an hour, jobs discarded in the last 24 hours |
| Configuration | The endpoint URL, the mailer and its sender, the CDN settings of `Brando.Images` and `Brando.Files` when enabled, and the Assistant's API key when a model is configured |
| Admin routes | For each of the application's Blueprints with an admin listing or form route, the route helper its rows and links call, `admin_<singular>_form_path` with `:update` (`admin_<scope>_<singular>_form_path` with `router_scope:`). A site still routing 0.53's `<Name>CreateLive`/`<Name>UpdateLive` fails here; `mix brando.migrate54` converts generated ones |
| Admin assets | The `@brandocms/brandojs` version the admin installs against Brando's: from `node_modules` for an npm version, from `assets/backend/.yalc` (or the checkout it links to) for a local source. An npm install at another version suggests `mix brando.assets.setup --npm --backend-only`, or `--local --backend-only` for a development Brando, which has no npm release |
| Admin CSS compiler | The native EuropaCSS packages in `assets/backend` (`Brando.EuropaCSS`): `@brandocms/vite-plugin-europacss` and `@brandocms/europacss-cli` declared from npm at the versions Brando's backend template pins, and installed at them. The legacy `@brandocms/europacss`, a Yalc copy or path, or another version is a warning with `mix brando.gen.backend --upgrade` as the fix; an install behind `package.json` asks for `pnpm install`. Skipped in a release |
| Image configs | Images made with an older image config: what Utilities → Recreate changed images recreates. Images made before Brando recorded configs are split, as a dry run of `mix brando.images.adopt`, into those whose files already match and those that differ, counted by how they differ (formats, sizes, missing files, dimensions). With no image files in the media folder at all, it says so and asks for the media instead of a recreate |
| Modules | Blocks behind their module's version, per module |
| Module entry paths | Liquid module code that reads a multi module's entries as Villain stored them, `{{ link.data.vars.url }}`, which renders nothing since the blocks conversion; `brando_219` rewrites it to `{{ link.vars.url }}`. Datasource modules are left out: their `entries` are records |
| Sitemap | A sitemap module, and a sitemap generated within two days |
| robots.txt | `/robots.txt` routed to Brando, and no static file in front of it: a `priv/static/robots.txt` counts only when the endpoint's `Plug.Static` serves it, by its `only:` (a literal list, or `static_paths/0` on Phoenix 1.7 and later) or for want of one, and the fix names that setting |
| JSON-LD | An identity for each language with a name and a logo, and a site URL |
| Alt text | Images without alt text, per content language |
| Media paths | Image and file rows, deleted ones included, whose stored path leaves the media folder: an image's path or one of its sizes, or a file's name, that is absolute, starts with `~/` or climbs out with `..`. Brando refuses such a path when it is saved and in every file operation, but a row stored before that check keeps it, and the crop editor may have written an upload to the place it names. The details list each row and its path: remove what was written there, then delete the row or have a superuser correct its path |
| Deprecations | Calls to Brando functions marked `@deprecated` in the project's `lib/`, following aliases, imports and pipes |
| Test database | In development, the Repo's database for `:test` (read from `config/config.exs` and `config/runtime.exs` in the current shell) against the one in use: a `runtime.exs` that reads the Repo `url:` from the environment in every environment makes `mix test` use, and migrate, the development database |

With tenancy enabled, the content checks (image configs, modules, module
entry paths, sitemap, JSON-LD, alt text, media paths) run in every environment of every
active site, and their details name the environment.

## In the admin

**Configuration → Utilities** shows the same checks as the System check
card. They run in the background when the page opens, so the page itself does
not wait; "Run again" repeats them. Each row shows what was found, its status,
the fix, and a link to the screen that fixes it where there is one. The
details under a row are what `--verbose` prints. The Versions row starts with
the running Brando and its source.

A release has no source tree, so in production the checks that read the
project's files (admin assets and deprecations) are skipped and say so.

<!-- usage-rules:start topic="deployment" -->

## Add a check

A check is a module implementing `Brando.Doctor.Check`. It reads, and returns
a `Brando.Doctor.Result`:

```elixir
defmodule MyApp.Doctor.SearchIndex do
  use Brando.Doctor.Check

  @impl true
  def id, do: "search_index"

  @impl true
  def label, do: "Search index"

  @impl true
  def run(_context) do
    case MyApp.Search.unindexed() do
      [] ->
        ok("up to date")

      entries ->
        warning("#{length(entries)} entries not indexed",
          fix: "run mix my_app.reindex",
          items: Enum.map(entries, & &1.title)
        )
    end
  end
end
```

Register it, and Brando's own checks run first:

```elixir
config :brando, Brando.Doctor,
  checks: [MyApp.Doctor.SearchIndex],
  # Leave out a check that does not apply
  skip: [Brando.Doctor.Checks.AltText]
```

- `ok/2`, `warning/2`, `error/2` and `skipped/2` take `:fix` (what to do),
  `:items` (what `--verbose` lists) and `:link`, an admin LiveView or path and
  a label: `link: {MyAppAdmin.SearchLive, "Open search"}`.
- Return `true` from `needs_source?/0` when the check reads the project's
  files, so it is skipped in a release.
- `run/1` gets a `Brando.Doctor.Context`. `Brando.Doctor.Context.each_environment/2` runs a
  function in each tenant environment the check should cover.
- `label/0` and the result text appear in the admin card too. Translate them
  with the application's Gettext backend if the admin is used in more than one
  language; the doctor runs checks in the admin user's locale there, and in
  English in the terminal.
- A check that raises, or takes over a minute, is reported as an error; the
  others still run.

<!-- usage-rules:end -->
