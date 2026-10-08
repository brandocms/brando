# System check

Most problems on a Brando site come from something out of date or
misconfigured: a migration not run, admin assets from an older Yalc publish,
images made before their settings changed, blocks on old module versions, a
missing sitemap. `mix brando.doctor` checks for all of these and says what to
do about each one.

```
$ mix brando.doctor
Brando 0.55.0-dev · Phoenix 1.8.15 · LiveView 1.2.12

✓ Versions                   Elixir 1.20.3 · OTP 28
✓ Migrations                 up to date
✓ Oban queues                6 queues, 0 stuck
✓ Configuration              URL, mailer and media settings in place
! Admin assets               .yalc brandojs 0.55.0-beta.0
                             expected 0.55.0-dev, run npx yalc update @brandocms/brandojs and pnpm install in assets/backend
! Image configs              2 configs changed since their images were made (14 images)
                             Utilities → Recreate changed images
! Modules                    4 blocks on outdated module versions
                             refresh the modules: mix brando.modules refresh --uid UID --user ID
✗ Sitemap                    not generated
                             Utilities → Generate sitemap
✓ robots.txt                 served from SEO settings
✓ JSON-LD                    identity complete
! Alt text                   38 images without alt (en)
                             Images → Alt text drafts it with AI, for review before saving
✓ Deprecations               none in lib/

5 warnings, 1 error. Details: mix brando.doctor --verbose
```

The checks only read. Nothing is migrated, regenerated or recreated: each
failing check names the fix, and in the admin links to the screen for it. The
task starts the application without its web server and with Oban's queues
stopped, so it can run beside a running server and no job runs while it looks.

## Options and exit status

| Option | Result |
| --- | --- |
| `--verbose` (`-v`) | Lists what each check found: the pending migrations, the stale modules, the files and lines of deprecated calls |
| `--json` | Prints the report as JSON for scripts (see below) |
| `--strict` | Fails on warnings as well as errors |

The task exits with status 1 when a check finds an error, so CI can run it;
with only warnings it exits 0, unless `--strict` is given. A skipped check
never fails.

`--json` prints:

```json
{
  "status": "warning",
  "versions": {"brando": "0.55.0", "elixir": "1.20.3", "otp": "28", "phoenix": "1.8.15", "live_view": "1.2.12"},
  "counts": {"ok": 9, "warning": 3, "error": 0, "skipped": 0},
  "checks": [
    {"id": "migrations", "label": "Migrations", "status": "ok", "summary": "up to date", "fix": null, "items": ["54 run"]}
  ]
}
```

`status` is `ok`, `warning`, `error` or `skipped`; `items` is what
`--verbose` lists. The ids are stable; the labels and summaries are prose.

## What is checked

| Check | Looks at |
| --- | --- |
| Versions | Elixir, OTP, Phoenix and LiveView against the versions this Brando supports |
| Migrations | Public migrations not run (Brando's upgrade migrations included), tenant migrations not run in each environment, pending copies that differ from Brando's templates (as `mix brando.migrations.check`), and upgrade migrations Brando added since they were copied |
| Oban queues | The configured queues (in the admin, the running ones, so a paused queue shows), that the `content_events`, `webhooks` and `search_index` queues are among them, jobs waiting or executing for over an hour, jobs discarded in the last 24 hours |
| Configuration | The endpoint URL, the mailer and its sender, the CDN settings of `Brando.Images` and `Brando.Files` when enabled, and the Assistant's API key when a model is configured |
| Admin assets | The `@brandocms/brandojs` version in `assets/backend/.yalc` (or the checkout it links to) against Brando's |
| Image configs | Images made with an older image config: what Utilities → Recreate changed images recreates |
| Modules | Blocks behind their module's version, per module |
| Sitemap | A sitemap module, and a sitemap generated within two days |
| robots.txt | `/robots.txt` routed to Brando, and no static file in front of it |
| JSON-LD | An identity for each language with a name and a logo, and a site URL |
| Alt text | Images without alt text, per content language |
| Deprecations | Calls to Brando functions marked `@deprecated` in the project's `lib/`, following aliases, imports and pipes |

With tenancy enabled, the content checks (image configs, modules, sitemap,
JSON-LD, alt text) run in every environment of every active site, and their
details name the environment.

## In the admin

**Configuration → Utilities** shows the same checks as the System check
card. They run in the background when the page opens, so the page itself does
not wait; "Run again" repeats them. Each row shows what was found, its status,
the fix, and a link to the screen that fixes it where there is one. The
details under a row are what `--verbose` prints.

A release has no source tree, so in production the checks that read the
project's files (admin assets and deprecations) are skipped and say so.

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
