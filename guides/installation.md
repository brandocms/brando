# Installation

Install Brando into a Phoenix application through Igniter, review the source
diff, then run `mix brando.setup` to build the assets, create the database and
the first account, and seed a homepage. Existing Phoenix routes, templates,
tests, configuration, secrets and dependency choices are preserved.
Conflicting generated files stop the plan, including with `--yes`.

## Prerequisites

- Elixir 1.18 or newer, and PostgreSQL.
- Node.js 24 and pnpm 12, for the admin's and the site's Vite builds.
- A build environment Image and Vix support, for image processing with
  libvips.
- Yalc, while Brando is a development version (`-dev`, such as 0.55.0-dev).
  The admin's JavaScript and CSS, BrandoJS (`@brandocms/brandojs`), is
  published to npm with every Brando release at the same version; a
  development version has no npm release, and the admin takes BrandoJS from
  Brando's source through Yalc (see [Build assets](#build-assets)).
- The Phoenix and Igniter project generators:

  ```sh
  mix archive.install hex phx_new
  mix archive.install hex igniter_new
  ```

  Use `phx_new` 1.8.13 or newer: an older generator selects LiveView
  `~> 1.1.0`, which cannot resolve with Brando's LiveView 1.2 (see
  [Installing into an existing application](#installing-into-an-existing-application)).

[Toolchain pins](#toolchain-pins) lists the exact versions Brando is tested
with.

## Choose install options

The installer writes these choices into the application's source, so decide
them before installing. Without options, a new install has one site (tenancy
mode `none`), placeholder deployment hosts and the CMS public site at `/`.

| Option | Use it for | Details |
| --- | --- | --- |
| `--tenancy-mode single --site-key my-site` or `--tenancy-mode multi` | One named site, or several sites in one installation | [Install options](#install-options) |
| `--domain example.com`, with `--staging-domain` and `--origin` | The production and staging hosts and other trusted origins, for `check_origin` and the Florist environment files | [Deployment hosts](#deployment-hosts) |
| `--no-public-site` | Keeping Phoenix's homepage and installing the admin alone | [Add CMS public pages](#add-cms-public-pages) |
| `--interactive` | Being asked for the choices left out | [Install options](#install-options) |
| `--dry-run` | Previewing the changes without writing them | [Install options](#install-options) |
| `--yes` | Accepting the changes without the prompt; a conflicting file still stops the install | [Install options](#install-options) |

Add them at the end of the install command in the next step.

## Install Brando

> #### Brando 0.55 is not on Hex yet {: .warning}
>
> Until it is, write `brando@github:brandocms/brando` where the commands below
> say `brando`. [Where Brando comes from](#where-brando-comes-from) has the
> other forms.

For a new application, run this from a folder outside any Mix project (from
inside one, `mix igniter.new` fails on Elixir 1.20.4):

```sh
mix igniter.new my_app --with phx.new \
  --with-args="--no-install --no-assets --no-dashboard --no-mailer" \
  --install brando
cd my_app
```

`mix igniter.new` creates the application with `mix phx.new`, adds Igniter,
and runs Brando's installer with the options it does not use itself.
`--with-args` goes to `mix phx.new`, not to Brando. `--no-install` leaves
fetching dependencies to Igniter, which fetches them once Brando is added.
`--no-assets` leaves out esbuild and Tailwind, since Brando installs its own
Vite builds. `--no-dashboard` leaves out Phoenix LiveDashboard, which Brando
does not use. `--no-mailer` leaves out phx.new's Swoosh mailer, because
`mix brando.gen.mail` creates one in [Run setup](#run-setup).

For an existing application, commit it first, so `git diff` shows the install
afterwards. Then, from its root:

```sh
mix igniter.install brando
```

Once Brando is a dependency, `mix brando.install` runs the same installer with
the same options. [Installing into an existing application](#installing-into-an-existing-application)
covers adding the dependency by hand, applications from an older Phoenix
generator and existing `/admin` routes.

### Where Brando comes from

Igniter reads the package's source from its name:

- `brando`: the Hex package.
- `brando@github:brandocms/brando`: GitHub's default branch.
  `brando@github:brandocms/brando@<ref>` takes a tag, branch or commit.
- `brando@path:/absolute/path/to/brando`: a local checkout, for working on
  Brando itself. See [Installing from a Brando checkout](#installing-from-a-brando-checkout).

Brando's installer keeps the dependency as you declared it. A release's Docker
build fetches dependencies from `mix.exs` and cannot see a checkout outside
the project, so deploy a site that takes Brando from Hex or GitHub.

## Review the changes

Igniter prints the changes and asks before writing them. A generated file that
conflicts with one of the application's own stops the plan, and ambiguous
modules or unsupported layouts produce instructions before anything is
written. After the diff come the installer's notices: what it kept, and what
is left to do by hand, such as a changed homepage it did not replace or
placeholder hosts. [What the installer writes](#what-the-installer-writes)
describes the changes.

To read the install as a Git diff in a new application, create it with
`mix phx.new my_app --no-install --no-assets --no-dashboard --no-mailer`
instead, commit it, and install from inside it as an existing application.
Read `git diff`, with `git status` for the new files.

Once the changes are written, review `config/brando.exs` and the application's
database and endpoint settings, which setup uses to create the database. The
default language is English: add other languages to `config/brando.exs`
before setup, which seeds content for each configured language (see
[Languages and translations](i18n.md#configure-content-and-interface-languages)).

<!-- usage-rules:start topic="generators" -->

## Run setup

```sh
mix brando.gen.mail
mix compile --warnings-as-errors
mix brando.setup
```

`brando.gen.mail` reuses the application's Swoosh mailer or creates
`MyApp.Mailer`, and points Brando at it for password resets and form
notifications; [Auxiliary generators](generators.md#auxiliary-generators) has
the details. An application that already had a mailer before installing can
skip it.

`brando.setup` composes the operational steps an installed application needs:
asset builds, `ecto.create`/`ecto.migrate`, a superuser account, and default
content seeds. Each step is skipped when its result already exists, so a rerun
after a failure resumes instead of duplicating. Skip steps with `--no-assets`,
`--no-db`, `--no-account` and `--no-seeds`. Setup prompts for anything it needs;
for an unattended run, supply `--email`, `--name` and `--password` for the
account and `--base-url` and `--description` for the seeded site identity. The
account logs in with the password given here; it is not asked to change it on
first login.
`--source PATH` hands a Brando JavaScript source to asset setup. Setup ends
with `Setup complete.`; [Running the steps separately](#running-the-steps-separately)
describes each step as its own task.

<!-- usage-rules:end -->

With `single` or `multi`, provision the site and environment after the public
migrations and initialize content inside that environment, as
[Sites and environments](tenancy_and_environments.md) describes.

## Sign in

```sh
mix phx.server
```

Open `http://localhost:4000/admin/login` and sign in with the account setup
created. In development, `mix phx.server` also starts the admin's and the
site's Vite dev servers (see [Vite dev servers](#vite-dev-servers)). Group
authorization is set up separately, in [Authorization](authorization.md).

## Open the homepage

Open `http://localhost:4000/`. Setup seeded a published page with URI `index`,
marked as the homepage and rendered with the `index.html` template, built from
the [seeded modules](#seeded-content). Edit it in `/admin/pages`, or replace it
with your own.

Without the seeds, `/` responds 404 until a homepage exists: in
`/admin/pages`, create a page with URI `index`, mark it as the homepage,
choose `index.html` and publish it. Other pages can use `default.html`. An
application installed with `--no-public-site` keeps Phoenix's homepage, and
its Brando pages have no public routes until
[Add CMS public pages](#add-cms-public-pages).

## Install options

```sh
mix brando.install --tenancy-mode single --site-key my-site
mix brando.install --tenancy-mode multi
mix brando.install --interactive
```

A new install defaults to `none` without a prompt. Omitted flags on a rerun keep
the existing mode and site key. Follow
[Sites and environments](tenancy_and_environments.md) when using `single` or
`multi`; changing the source setting does not migrate existing data.

`--interactive --tenancy-mode single` asks only for the missing site key.
`--yes` accepts the diff; it neither enables guided questions nor permits replacing
conflicting files. `--dry-run` previews source without applying it. In a
terminal, `--dry-run` asks how to show the diff, and option 1 prints all of it.
Without a terminal, `--dry-run --yes` prints only the moves and removals of an
install-sized diff. To review the whole change, commit the application before
installing, install, and read `git diff` (with `git status` for the new files).
`--no-tenancy-prompt` turns the questions off, even with `--interactive`.

The installer discovers custom namespaces and allows `--module`, `--web-module`,
`--admin-module`, `--repo`, `--router` and `--endpoint` selection. Ambiguous modules
and unsupported application layouts produce instructions before files are written.
Umbrella roots are not supported.

## Deployment hosts

```sh
mix brando.install --domain example.com
mix brando.install --domain example.com --staging-domain preview.example.net \
  --origin '//*.agency.example' --origin 'https://cms.example.org:8443'
```

`--domain` is the production domain and `--staging-domain` the staging host,
by default `staging.<domain>`. `--origin` adds a trusted origin and can be
repeated: `//host`, `//*.host` or `http(s)://host`, each with an optional port;
a wildcard needs at least two labels after it (`//*.example.com`, not
`//*.com`). A domain is a bare host name, without a scheme, port or path, and
not an IP address. Invalid values stop the install with an issue.

The installer writes:

- With `--domain`, `check_origin` for the endpoint in `config/prod.exs`:
  `//<domain>`, `//www.<domain>` (for a `www.` domain, the name without
  `www.`), `//<staging host>`, each `--origin`, and the
  `PHX_HOST` of any `.envrc.prod` or `.envrc.staging` already there. Staging
  runs the prod release with its own environment file, so its host is listed
  here too. The list replaces Phoenix's default check against the endpoint's
  URL host. It names hosts, not every subdomain: a page on a subdomain
  someone else controls (a forgotten DNS record, a hosted service) could
  otherwise open the admin's socket with an editor's cookies. Add every other
  host that serves LiveView pages or the admin, or Phoenix refuses their
  sockets: each site domain of a multi-site installation
  (`<site>.example.com`), and an admin moved to another host through
  `PHX_HOST` (`cms.example.com`). When every subdomain is yours, trust them
  all with `--origin '//*.example.com'`.
- `.envrc.prod` and `.envrc.staging` for Florist, with `PHX_HOST` set to the
  domain and the staging host, `PHX_SERVER`, a `SECRET_KEY_BASE`, a
  `DATABASE_URL` and a `RELEASE_NODE` default. They use the names a Phoenix
  `config/runtime.exs` reads and are added to `.gitignore` because they hold
  secrets. The diff and `--dry-run` show markers in place of the secrets,
  which the installer fills in after you accept the changes.
- `rel/env.sh.eex`, which makes the release source the environment file
  Florist copies into it (`.envrc.runtime`) and sets long node names.

Prod connects as `<app>`, Florist's default database user, and staging as
its own `<app>_staging`. Set up the Florist targets to match: in the staging target,
`set :user, "${PROJECT_NAME}_staging"` and `set :mix_env, :prod` (see
[Runtime environment](deployment.md#runtime-environment-envrc-flavor) in the deployment
guide), and `FLORIST_DB_PASSWORD_PROD` or `FLORIST_DB_PASSWORD_STAGING` to
the password in the `DATABASE_URL`.

Without `--domain`, no `check_origin` is written, so Phoenix keeps checking
origins against the endpoint's URL host, which `PHX_HOST` sets. The
environment files get placeholder hosts built from the application name
(`my-app.com`, `staging.my-app.com`) and the installer says so. With
`--interactive` and no `--domain`, it asks for the domain, then the staging
host and, when `check_origin` is still to be written, the extra origins
(comma-separated), skipping any an option answers, and asks again after an
invalid answer; an empty domain answer keeps the placeholder. `--yes` and a
plain run never ask.

An existing `check_origin` in `config/config.exs`, `config/prod.exs`,
`config/runtime.exs` or a file they import with a literal path, an existing
`.envrc.prod` or `.envrc.staging`, and an existing `rel/env.sh.eex` are kept:
reruns change none of them, and asking for different hosts adds a notice with
the values to set by hand. A kept `rel/env.sh.eex` that does not source
`.envrc.runtime` gets a notice too.

## Add CMS public pages

A new `mix brando.install` adds the public site; `--no-public-site` leaves it
out. A rerun never adds it. To add it to an application installed without it:

```sh
mix brando.gen.site --replace-phoenix-home
# or, with guided homepage ownership:
mix brando.gen.site --interactive
```

The site is `YourWeb.CMS.PageController`, `PageHTML`, `Layouts`,
`SiteContext`, the [lockdown](#lockdown) page, the site's
[error pages](#error-pages) and a [live preview](live_preview.md) of pages.
Its pipeline resolves the tenant before locale and identity;
published pages use the built frontend assets, Brando metadata and named page
routes. Explicit application routes take precedence over CMS catch-all routing.
phx.new's `priv/static/robots.txt` is removed while it is unchanged, with
`robots.txt` in the web module's `static_paths/0`, so `/robots.txt` is the SEO
settings' text in development as in the release; a changed one is kept, with a
notice.

On a new install, phx.new's `PageController.home` route at `/` is replaced while
`PageController` and its `home.html.heex` are still as `mix phx.new` wrote them.
A homepage the application has changed is kept, and the site is not generated,
with a notice naming the `mix brando.gen.site` commands above; `--interactive`
asks instead. `mix brando.gen.site` removes the route only with
`--replace-phoenix-home` or an affirmative interactive answer. The controller and
templates remain available. Other homepages (a LiveView at `/`, or Phoenix
1.6's `PageController, :index`), catch-alls, routes whose first segment is a
parameter (`scope "/:locale"`, `get "/:slug"`), support-path collisions and a
router without a `:browser` pipeline, which the site's routes pipe through,
need manual integration: a new install leaves the site out and installs the
admin, with a notice naming the routes and the `mix brando.gen.site` command to
run once they are resolved, and `mix brando.gen.site` stops. `--yes` never takes
ownership of a changed homepage. Update
existing homepage request-test expectations when replacing the homepage
behavior; phx.new's own test of it is removed with the route.

The site needs a published homepage page, which setup seeds (see
[Open the homepage](#open-the-homepage)). The scaffold configures
`:page_html_module` to select its own CMS templates while preserving your
Phoenix PageHTML and layouts. Templates under `priv/templates/brando.gen.site`
override packaged defaults. No page or account is created by this source
generator.

### Error pages

The site's 404 and 500 pages render in its layout, `YourWeb.CMS.Layouts`.
phx.new's `YourWeb.ErrorHTML`, which `render_errors` in `config/config.exs`
names, is replaced while it is unchanged from what phx.new generated, and the
404 and 500 templates go in `controllers/error_html/` next to it. Other
statuses still render their status message as plain text. phx.new's
`error_html_test.exs`, which asserts the plain-text pages, is replaced too.
Both are recognized as phx.new 1.7 and 1.8 generate them. A customized
`ErrorHTML` or test is kept, with a notice.

A missing CMS page (with `use_default_errors: true`, the installer's default)
renders the 404 inside the layout the page already has. An error the endpoint
renders, such as a 500, gets the whole layout, built from the request as it was
when the error was raised. Both get the `partials` fragments, the footer
included, when the failing controller had not assigned them yet; if those
cannot be read, the page renders without them and the error is logged. If the layout itself raises, for example while the
database is down and the caches are cold, the page renders without it and the
layout's error is logged.

### Live preview

The generator gives `YourWeb.LivePreview` a `preview_target` for
`Brando.Pages.Page` that renders the edited page as `CMS.PageController`
does: `CMS.PageHTML` and the page's template inside `CMS.Layouts`' root
layout, with the identity, the `main` navigation and the `partials`
fragments assigned. Changing the page's language recomputes those and
re-renders the page's body, header and footer included; `<html lang>` and
`<head>` update when the preview reloads. The module `brando.install`
writes, which has no targets, is replaced; a missing one is created. A
LivePreview that already previews pages is kept, and any other customized one
gets a notice with the target to add. See [Live preview](live_preview.md) for more views and assigns.

### Lockdown

`Brando.Plug.Lockdown` keeps a site under construction private. The generator
puts it first in the `:brando_site` pipeline and adds the page it sends
visitors to: `YourWeb.CMS.LockdownController` and `LockdownHTML` at
`/coming-soon`, routed through `:browser` only, with the route name
`lockdown`. The installer writes `lockdown: false`, so the plug passes everyone
until you turn it on:

```elixir
# config/runtime.exs
config :brando,
  lockdown: true,
  lockdown_password: System.get_env("LOCKDOWN_PASSWORD"),
  # Optional: the site opens by itself after this time.
  lockdown_until: ~U[2027-01-01 00:00:00Z]
```

While locked, signed-in users with access to the admin see the site: with
groups authorization, those whose groups grant backend access; with legacy
roles, every active account, as for `/admin`. So does the admin's live preview, and
shared preview links (`/__p__/…`) stay open to anyone who has one. Visitors who
enter the password on `/coming-soon`, or open any page with `?key=<password>`,
see the site for the rest of their session. Without a password, or with an
empty one, only users with admin access get in. `/coming-soon` resolves the
site itself, so in multi-site mode it renders with that site's assets. Only
routes through `:brando_site` are locked: add `plug Brando.Plug.Lockdown` to
any other pipeline that serves public pages. The static site generator fetches
pages over HTTP without a session, so turn lockdown off before building a
static site.

An application that already routes `/coming-soon` keeps its own page: the
generator adds neither the page nor the plug, and says so. Rerunning
`mix brando.gen.site` on a site generated before the lockdown page adds both,
as long as what the generator owns (`CMS.PageController`, `PageHTML`,
`Layouts`, `SiteContext` and the CMS routes) is still as it generated it. A
customized one is reported as an issue and the rerun writes nothing; add the
lockdown page and plug by hand then, as above.

## Installing into an existing application

`mix igniter.install brando` adds the dependency and runs the installer. To
add the dependency by hand instead, put these in `mix.exs`, with Brando's
source as in [Where Brando comes from](#where-brando-comes-from):

```elixir
{:brando, github: "brandocms/brando"},
{:igniter, "~> 0.8.0", only: [:dev, :test]}
```

Then run:

```sh
mix deps.get
mix deps.compile
mix brando.install
```

Brando's optional modules automatically recompile if Igniter is added to an
already compiled application.

An application generated by an older `phx.new` reports this when fetching:

    Because "your app" depends on "brando" which depends on
    "phoenix_live_view 1.2.13", "phoenix_live_view 1.2.13" is required.
    So, because "your app" depends on "phoenix_live_view ~> 1.1.0",
    version solving failed.

No installer can repair this: resolution fails while fetching, before Brando is
compiled and before any of its tasks can run. Widen the constraints your
application declares, then fetch again:

```elixir
{:phoenix, "~> 1.8.13"},
{:phoenix_live_view, "~> 1.2.0"},
{:ecto_sql, "~> 3.14"},
```

A lock built for the previous constraints also blocks resolution; run
`mix deps.unlock --all` before `mix deps.get` when the reported conflict names
`the lock`.

Existing `/admin` routes, dynamic route paths and conflicting authentication
migrations require explicit integration. Brando owns the shared public `users`
and `users_tokens` tables; the installer does not rename an existing account
schema. Preflight examines source declarations, without inspecting a live database.

## What the installer writes

The generated changes configure Brando, extend supervision/endpoint/router,
create the admin support modules and Vite projects, and add missing migrations.
A new install adds the [CMS public pages](#add-cms-public-pages) unless given
`--no-public-site`; a homepage the application has made its own is kept, and
a router the site can't be added to keeps its routes and gets the admin alone.

For a [Florist deploy](deployment.md), the installer writes:

- the production endpoint's `check_origin`, the Florist environment files and
  the release script that sources them (see [Deployment hosts](#deployment-hosts));
- Brando's Dockerfile and `.dockerignore` when there are none (see
  [The Docker build](deployment.md#the-docker-build));
- `MyApp.ReleaseTasks` and a release that writes the tarball Florist deploys
  (see [Release helpers](deployment.md#release-helpers));
- relative `media_path` and `log_dir` in `config/prod.exs` (see
  [Media and log paths](deployment.md#media-and-log-paths));
- the `.gitignore` lines a Brando application needs (see
  [Ignored files](deployment.md#ignored-files)).

Those sections also say what an existing file keeps. The release does not copy
`priv/static`, so phx.new's `favicon.ico` there is removed and its
`images/logo.svg` moves to `assets/frontend/public/images`; with the public
site, its `robots.txt` is removed too, so Brando answers `/robots.txt`, and
without it `robots.txt` moves to `assets/frontend/public`. Florist's own
configuration, like sample content, remains separate.

The installer also adds `:brando` to `import_deps` in `.formatter.exs`, so
`mix format` keeps Blueprint DSL calls without parentheses, and moves the
application's version to a `VERSION` file that `mix.exs` reads
(`@version "VERSION" |> File.read!() |> String.trim()`), where Florist looks
for it. A literal version, inline or in `@version`, moves; an existing
`VERSION` is kept, and `mix.exs` reads it when the two agree, with a notice when
they don't. A `mix.exs` that computes its version another way is left as it is.

### Toolchain pins

Brando is tested with phx_new 1.8.13, igniter_new 0.5.28, Phoenix 1.8.16,
LiveView 1.2.13, Elixir 1.20.4, OTP 28.5.0.8 and PostgreSQL 16.1.

A new install pins that toolchain in a `.tool-versions`, which asdf and
mise both read: Erlang 28.5.0.8, Elixir 1.20.4, Node.js 24 and pnpm 12.15.0 (the
Node.js major and pnpm the Dockerfile's asset stages use). With asdf or mise,
`mix` and `pnpm` in the application then run those versions whatever the
machine's defaults are; run `mise install` or `asdf install` for the Node.js
and pnpm it names. The file is written only when the install itself runs the
Erlang and Elixir that asdf or mise installed under those names (an Elixir
from Homebrew, or one asdf built from source as `1.20.4`, doesn't count),
since the install's follow-up `mix` tasks run in the application and a shim
stops at a pinned version it has not installed under that name, and only
when neither the application nor a folder above it (below your home folder)
pins a toolchain already: a `.tool-versions`, a mise configuration
(`mise.toml`, `.mise.toml`, `mise.local.toml`, `.mise/config.toml`,
`.config/mise.toml`, `.config/mise/config.toml`), `.nvmrc` or `.node-version`.
Otherwise a notice shows the file's contents to add yourself.

## Files for coding agents

<!-- usage-rules:start topic="generators" -->

`mix brando.install` gives coding agents Brando's rules and skills:

* `AGENTS.md` gets a `brando` section linking `deps/brando/usage-rules.md`,
  inside the `<!-- usage-rules-start -->` block Phoenix writes, or in a new
  file. `mix usage_rules.sync` from the `usage_rules` package can take that
  section over; it loads the topic files in `deps/brando/usage-rules/` as
  `brando:<topic>`.
* `.claude/skills/` gets Brando's skills for building a site: Blueprints,
  blocks and modules, live preview, media fields and deploys.

A versioned `mix brando.upgrade` adds the ones that are missing. Neither task
replaces a skill file or a `brando` section that already exists, so edit them
freely.

<!-- usage-rules:end -->

## Running the steps separately

These are the equivalent steps as individual tasks, to control each one.
`mix brando.setup` creates the account itself, in place of `brando.gen.admin`,
and does not run `brando.gen.languages`:

```sh
mix brando.assets.setup
mix ecto.create
mix ecto.migrate
mix brando.gen.languages
mix brando.gen.admin
mix brando.gen.seeds
mix phx.server
```

[Build assets](#build-assets) describes `brando.assets.setup`. Review the
migrations and point the application at its intended development database
before `ecto.create`.

`brando.gen.languages`, which setup does not run, creates identity/SEO
defaults and prints language configuration; choose English (`en`) for the
initial defaults. The admin task prompts for account details. Open
`/admin/login` and sign in with that password; like `brando.setup`'s account,
it is not asked to change it on first login. Account creation and database
operations are separate from the Igniter source plan.

### Seeded content

`brando.gen.seeds` creates the content a new site needs before its first request
succeeds: identity and SEO per configured language when missing, seven modules,
a published `index` page built from six of them, a `main` navigation menu and a
`partials/footer` fragment. It owns an account with `--user ID`, defaulting to
the oldest active superuser. `--base-url URL` and `--description TEXT` fill in
a newly created SEO record's base URL and fallback meta description; without a
base URL, canonical links, sharing previews and the sitemap cannot build full
addresses. Existing content of each kind is left untouched, so a rerun adds
only what is missing; the content is a starting point for editing in the
admin, not a migration path. Without it, `/` has no published page and
responds 404. Your application's own `priv/repo/seeds.exs` is preserved and
never run for you.

The seeded modules (Hero, Steps, Cards, Tips, Toolbox, Closing and Footer)
double as worked examples of the ref conventions: mono micro-labels and links
live in the module markup, while every piece of copy is a ref an editor can
change. The Toolbox module keeps its task table in markup on purpose, since it
documents the framework rather than the site. Delete the page and the modules
once your own design takes over; nothing else depends on them.

Two conventions the seeds rely on, worth knowing when you write your own:

- A header block's text is inserted raw, so the hero headline carries a
  `<span class="soft">` around its second line to step it back. Newlines in a
  header ref become `<br>`.
- Ref content is parsed for Liquid on its way into the module markup. Copy that
  shows a `{% ref %}` tag, like the Quick start step that explains them, has
  to escape its braces as `&#123;` / `&#125;`, or the renderer consumes it as a
  tag of its own.

## Build assets

```sh
mix brando.assets.setup
```

Asset setup runs `pnpm install` and `pnpm build` in both consumer asset
directories. Where the admin takes BrandoJS from is set in
`assets/backend/package.json`, and the task keeps it:

* **npm**: `"@brandocms/brandojs": "0.55.0"`, Brando's own version. A released
  Brando generates this; `pnpm install` fetches it.
* **A Yalc copy**: `"file:.yalc/@brandocms/brandojs"`, a copy of a Brando
  checkout. A `-dev` Brando generates this, and it is how you work on Brando
  itself. The task publishes the selected Brando dependency's `assets/` to a
  consumer-local Yalc store under `_build` and adds it to the admin. An Elixir
  package from Hex has no JavaScript sources: pass
  `--source /path/to/matching/brando/assets`, or `--npm`.
* **A linked checkout**: `"link:../../brando/assets"` (or a `file:` path
  outside `.yalc`). The task checks that the path holds `@brandocms/brandojs`
  and leaves it to pnpm.

A `package.json` without BrandoJS gets what a generated admin has. To switch,
run `mix brando.assets.setup --local` (or `--source PATH`) to take BrandoJS
from a Yalc copy of a checkout, and `mix brando.assets.setup --npm` to go back
to the npm release of Brando's version. `--npm` also removes the Yalc copy.
The task checks for Node.js, pnpm and, for a Yalc copy, Yalc before it changes
anything. Use `--no-build` to install only, and `--backend-only` to install
and build the admin alone.

`pnpm build` writes `admin_manifest.json`, `manifest.json` and assets to the
consumer's `priv/static`. Production uses them, and so does development with
`config :my_app, hmr: false`. After framework JS changes, rerun asset setup.

### Admin and site CSS

The admin (`assets/backend`) and the site (`assets/frontend`) compile their CSS
with the native EuropaCSS compiler, through the Vite plugin
`@brandocms/vite-plugin-europacss`. pnpm installs the compiler,
`@brandocms/europacss-cli`, from npm, with an executable for the machine it
runs on from the lockfile's optional dependencies (macOS, Windows, and Linux
with glibc or musl, x64 and arm64), so no Rust toolchain is needed. Install on
the machine that builds, as the generated Dockerfile does, rather than copying
`node_modules` between platforms, and never with `--no-optional`. The CLI is
`pnpm exec europa` in either directory.

Each directory has a `europa.json5`. The admin's extends Brando's preset
(`./node_modules/@brandocms/brandojs/europa.json5`) and lists only what the
application changes, such as theme colours; objects merge key by key with the
preset's, and arrays and plain values replace them. The site's holds the
site's own tokens: breakpoints, spacing, typography and colours.

The admin's styles are in the cascade layers `reset, vendor, brando, app`, in
that order. Put the application's admin rules in `@layer app { … }`, as the
generated `assets/backend/css/app.css` does: they then outrank Brando's
whatever their selectors, though an `!important` in Brando's layer still
outranks one in `app`.

### Vite dev servers

In development the installer sets `config :my_app, hmr: true` in
`config/dev.exs`: the admin loads its assets from a Vite dev server for
`assets/backend` on port 3333, and the site from one for `assets/frontend` on
port 3000. The installer adds two endpoint watchers to `config/dev.exs`, so
`mix phx.server` starts both servers and stops them when it stops:

```elixir
config :my_app, MyAppWeb.Endpoint,
  watchers: [
    vite_admin: {Brando.Vite, :watch, [Path.expand("../assets/backend", __DIR__)]},
    vite_site: {Brando.Vite, :watch, [Path.expand("../assets/frontend", __DIR__)]}
  ]
```

`Brando.Vite.watch/1` runs Vite from the directory's `node_modules`, so run
`mix brando.assets.setup` (or `pnpm install` in both directories) first. Vite's
output goes to the `mix phx.server` log. Vite stops when Phoenix stops, also
when you leave with Ctrl-C.

The installer fills the watchers only when the endpoint has none (phx.new's
`watchers: []`, or no `watchers` key) and `config/dev.exs` does not set
`hmr: false`. Watchers of the application's own are
kept, and the installer prints the two entries to add by hand. Applications
installed by earlier Brando versions have no Vite watchers: add the two entries
above to the endpoint's `watchers` in `config/dev.exs`, or keep running `pnpm dev` in
`assets/backend` and `assets/frontend`.

Both generated `vite.config.js` files set `server.strictPort`, so Vite does
not quietly move to a port Phoenix does not know. When Vite cannot start,
because another process such as another site's Vite server holds its port,
because `node_modules` is missing, or because `node` is not on the `PATH`,
the log has Vite's own output and one error from `Brando.Vite` saying what to
do. Phoenix carries on without that dev server and does not retry it; restart
`mix phx.server` once it is fixed. Until then the admin, or the site, does not
load from that port, which may hold the other site's Vite: it uses its last
build in `priv/static` (from `mix brando.assets.setup` or `pnpm build`), which
does not follow your edits, and shows a notice saying that Vite did not start
and why. A `pnpm build` while the server runs shows on the next page load. The
same happens when Vite exits with an error after it started. For a taken port
the notice names the variable to change, `BRANDO_VITE_ADMIN_PORT` or
`BRANDO_VITE_FRONTEND_PORT` (below). When you run `pnpm dev` yourself, without
the watchers, the page always loads from the port.
When a dev server's scripts fail to load, because it is not running or cannot
compile a module, the admin or the site shows a notice naming the address it
tried. Copy `strictPort` into the Vite configs of existing applications.

To run two Brando sites at once, give one of them other ports. Export them in
that project's shell environment, for example its `.envrc`, so that Phoenix,
which renders the script tags, and the Vite servers its watchers start read the
same values:

```sh
export BRANDO_VITE_ADMIN_PORT=3334
export BRANDO_VITE_FRONTEND_PORT=3001
```

`BRANDO_VITE_ADMIN_HOST` and `BRANDO_VITE_FRONTEND_HOST` set the hosts
(default `localhost`). To use the built assets instead, run `pnpm build` in
both directories, set `config :my_app, hmr: false` in `config/dev.exs` and
remove the two watchers; running `mix brando.install` again leaves them out.

## Installing from a Brando checkout

To work on Brando itself, install it from a local checkout:

```sh
mix igniter.install brando@path:/absolute/path/to/brando
```

or declare `{:brando, path: "/absolute/path/to/brando"}` in `mix.exs` and run
`mix brando.install`. Deploy from GitHub or Hex: the release's Docker build
cannot see the checkout.

While Brando is a path dependency, a running site doesn't pick up changes in
the checkout: the site builds its own copy of the dependency, `mix compile` in
the Brando repository doesn't touch it, and Phoenix's code reloader only
recompiles the site's own code. Adding `:brando` to the endpoint's
`reloadable_apps` does make the reloader compile Brando's edits, but it checks
Brando's whole source tree (about 1,600 files) on every request: 40 to 70 ms
on Elixir 1.18, and on 1.19 and later every request also rebuilds the site's
consolidated protocols, 0.6 to 3 seconds. Leave `:brando`, and every other
dependency, out of `reloadable_apps`. After changing Brando:

```sh
mix deps.compile brando   # in the site
# then restart the server
```

Admin JavaScript and CSS come from the checkout through Yalc while the site's
admin takes BrandoJS from a local source (`mix brando.assets.setup --local`;
see [Build assets](#build-assets)): run `npx yalc publish` in Brando's
`assets` after a change. The admin's Vite config includes BrandoJS's
`yalcAutoUpdate` plugin, so its running Vite dev server pulls each publish,
and with HMR on there is nothing else to do. Without it, rerun
`mix brando.assets.setup --backend-only` to rebuild.

The rules `mix brando.install` gives coding agents link to
`deps/brando/guides/`. With a `path:` dependency those links don't resolve;
the guides are in the Brando checkout.
