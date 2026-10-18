# Migrating from Brando 0.53 or 0.54

Brando 0.55 changes application source, Brando-owned database tables, Blueprint
storage contracts, persisted block data, identifiers, and Gettext structure.
Treat the upgrade as a reviewed deployment, not as one automatic command.
Applications on the `0.54` branch follow the same order; the source step below
says which task they skip.

## Which guide

Find the newest Brando migration the application has copied:

```shell
ls priv/repo/migrations | grep -o 'brando_[0-9]*' | sort -t_ -k2 -n | tail -1
```

| Newest migration | The application is on | Follow |
| --- | --- | --- |
| `brando_55` or lower | 0.51 (`legacy`): Vue admin, no Blueprints | [Migrating from 0.51](migrating_from_051.md) |
| `brando_56` to `brando_102` | 0.52 or 0.53: Blueprints, content still Villain JSON in `data` columns, no `*_blocks` tables | This guide, both source tasks |
| `brando_103` to `brando_130` | 0.54: blocks | This guide, without `mix brando.migrate54` |
| `brando_131` or higher | a 0.55 development build | Rerun `mix brando.migrate55` (see [Run the source tasks](#run-the-source-tasks)), then this guide from section 3 |

The `@version` in `deps/brando/mix.exs` is a weaker signal: a development
checkout reported `0.53.0-dev` from mid-2022 to the 0.53.0 release in 2024.

- On 0.52 (`brando_87` or lower), first make the changes in the 0.53.0
  section of `CHANGELOG.md`. No task covers the 0.52 to 0.53 source changes.
- With Villain content, `mix brando.migrate` converts it to blocks
  (`brando_103` onward), and the Blueprint snapshots predate that conversion.
  Read [Legacy snapshots](#legacy-snapshots) before generating Blueprint
  migrations.

## 1. Establish a recovery point

Before updating the dependency:

1. Commit the complete application worktree, including every existing Ecto
   migration and Blueprint snapshot.
2. Back up the production database and Gettext catalogs.
3. Rehearse the upgrade on a copy of production data or an equivalent staging
   database.
4. Record which database-backed Blueprints already have generated snapshots
   under `priv/blueprints/snapshots`.
5. Start the old site and leave it running through the upgrade (below).

Do not delete a snapshot to repair history. A missing snapshot can make an
existing table look new to the generator.

### Keep the old site running

The final gate compares the public pages before and after the upgrade with
`mix brando.upgrade.snapshot` (see [Final deployment gate](#6-final-deployment-gate)),
which fetches the pages from both sites while they run. Start the old site now,
before changing anything:

1. Restore the production dump twice: one database to upgrade, and an
   untouched copy for the old site.
2. Run the old site from a checkout of the pre-upgrade commit, such as a Git
   worktree (`git worktree add ../myapp-before HEAD`), against the untouched
   copy and on a port of its own (4000, say).
3. Check that it compiles and serves, and leave it running.

A new worktree compiles every dependency from scratch, and an old lock may not
build on a current OTP: one 0.53 site's lock held a `mochiweb` that does not
compile on OTP 27, where `maybe` is a reserved word, and built on OTP 26 with
Elixir 1.17. Give the worktree the toolchain its lock builds on, in a
`.mise.toml` of its own. Finding that out now is easier than at the end, when
the application's own `_build` holds the upgrade.

## 2. Update source with Igniter

### Dependencies and toolchain

The source tasks run once the new Brando resolves, so fix `mix.exs` by hand
first.

Point the Brando dependency at a checkout, or at a commit on GitHub:

```elixir
# mix.exs
{:brando, path: "/absolute/path/to/brando"},
# or
{:brando, github: "brandocms/brando", ref: "<commit sha>"},
```

Use `path:` to rehearse locally only. The release's Docker build fetches
dependencies from `mix.exs` and cannot see a checkout outside the project, so
deploy from `github:`. [Installation and generators](generators.md) describes
working against a `path:` checkout, including `mix deps.compile brando` after
changing it.

The admin's JavaScript, BrandoJS, comes from npm at Brando's version once
Brando is released, and from the same Brando source through Yalc for a
development version or while working on Brando. With a Yalc copy,
`mix brando.assets.setup --backend-only` (see
[Admin assets](#admin-assets)) publishes the dependency's `assets` directory to
a store under `_build` and updates `assets/backend/.yalc`. By hand, the steps
are `npx yalc publish` in Brando's `assets`, then
`npx yalc update @brandocms/brandojs` and `pnpm install` in the application's
`assets/backend`, and a restart of its Vite. Do not use `yalc push`: it
rewrites every project registered with Yalc on the machine. Keep the Elixir and
JavaScript sides on the same Brando revision.

Brando requires exact or recent versions of packages a 2023 `mix.exs` also
declares, and `mix deps.get` reports the conflicts one at a time. Brando's
script makes all of those changes at once; run it from the application's
root:

```shell
elixir /path/to/brando/scripts/prepare_055_deps.exs --brando-path /path/to/brando
```

Give it `--brando-ref <sha>` instead of `--brando-path` to point Brando at a
commit on GitHub; `--dry-run` writes nothing. It needs no resolved
dependencies: it edits `mix.exs` as text and prints each change. It applies
the constraints below to the packages the application declares, bumps
`ex_chimp` to 0.2, drops `only: :test` from `floki`, removes `timex` once `lib/`
no longer calls it (and lists the calls otherwise), adds Igniter, sets
`elixir: "~> 1.18"` and `listeners: [Phoenix.CodeReloader]` in `project/0`,
and points the Brando dependency at the checkout or commit. It then lists what
`mix.lock` still has on HTTPoison or hackney 1. Running it again changes
nothing. Then unlock and fetch, as described below; on a 0.53 site that
resolved on the first `mix deps.get`.

By hand, change every one of these the application declares before fetching
(the versions are Brando's own, from its `mix.exs`):

```elixir
# mix.exs
{:phoenix, "~> 1.8.15"},
{:phoenix_live_view, "~> 1.2.0"},
{:phoenix_html, "~> 4.0"},
{:ecto, "~> 3.14"},
{:ecto_sql, "~> 3.14"},
{:postgrex, "~> 0.20"},
{:gettext, "~> 1.0"},
{:floki, "~> 0.32"},
{:swoosh, "~> 1.17"},
{:igniter, "~> 0.8", only: [:dev, :test]},
```

Brando pins `phoenix` 1.8.15 and `phoenix_live_view` 1.2.12 exactly. If the
application also declares `sentry` (`~> 13.0`), `oban` (`~> 2.23`), `cachex`
(`~> 4.0`), `image`, `req` or another of Brando's dependencies, compare it with
Brando's `mix.exs` as well. In particular:

- Gettext 1.0 is required; `~> 0.26` does not resolve.
- Remove `timex`. No Timex release accepts Gettext 1.0 (3.7.13 requires
  `~> 0.26`), and Brando's installer added it to sites until 2021. Replace its
  calls with `Date`, `DateTime` and `Calendar`; Brando makes the `tz`
  package Elixir's time zone database at boot.
- Drop `only: :test` from `floki` (the Phoenix generator default). Brando uses
  Floki at runtime, and `mix deps.get` stops with "Dependencies have diverged"
  while the application restricts it to tests.
- Igniter is an optional Brando dependency the source tasks are built on.
- Brando depends on `ex_aws` 2.7, which accepts only hackney 4 whenever
  anything else brings hackney in. Packages still on HTTPoison or hackney 1.x,
  such as `ex_chimp` 0.1, fail with `version solving failed`. Bump `ex_chimp`
  to `{:ex_chimp, "~> 0.2.0"}`, which uses Req with the same API. Upgrade
  other such packages to a release on hackney 4 or Req, or move those calls to
  Req, which Brando already depends on.

The old lock holds packages at versions the new Brando cannot use (`swoosh`
1.14, or `elixir_make` 0.6, which `vix` and `image` cannot use), and Mix
names `the lock` in the conflict. Unlock everything, then fetch:

```shell
mix deps.unlock --all
mix deps.get
```

Starting from the `mix.lock` of a site already on 0.55 also works.

Pin the toolchain with mise or asdf:

- Elixir 1.18 or newer (Brando's `mix.exs` requires `~> 1.18`) on OTP 27 or
  newer. CI runs Brando's tests on Elixir 1.18.1 with OTP 27.2, 1.19.5 with
  OTP 28.5 and 1.20.4 with OTP 28.5.0.8, and Brando's own `.mise.toml` pins
  1.20.4 and 28.5.0.8. Develop on 1.19 or later: on older Elixir, Phoenix
  1.8's code reloader unloads every consolidated protocol on every request,
  which adds 50 to 70 ms to each request in development. Releases have no
  code reloader.
- Node 24. Brando's `.mise.toml` pins it, CI builds with it, and the template
  Dockerfile's `node:24` stages, which `mix brando.gen.backend --upgrade`
  writes (see [Admin assets](#admin-assets)), build with it. The admin's
  `engines` (`>=24.0.0`) rejects Node 22 and older, and the odd 23, in pnpm
  installs.
- `twined/fehn:4.2` for the release build. A 0.53 or 0.54 Dockerfile builds on
  `twined/fehn:3.9` (Elixir 1.15) or `3.10` (Elixir 1.17), which cannot compile
  Brando's `~> 1.18`. Change its `FROM --platform=linux/amd64 twined/fehn:<tag>
  as deps` line to the fehn 4.2 variant for the server's Ubuntu release, since
  a release starts only on a server with the image's glibc and OpenSSL:
  `twined/fehn:4.2` (or `4.2-noble`) for Ubuntu 24.04 and
  `twined/fehn:4.2-jammy` for Ubuntu 22.04, both Elixir 1.20.4 on OTP
  28.5.0.8. fehn 3.x built on Ubuntu 20.04, whose variant,
  `twined/fehn:4.2-focal`, has Elixir 1.19.5 on OTP 28.4.3: on it, pin those
  versions instead, or better, upgrade the server to 22.04 or 24.04 (or move
  to a new one) before the first deploy of the upgraded site.
  `mix brando.gen.backend --upgrade` rewrites other parts of the Dockerfile
  but not `FROM`, and names an older tag in a notice.
  [The Docker build](deployment.md#the-docker-build) has the variants and how
  to check a server.

`scripts/prepare_055_deps.exs` and `mix brando.doctor` print the `node` on the
PATH and warn when it is an odd release or older than the one Brando is tested
on, before an install fails on it.

### Run the source tasks

Once the dependencies resolve, run:

```shell
mix brando.migrate54
mix brando.migrate55
```

Neither task compiles the application. They load the dependencies and the
configuration and rewrite source that does not yet compile against the new
Brando; the application usually compiles only after both have run.

Applications already on Brando 0.54 skip `mix brando.migrate54` and run only
`mix brando.migrate55`. Both tasks match legacy syntax or missing
configuration only, so running one on source that no longer needs it changes
nothing.

Brando's optional task and helper modules automatically request recompilation
when Igniter becomes available. The dependency remains optional at runtime.
Any change to the application's configuration recompiles Brando, which takes
about a minute. `mix brando.migrate54` therefore writes every `config :brando`
setting the upgrade asks for at once (`repo_module`, `mailer` and a placeholder
sender), and `mix brando.migrate55` finds them in place. Replace the
placeholder sender's `noreply@example.com` with the address Brando should send
from before you first compile, and make your own configuration changes in the
same pass. Outside development and test, Brando treats a sender on a domain
reserved for examples as no sender: it sends nothing, and `mix brando.doctor`
fails until it is replaced. A sender set anywhere in `config/*.exs`, inside an
`if config_env() == :prod` block included, gets no placeholder.

After editing a local Brando checkout, run `mix deps.compile brando` and
restart the server: `mix brando.migrate55` takes `:brando` out of the
endpoint's `reloadable_apps` (see below), so the code reloader no longer
picks up Brando's changes (see [Installation and generators](generators.md)).

If the application has never been run through `mix format`, run it and commit
the result before the source tasks, so their diff holds only their changes.
The `mix format` after the source tasks (below) runs LiveView 1.x's HEEx
formatter, which rewrites `<%= expr %>` in HEEx templates to `{expr}`; expect
those changes in the same commit.

`mix brando.migrate54` covers the 0.53 to 0.54 source changes. It:

- rewrites legacy Blueprint list, single, and selection datasources; trait,
  villain/block, form, input, metadata, and JSON-LD syntax; and listing queries,
  filters, actions, selection actions, and supported exports;
- preserves legacy Meta and JSON-LD path/mutator behavior
  (`meta_field "og:locale", [:language], &encode_locale/1` becomes
  `field "og:locale", fn entry -> encode_locale(get_in(entry, [Access.key(:language)])) end`);
- replaces `use Brando.Datasource`, which imported `Ecto.Query`, with
  `import Ecto.Query` in a Blueprint whose functions call its macros (`from`,
  `where` and the rest). A list and a selection datasource may still share a
  name (`list :all` beside `selection :all`): content modules name a
  datasource by its type and name;
- renames legacy listing `filter:` keys and `list_villains/0` calls on
  `Brando.Villain`;
- rewrites every legacy LivePreview target with its own layout and template
  module;
- replaces `mix phx.digest` in a root Dockerfile, removes `?vsn=d` from font
  URLs in application styles/templates, and adds a missing single-Repo
  `config :brando, repo_module:` setting;
- points Brando at the application's mailer and writes a placeholder sender
  when none is set, as `mix brando.migrate55` does (see below), so Brando's
  configuration changes only once;
- removes `processor_module: Brando.Images.Processor.Sharp` from config. Brando
  refuses to boot with it, and Vix is the default;
- moves Gettext backends to `use Gettext.Backend` and their importers to
  `use Gettext, backend: ...`, leaving the `gettext` requirement alone;
- creates the `scripts/sync_gettext.sh` helper in the application, replacing a
  copy of the 0.54 helper. A copy the application edited is left alone with a
  warning;
- moves a Villain editor (`input :data, :blocks`, inside a tab or fieldset) to
  a form-level `blocks :blocks`, and removes the tab or fieldset it leaves
  empty;
- rewrites reads of a Villain HTML field (`entry.html`, `@entry.html`,
  `hero_html`) in a moved schema's own templates to `rendered_blocks`
  (`rendered_hero_blocks`), and lists, with file and line, the `.html` reads
  it left;
- rewrites a fragment's `html` read out of a fragments map to
  `rendered_blocks` (`@partials["footer"].html`, where
  `plug Brando.Plug.Fragment, as: :partials` or a `get_fragments` call fills
  the map), and lists the other `…].html` map reads with file and line. A
  fragment has no `html` since 0.54, and such a read fails the page with a
  `KeyError`;
- adds `relation:` to a `:multi_select` on a has_many relation that has only
  `relation_key:`, naming the join schema's belongs_to on that key
  (`relation_key: :category_id` gets `relation: :category`). The admin form
  crashed without it, and a Blueprint without it no longer compiles. An input
  whose belongs_to it cannot find is listed;
- drops the options of an `:entries` input's `for:` (now `sources:`) that
  the identifiers it lists do not have, such as `preload:` and an order by
  `sequence`, and says what it dropped. The options apply to the identifiers,
  not the source schema (see [Related entries](blueprint_forms.md#related-entries));
  a Blueprint with such options no longer compiles. Options it cannot read
  are listed;
- rewrites 0.53 navigation item reads inside `for item <- @navigation.items`
  (and `:for`) to `Brando.HTML.get_menu_item_url/1`, `get_menu_item_text/1`,
  `get_menu_item_target_blank/1` and `item.children`, and, when templates read
  the page's vars (`@page`, `assigns[:page]`), adds `:vars` to the `preload` of
  the `Pages.get_page/1` calls written with a map, or with a variable the same
  function assigns one (`page_opts = %{…}`). Reads it cannot rewrite, and page
  loads it cannot update, are listed with file and line. When vars are read
  on something other than the page, the `Pages.get_page/1` calls are listed
  beside the reads, for you to give `preload: [:vars]` where their page
  reaches them;
- converts each admin Create/Update LiveView pair the generator made and the
  application did not edit into one `<Name>FormLive`, written beside the
  `UpdateLive` it replaces, deletes the pair and points both routes at the new
  module. A pair that differs from the generator's only in the text of its
  `<:header>` slot counts as unedited, since the 0.55 form shows no header.
  Edited pairs are listed. When two FormLives would share a route
  helper (two `Category` schemas, say) and one is routed in a plain
  `scope "/menu", MyAppAdmin.Menu do` holding only that domain's admin
  LiveViews, the task adds `as: :menu` to the scope and `router_scope: :menu`
  to every Blueprint routed in it. Routes listed flat in `admin_routes`, as the
  0.53 generator wrote them, are wrapped in a new
  `scope "/menu/categories", MyAppAdmin.Menu, as: :menu do` when the domain's
  lines are adjacent. Other shapes are listed with the same fix.
  Without the form route, the listing's edit links crash, and
  `mix brando.doctor` reports each Blueprint whose route helper is missing;
- rewrites a listing's 0.53 `field` and `template` columns into a row
  component when it can convert every column: `component
  &__MODULE__.listing_row/1` in the listing and a `listing_row/1` at the end of
  the module. An `:image` field becomes `<.cover>`, a `:url` field `<.url>`,
  and a Liquid template whose only link goes to the entry's admin update form
  becomes `<.update_link>`, with the markup before the link in its `:before`
  slot and the markup after it in its `:outside` slot (`{{ entry.a.b }}`
  becomes `{@entry.a && @entry.a.b}`, also inside attributes,
  `{% if entry.x %}` an `:if`, and `{% for c in entry.categories %}` a
  `:for={c <- @entry.categories || []}`). Language columns and inline `<svg>`
  icons in badges are dropped. Any other listing is left as it is and listed with file
  and line;
- removes listing actions whose event is `edit_entry`, `duplicate_entry` or
  `delete_entry` from listings that keep `default_actions`, which already
  offers them, and names each one; an action with options beyond `label`,
  `event` and `confirm` is listed instead;
- writes Blueprint labels given as `gettext("…")` as `t("…")` where the admin
  translates them in the schema's domain (tab names, alerts, `label:`,
  `placeholder:` and `instructions:`, listing filter, action, sort and export
  labels, action confirmations, `translate` values), and lists the Gettext
  calls there it cannot rewrite. `gettext/1` extracts into `default`, so such
  a label stayed in English;
- deletes a Phoenix.View-era `ErrorHelpers` module, `view/0` and
  `view_helpers/0` when nothing uses them. Otherwise it replaces their
  `use Phoenix.HTML` with `import Phoenix.HTML`, `import Phoenix.HTML.Form` and
  `use PhoenixHTMLHelpers` and asks you to add `{:phoenix_html_helpers,
  "~> 1.0"}`. It lists any other `use Phoenix.HTML`;
- adds `listeners: [Phoenix.CodeReloader]` to `project/0` (Phoenix 1.8's code
  reloader warns at boot without it), turns `use Mix.Config` into
  `import Config`, and Logger's `:warn` level into `:warning`.

`mix brando.migrate55` covers the 0.54 to 0.55 source changes. It:

- points references to the modules renamed in 0.55 at their new names in
  routers, sockets, config and code: a route's `Brando.SEOController, :robots`
  becomes `BrandoWeb.SEOController, :robots`, and so on (the table is in
  `UPGRADE.md`). An alias in braces the new name cannot share is reported
  instead; the old names keep working, with a warning, until 0.57;
- adds the narrow listing component imports used by custom row functions;
- defaults an unconfigured Swoosh API client to `Swoosh.ApiClient.Req` and
  pins declared `phoenix_live_view` dependencies in `assets/**/package.json`
  to the loaded server version;
- points Brando at the application's `Mailer` (`config :brando, mailer:
  MyApp.Mailer`), or, when it has none, creates `MyApp.Mailer` with the local
  adapter in development and the test adapter in test, and writes a
  placeholder sender (`noreply@example.com`) when none is set. After
  `mix brando.migrate54` these are already in place. Replace the placeholder with an
  address your mail provider sends for, and configure the mailer's production
  adapter in `runtime.exs`, as described in [Email](email.md);
  `mix brando.doctor` warns until you do;
- gives calls to the application's `list_*` queries that order a Sequenced
  schema only by `sequence` a tiebreak (`"asc sequence, desc inserted_at"`, or
  `"asc sequence, asc id"` without timestamps), and lists the calls with no
  `order:` with file and line (see the ordering note in section 3);
- lists front-end scripts under `assets/` that read `data-src` from a
  `<video>`. A file video's `data-src` is on its `[data-smart-video]` wrapper,
  and the `<video>` carries `src` unless it preloads, so read
  `el.closest('[data-smart-video]').dataset.src` or fall back to it;
- warns when `config/runtime.exs` reads the Repo `url:` from the environment
  in `:test` too, and when `test_paths` names a missing directory (see
  [Test and development databases](#test-and-development-databases));
- removes `:brando` and the Hex and git dependencies from the endpoint's
  `reloadable_apps` (usually in `config/dev.exs`), and lists each list it
  changed with file and line. With `:brando` listed, the code reloader checks
  Brando's sources on every development request, and on Elixir 1.19 and later
  each check rebuilds the application's protocols. The application and path
  dependencies you edit alongside it stay; a list left with only the
  application goes, since Phoenix's default reloads the application itself;
- removes a bare `use Phoenix.Component` from a module whose
  `use BrandoWeb, :html` (or a kind of the application's web module that uses
  Phoenix.Component) already does it. Elixir 1.20 warns about the second one,
  which fails `--warnings-as-errors`;
- writes `Brando.Content.get_entries_from_identifiers(ids, [:cover])`, whose
  list of preloads is deprecated, as
  `get_entries_from_identifiers(ids, %{preload: [:cover]})`, and lists a call
  whose preloads it cannot read;
- adds `plug Brando.Plug.Markdown` and `plug Brando.Plug.IndexNow` to the
  endpoint, before the router (and before `Brando.Plug.Health`), unless it
  already has them;
- gives Villain parsers (`use Brando.Villain.Parser`) back what the parser's
  `__using__` no longer brings in, where they use it: `use Phoenix.Component`
  for `~H`, `import Brando.HTML` for components such as `<.picture>`,
  `import Phoenix.HTML`, and the `Brando.Cache`, `Content`, `Datasource`,
  `Utils`, `Villain` and `Liquex.Context` aliases. It also warns about
  overrides of blocks Brando no longer renders, such as `slideshow/2`
  (slideshows became `gallery` in `brando_77`). Delete those; nothing calls
  them;
- removes the Sharp `processor_module` setting, as `mix brando.migrate54` does;
- writes `identifier false` on an embedded Blueprint (`data_layer :embedded`)
  that declares an identifier, which 0.55 refuses to compile;
- writes `default_srcset:` in an image asset's `cfg` as `srcset: %{default:
  […]}`, or removes it beside a `srcset:`. Brando ignored `default_srcset`
  there, so the asset used its `srcset` or the default config's; 0.55 rejects
  the field. Check that the sizes the list names are in the asset's `sizes`;
- writes `from:` or `for:` on a slug input as `source:`, or removes it beside
  a `source:`. The slug input reads only `source:`: under the others the slug
  never filled in, and 0.55 refuses to compile them. The 0.55 development
  `mix brando.gen.blueprint` wrote `from:`: an application's own copy of its
  template, `priv/templates/brando.gen.blueprint/blueprint.ex`, is EEx and is
  not rewritten. The task reads it as text and lists the lines that look like
  a slug input naming `from:` or `for:`; check the slug inputs there and
  change them to `source:` by hand;
- lists, with file and line, each read of an `:entries` relation
  (`project.related_entries`) that does not go through `.identifier` (see
  below);
- copies each Blueprint's translations from its 0.53 `*_naming`, `*_forms`
  and `*_listings` catalogs, and the `default` domain's translations of its
  `t/1` labels, into its schema's domain, in every locale of the Gettext
  backend the Blueprint translates through (its `gettext_module`, by default
  `MyAppAdmin.Gettext`). Copies of those catalogs in another backend, such as
  the frontend's, are read by nothing and are left alone (see
  [Reconcile Gettext catalogs](#5-reconcile-gettext-catalogs));
- sets `persist_identifier false` on Blueprints with no admin editor (no
  `:update` form route and no admin LiveView), no `absolute_url`, and nothing
  that could select their entries (no `:selection` or `:single` datasource,
  no `:entries` input whose `sources:` name them, no `:entries` relation
  without an input that lists its `sources:`), and lists the Blueprints it
  could not decide. A join schema such as `ArticleCategory`, which only
  `belongs_to` its two sides, is set too. `mix brando.identifiers.sync` then deletes
  such a Blueprint's existing identifiers, and any pick that still points at
  them;
- completes `Plural-Forms` headers in `priv/gettext/**/*.po`. Gettext 1.0 warns
  on `nplurals=2;` without a rule and on a rule without its trailing `;`, once
  per catalog per compile, so `--warnings-as-errors` fails until they read
  `nplurals=2; plural=(n != 1);`. Older Poedit releases wrote the line without
  its `\n`, so Gettext reads it joined to the next header
  (`plural=(n != 1);X-Generator: Poedit 3.0.1`) and warns although the rule is
  complete. The task gives such a rule a line of its own, keeps the header that
  followed it, and drops text that is no header of its own (a stray
  `"3.0.1;\n"`) or a header a later line sets again, listing each file;
- refreshes `scripts/sync_gettext.sh` and archives the consumer-owned
  `mix brando.upgrade` task that 0.54 installed, wherever it lives under `lib/`,
  so Brando's own `mix brando.upgrade FROM TO` hook can take over the task name
  (copying migration files is now `mix brando.gen.migrations`);
- creates `florist.config.exs` when both legacy `deployment.cfg` and
  `fabfile.py` exist and no Florist configuration is already present, and adds
  `plug Brando.Plug.Health` to the endpoint, before the router. Florist's
  deploy and nginx templates check `/health`.

The Florist conversion reads only deterministic literal settings; it never
evaluates Python. It carries over the project/module, production and staging
targets, SSH endpoint, remote paths and names, database names/users, Docker
host/file, domains, and pgbackup intent where they can be inferred. It retains
the legacy `:single` deployment and nginx topology. Existing
`florist.config.exs`, `deployment.cfg`, and `fabfile.py` files are never
overwritten or removed.

Where `deployment.cfg` falls short, the converter reads the other legacy files:

- a target's domain comes from `<TARGET>_URL`, or, when that is missing or still
  the install template's `http://somesite.com` (which it reports), from
  `BRANDO_URL_HOST` in `.envrc.<flavor>`, then from the `server_name` of the
  `etc/nginx/<flavor>.conf` server that proxies to the application (the HTTPS
  one first);
- the application port comes from `PORT=` in `etc/supervisord/<flavor>.conf` or
  `etc/systemd/<flavor>.service`, checked against the nginx upstream. Without
  either it falls back to the bundled Fabric defaults (`8055` and `8060`) and
  says so;
- the warnings name the process manager it found: supervisord or systemd.

Passwords are deliberately omitted. Before loading the generated configuration,
export `FLORIST_DB_PASSWORD_PROD` and, when generated,
`FLORIST_DB_PASSWORD_STAGING`. Florist uses the SSH agent by default; do not
copy `SSH_PASS` into source control. The task warns and uses a documented
fallback for any Python expression it cannot convert safely.

It does not connect to the database, generate application Blueprint migrations,
choose identifier persistence, migrate data, or resolve production constraints.

Named environments and multi-site tenancy remain opt-in. Projects staying in
the default `tenancy_mode: :none` keep their existing content and media in the
classic locations; they still apply the ordinary Brando-owned public
migrations, but do not add the tenant plug, create tenant migrations, provision
site/environment records, or copy data with `mix brando.migrate_to_tenant`.

After completing this general source upgrade, applications deliberately
choosing tenancy can run
`mix brando.setup.tenancy --mode single --site-key my-site` or
`mix brando.setup.tenancy --mode multi`. That separate Igniter task configures
the deterministic application source changes without running migrations or
copying live data; see `guides/tenancy_and_environments.md` for the ordered
conversion workflow.

The following 0.54 and 0.55 changelog items remain manual because their
correct rewrite depends on application semantics:

- converting legacy `Brando.Type.Video` embedded values to
  `Brando.Videos.Video` records and migrating their data;
- updating source-controlled Liquid/HEEx ref paths and `gallery_images` access
  (Brando-owned migrations handle database-stored module/fragment code);
- updating code that reads an `:entries` relation. It holds the join rows,
  each with its `identifier`, where it held identifiers, so
  `Enum.map(project.related_entries, & &1.entry_id)` fails with a `KeyError`.
  `mix brando.migrate55` lists the reads. Preload the identifiers through the
  rows and read the entry id there:

  ```elixir
  project = Brando.Repo.preload(project, related_entries: :identifier)
  ids = Enum.map(project.related_entries, & &1.identifier.entry_id)
  ```

  The rows come in the order the editor picked them; a list query on `ids`
  does not keep it (see [Entries](blueprint_fields.md#entries));
- moving datasource declarations that still use `Brando.Datasource` outside a
  Blueprint module onto the appropriate Blueprint;
- writing the row component for each listing `mix brando.migrate54` listed
  (see [Rows](blueprint_listings.md#rows)), replacing positional
  `child_listing` declarations with child schemas, and redesigning exports
  that use the removed `after_export` callback;
- setting `manifest: 'manifest.json'` in the frontend's Vite config only when
  that application uses Vite 5+, which moved the default manifest into
  `.vite/`. Vite 3 and 4 manifests keep working as they are: they name no
  entries, so Brando finds the critical entry by its key (`js/critical.js`);
- replacing custom processing that relied on sharp-cli, consolidating the
  Create/Update LiveViews `mix brando.migrate54` listed, adopting `<.head>`,
  and updating the navigation reads and page loads it listed;
- refreshing the frontend's package-manager lockfile and rebuilding it after
  the task pins `phoenix_live_view` (the admin is covered in
  [Admin assets](#admin-assets)); nonstandard frontend manifests still need
  manual review. If application code calls Hackney directly, declare
  `{:hackney, "~> 4.0"}`: hackney 1.x does not resolve next to Brando (see
  [Dependencies and toolchain](#dependencies-and-toolchain));
- updating callers of `Brando.Videos.Uploader.initiate_upload/3` for its new
  error tuples and provider credential behavior;
- replacing the removed Brando.CDN key-existence check by hand. `key_available?/2` has inverted
  truth and deliberately different error semantics, so a mechanical rename is
  unsafe;
- moving function-based asset `config_target` callbacks from helper modules to
  the relevant Blueprint schema;
- repointing custom admin form components at the modules the form's markup was
  split into. `BrandoAdmin.Components.Form` no longer exports the input
  primitives (`field_base/1`, `input/1`, `label/1`, `error_tag/1`,
  `submit_button/1`, `inputs_for_block/1`, `inputs_for_poly/1`,
  `array_inputs/1`, `array_inputs_from_data/1`, `map_inputs/1`,
  `map_value_inputs/1`, `translate_error/1`) — those are now
  `BrandoAdmin.Components.Form.Primitives` — nor the image, file and video
  drawers and their JS command helpers, which are `Form.ImageDrawer`,
  `Form.FileDrawer` and `Form.VideoDrawer`. The functions and their assigns are
  unchanged, so each is a rename, but the compiler cannot rewrite them for you
  because the call sites are in application markup. `mix compile
  --warnings-as-errors` reports every one as an undefined function;
- transferring ownership of PostgreSQL's `oban_job_state` enum before the Oban
  v14 migration when deploying through the bundled Fabric workflow;
- showing Brando's dashboard. The admin's start page is the application's own
  `MyAppAdmin.DashboardLive`, and one from an older installer renders only a
  header. `mix brando.migrate55` replaces a `DashboardLive` that is exactly the
  old installer's with the current template, and lists one that renders
  `Content.header` but differs. In that one, render the dashboard component,
  as the installer's template does:

  ```elixir
  def render(assigns) do
    assigns = assign_new(assigns, :authorization, fn -> nil end)

    ~H"""
    <.live_component
      module={BrandoAdmin.Components.Dashboard}
      id="admin-dashboard"
      current_user={@current_user}
      authorization={@authorization}
    />
    """
  end
  ```

The tasks report these items as warnings so they cannot be missed in the
review.

Of what Phoenix 1.8 and phoenix_html 4 removed, `mix brando.migrate54`
handles the Phoenix.View-era helpers and the code reloader's listener (see
above). One thing is left to you: LiveView 1.2 warns at compile time about
`<input name="id">`, which overrides the form's `id` property in the browser.
Rename the field (to `_id`, say) and map it back where the form is handled.

Review every source change. `mix brando.migrate55` sets
`persist_identifier false` on Blueprints with no admin editor that nothing can
select; set it on any other Blueprint that should not persist identifiers:

```elixir
persist_identifier false
```

Then validate and commit the source migration:

```shell
mix format
mix compile --warnings-as-errors
mix test --warnings-as-errors
```

Rerunning either task is safe; a second run should produce no source diff.

### Admin assets

A 0.54 site's `assets/backend` is usually yarn, Vite 5 and Svelte 4, and the
source tasks leave it alone. Bring it to the current template:

```shell
mix brando.gen.backend --upgrade
```

It takes the template's package versions, `engines` and `packageManager`
(keeping the application's own packages, scripts and BrandoJS source), replaces
`vite.config.js`, removes `svelte.config.cjs` and yarn/npm lockfiles, and
replaces the Dockerfile's `assets_backend` stage with the template's pnpm stage.
That stage copies `assets/backend/.yalc` only when it exists, which Dockerfile
frontends up to 1.1 can reject, so an older or missing `# syntax=` line at the top
of the Dockerfile moves to the template's `# syntax=docker/dockerfile:1`; a
custom frontend is kept with a notice. An older `twined/fehn` tag in the
`deps` stage's `FROM` is named in a notice and kept (see the toolchain list in
[Dependencies and toolchain](#dependencies-and-toolchain)). It also moves the admin's CSS build to native EuropaCSS (see
[Native EuropaCSS](#native-europacss)).
Customized CSS and other existing files are kept. It also moves the
`assets_frontend` stage up to the same Node major when
`assets/frontend/package.json` sets no `engines.node`, or one that allows it;
otherwise a notice says why it was kept. Either way, check that the frontend
builds on that Node. Review the diff, then install and build:

```shell
mix brando.assets.setup --backend-only
```

`--backend-only` leaves `assets/frontend` alone, for a frontend that still uses
yarn or its own build; without it the task installs and builds both with pnpm.
Commit the `assets/backend/pnpm-lock.yaml` it writes: the Docker build installs
from it. The upgrade keeps where the admin takes BrandoJS from: an npm version
moves to Brando's, and a Yalc copy or linked checkout stays. When Brando is a
release and the admin still uses a Yalc copy, a notice suggests
`mix brando.assets.setup --npm`, which pins the npm release and removes the
copy. The Docker image installs BrandoJS from npm, or ships the local
`assets/backend/.yalc` when the admin uses one, so rerun the setup after
updating BrandoJS.

`mix brando.doctor` reports admin assets from an older BrandoJS and suggests
the fix for its source: `mix brando.assets.setup --npm` for npm (`--local`
while Brando is a `-dev` version, which has no npm release),
`npx yalc update` and `pnpm install` for a Yalc copy. On a yarn-era `assets/backend` that is not
enough: run `mix brando.gen.backend --upgrade` first, then the setup above.
Its Admin CSS compiler check warns while `assets/backend` is not on the native
EuropaCSS packages at the versions Brando's template pins (the legacy
`@brandocms/europacss`, a Yalc copy, other versions, or an install older than
`package.json`), and `mix brando.migrate55` names the same in its notice.

#### Native EuropaCSS

The admin's CSS builds with the native (Rust) EuropaCSS compiler through its
Vite plugin, `@brandocms/vite-plugin-europacss`, instead of the legacy
`@brandocms/europacss` PostCSS plugin. The upgrade task makes these changes to
`assets/backend`, keeping the application's CSS and its own configuration:

- `package.json` drops `@brandocms/europacss` and `autoprefixer` and adds the
  Vite plugin and `@brandocms/europacss-cli`, both from npm at an exact
  version; `vite.config.js` (replaced) runs the plugin with `europa.json5`.
- `europa.json5` is created. It extends Brando's preset, so the application
  lists only what it changes:

  ```json5
  {
    extends: './node_modules/@brandocms/brandojs/europa.json5',
    theme: { colors: { dark: '#1d2422', blue: '#3a5f8a' } },
  }
  ```

  Objects merge key by key with the preset's; arrays and plain values replace
  them. The preset sets `nesting: 'expanded'`, so nested rules under a
  selector list compile to plain lists, each with its own specificity, as the
  legacy compiler wrote them, and `responsiveOrder: 'generated-last'` (below).
  Its `migration: { mediaPacking: 'none' }` tells `europa migrate` that the
  0.13 build did not pack media queries, so it skips the warnings that assume
  packing; the compiled CSS is unaffected.
- `postcss.config.cjs` and `europa.config.cjs` are removed when they are an
  earlier template's, unchanged. An application's own is kept with a notice:
  move its settings into `europa.json5` (`pnpm exec europa migrate-config
  europa.config.cjs -o converted.json5` converts static ones) and its PostCSS
  plugins into `vite.config.js`, then delete it. The converter warns that
  `theme.typography.paddingDivider` is deprecated: it fed
  `@column-typography`, which EuropaCSS removed in 0.2.0, so it had no effect
  in 0.13 either. Delete it unless the application's CSS reads it with
  `theme()`. `lineHeight` (the default for `vertical-rhythm()`) and `sections`
  (applied with `@unpack`) remain supported.

`@brandocms/europacss-cli` provides the compiler: pnpm installs its
executable for the machine it runs on from the lockfile's optional
dependencies (macOS, Windows, and Linux with glibc or musl, x64 and arm64), so
no Rust toolchain is needed. Install on the machine that builds, as the
template Dockerfile does, rather than copying `node_modules` between
platforms, and never with `--no-optional`. The CLI is `pnpm exec europa` in
`assets/backend`.

The application's admin CSS needs these changes; the upgrade task lists the
`@row` and `@container;` it finds:

- **Cascade layers.** The admin's styles are in the layers `reset, vendor,
  brando, app`, in that order. Put the application's rules in `@layer app { … }`
  and declare the order first, as the template's `css/app.css` does:
  application rules then outrank Brando's whatever their selectors. Unlayered
  rules outrank every layer. `!important` reverses layer order: an
  `!important` in Brando's layer outranks one in `app`.
- **`@row`** is gone. Write out what 0.13 compiled it to; `gap` is not
  equivalent where children set their own margins:

  ```css
  .row {
    display: flex;
    flex-wrap: nowrap;            /* `wrap` for `@row N/wrap` */

    > * {
      @space margin-left 1;

      &:nth-child(2n+1) {         /* `@row N`: Nn+1; bare `@row`: 1 */
        margin-left: 0;
      }
    }
  }
  ```

- **`@container;`** is now a CSS container query: use `@space container;`.
- **Suffix nesting** (`&__title`, `&-pin`) is not CSS nesting. Write the full
  class; `pnpm exec europa migrate --fix` rewrites the simple cases.
- **`@keyframes` inside a rule** is an error: move it outside the selector.
- **Responsive order is 0.13's.** The preset sets `responsiveOrder:
  'generated-last'`: a hand-written `@media` stays where it is written, and
  media from Europa's directives (`@space`, `@fontsize`, `@responsive`…)
  comes after the plain rules of the stylesheet, as 0.13 appended it. Keep
  it: the application's `europa.json5` compiles Brando's CSS as well, and
  EuropaCSS's default, `'all-last'`, would move Brando's hand-written `@media`
  after its plain rules too.
- Package imports (`@import 'pkg/file.css'`) and Vite aliases work: the Vite
  plugin resolves them.

Check the stylesheet, then compare the old and new builds in a browser:

```shell
cd assets/backend
pnpm exec europa migrate css/app.css --from 1.0.0-beta.6 --config europa.json5 --check
pnpm exec europa compare http://localhost:4000/admin --before old-admin.css --after new-admin.css \
  --stylesheet /assets/admin/admin-<hash>.css --viewport 1440x900 --viewport 390x844
```

`europa migrate` follows package imports from `node_modules`, as the Vite
plugin does. Keep a copy of the CSS the legacy build wrote before upgrading;
`europa compare` swaps it into a logged-in page (see EuropaCSS's guide to
comparing rendered styles).

### Review a generated Florist configuration

Treat switching deployment tools as its own rehearsed migration. Before the
first Florist command:

1. Compare every generated target with its `GLUE_SETTINGS` and target function
   in `fabfile.py`, especially domain, base directory, process name, database,
   Docker host, and Dockerfile. Check each domain, SSL mode and port the
   converter took from the legacy `.envrc`, nginx and process manager files
   (its warnings name the source), and any it fell back on. Florist names the
   single-deployment application port `blue_port`.
2. Keep `deployment type: :single` and `webserver type: :nginx` for the initial
   cutover. Moving to blue/green changes services, ports, proxying, and release
   directories and should be tested separately.
3. Protect persistent media deliberately. The bundled Fabric media operations
   and Florist both use `<base>/<project>/media`, but Florist changes releases
   to versioned directories and creates a `current/media` symlink. Verify any
   project-specific media path before cutover, back it up, and confirm the
   symlink points at the existing persistent directory.
4. Compare the legacy `etc/` process manager (systemd units or supervisord
   programs), nginx, logrotate, pgbackup, cron, and env files with Florist's
   generated/bootstrap behavior. Florist runs the release as a systemd service:
   on a supervisord site, stop and disable the supervisord program at cutover so
   the two do not compete for the port. Do not run bootstrap over a production
   service until the resulting paths and units have been reviewed. The
   generated staging target retains the bundled nginx `noindex` behavior.
5. Confirm `plug Brando.Plug.Health` sits in the endpoint before the router
   (`mix brando.migrate55` adds it when it creates the configuration). Florist
   checks `/health` during deploys; without the plug the check never passes.
6. Configure rclone manually if the fabfile used it. Its prompted credentials
   and deployment-specific bucket paths are intentionally not migrated.
7. Verify the Docker image contains the standard Mix release tarball at the
   path expected by Florist's `release_builder: :elixir`, then rehearse build,
   copy, upload, unpack, migrate, restart, and rollback on staging.

The legacy files remain available as an audit trail. Remove them only in a later
commit after the Florist deployment has been proven.

## 3. Generate and review database migrations

A project already on a 0.55 development build skips the source tasks above and
starts here, to pick up the migrations added since it last upgraded.

`mix brando.upgrade.database` runs this section and section 4 for you in an
application without named environments. Each run works out where the database
stands, runs the next steps of the order below, and stops wherever this guide
has you review something: after copying Brando's migrations, after a failed
conversion check, and after writing the Blueprint migrations (always with
`--reconcile`). It asks before every step that changes the database. Run it
again after each stop until it says the database phase is done; `--dry-run`
shows the plan. With named environments, follow the steps below by hand.

First copy every missing Brando-owned migration:

```shell
mix brando.gen.migrations
```

There are no `brando_206` or `brando_208` migrations: both numbers were
reserved and never needed, so the gap is not a missed migration.

`mix brando.migrations.check`, run against the database you will migrate,
lists copies made earlier that have not run yet and differ from Brando's
templates. `mix brando.gen.migrations --refresh` rewrites every copy that
differs, run or not (see [Test and development databases](#test-and-development-databases)).

The Igniter migration-file command does not start the application or touch the
database. It allocates monotonically increasing Ecto versions and preserves
historical files. `mix brando.migrate55` archives the unmodified
`Mix.Tasks.Brando.Upgrade` that 0.54 installed; a customized one must be renamed
and compiled before using the library-owned versioned upgrade hook.

Handle application Blueprints according to their history:

- For Blueprints with valid generated migrations and snapshots, run
  `mix brando.gen.blueprint_migration --all` and review the diffs, or plan one
  with `mix brando.gen.blueprint_migration MyApp.Domain.Schema`. `--all` also
  proposes a create-table migration for every Blueprint without a snapshot, so
  rebaseline existing tables first (next point).
- For an existing table with no generated Blueprint snapshot, do not apply the
  create-table migration that a first normal run would propose. Independently
  verify the live table, columns, indexes, and foreign keys against the current
  Blueprint, then establish the known-good baseline with `--rebaseline`.
- For a genuinely new table, use the normal generator output.
- For a table, root primary-key, physical primary-key source, or existing
  column-level primary-key change, write and test a hand-written Ecto migration,
  then rebaseline. The generator deliberately refuses to infer these operations.

See [Blueprint migrations](blueprint_migrations.md) for renames, physical Ecto
sources, relation corrections, type/default conversions, legacy snapshots,
custom paths, and fail-closed history recovery.

When a migration adds the Creator trait's `edited_at` to an existing table, the
generator backfills it from `updated_at`, as `brando_175` does for Brando's own
tables.

### Legacy snapshots

A snapshot written before Brando's blocks conversion describes a table the
Brando migration chain has changed since. Diffed against it, the generator
proposes storage that already exists (`create table(:projects_blocks)`,
`rendered_blocks`) and drops the legacy Villain columns (`data`, `html`,
`*_data`). It warns when a planned table or column already exists in the
database or a planned drop looks like a Villain column. In that case, generate
the migrations with `--reconcile` against a migrated copy of production, which
does steps 2 to 6 below for you, or edit each generated migration by hand
(always, in an application with named environments, where `--reconcile` is
refused):

```shell
mix brando.gen.blueprint_migration --all --reconcile
```

That order is: `mix brando.gen.migrations`, `mix brando.migrate` (Brando's own
migrations, the blocks conversion among them), `mix brando.check.legacy_conversion`,
`mix brando.gen.blueprint_migration --all --reconcile`, review with a rollback
and forward, then `mix brando.migrate` again. `mix brando.migrate55` prints this
order when it sees `brando_102` or older as the newest copied migration, or a
snapshot with a Villain field.

1. Compare `\d table` in a migrated copy of production with every generated
   operation.
2. For a table or index that already exists, use `create_if_not_exists`, and
   `add_if_not_exists` for an existing column.
3. Rewrite a `create table(...)` of a table that already exists (one that
   predates Blueprint snapshots, so the generator saw no history) as an
   `alter table(...)` that adds only what `\d` lacks, such as the Creator
   trait's `edited_at` and `updated_by_id`. A table that already matches the
   Blueprint needs no migration: establish its baseline with `--rebaseline`
   as described above.
4. Do not combine `add_if_not_exists` with `references(...)` on a column that
   already exists. PostgreSQL skips the column but still adds the named
   foreign-key constraint, and stops with `constraint ... already exists`.
   Leave the column out, or drop the constraint first with
   `drop_if_exists constraint(...)`.
5. Keep `data`, `html` and the other Villain columns until the converted
   content is verified on production data. They are the only record of what
   the conversion started from, and repairs may need them. Keep any other
   column the plan drops while it still holds data, such as one removed from
   the Blueprint years ago without a migration; count its non-null values
   before deciding.

   `mix brando.check.legacy_conversion` does that verification: for every
   entry, it compares the Villain JSON with the blocks the upgrade migrations
   made of it (blocks at each level, vars and their values, refs, table rows,
   fragments) and names what is missing, such as
   `pages #12 › block 3 (module "Values") › vars: heading missing`. Run it
   straight after `mix brando.migrate`; it exits with status 1 while anything
   is missing. Its documentation lists what it leaves out, such as rendered
   HTML, which a diff of the public pages covers.

   It also checks that media refs kept their media: a picture whose Villain
   data had a `path` has an image, a gallery has as many images as Villain
   listed, a video has a video. Until it was fixed, `brando_133` linked a
   picture to an image by `path` only, and left it empty when the image had
   no row (deleted, or in the trash), although 0.53 showed it from the
   picture's own data; galleries lost such images too. A site that ran that
   copy sees findings like
   `pages #2 › block 3 (module "Jobb med oss") › ref pic: legacy image images/site/posts/1n60vo3o9p06.jpg has no image now (lost in the conversion, or removed by an editor since)`.
   `mix brando.repair.legacy_media --dry-run` lists what it would do about
   each; without `--dry-run` it links the image the Villain data names, or
   makes its row from that data, and adds missing gallery images in their
   places. It writes only where it can tell the media was lost in the
   conversion: it skips, with the reason, an entry whose blocks no longer
   line up with Villain's, an entry, block or gallery edited since the
   conversion, and, once the conversion is more than 30 days old, any image
   it would have to make, as emptying the trash leaves no trace of what an
   editor deleted. Run it soon after the upgrade, while the Villain columns
   are there, then run the check again; what it skipped is for an editor.
   A site that has resaved its entries since resaves them again afterwards.
6. In `down/0`, undo only what `up/0` added: leave out the tables, indexes
   and columns that existed before the migration.
7. Roll back and forward once on a scratch copy. A second
   `mix brando.gen.blueprint_migration --all --dry-run` should then propose
   no changes.

`--reconcile` reads the database for steps 2 to 6: it guards what exists with
`*_if_not_exists`, turns the `create table` of an existing table into an
`alter`, or records only a baseline when the table already matches, leaves out
existing `references(...)` columns, keeps every Villain column, every column
or table that holds data (with a comment giving the count) and anything the
Blueprint's generated migrations did not create (dropping the `NOT NULL` of a
kept column the schema no longer writes), and keeps pre-existing storage out of
`down/0`. Run it against the production database or a current copy: the
data it reads decides what is kept, and each migration names that database in
its first comment. It prints what it did per file; see
[Reconciling with an existing database](blueprint_migrations.md#reconciling-with-an-existing-database).
Still by hand:

- Step 1 for types, defaults and nullability: `--reconcile` compares names
  only.
- Step 7.
- Whether to drop the columns and tables kept for their data, later, in a
  migration of your own.
- A foreign key missing from an existing column, which a comment in the
  migration names.

A trait removed from a Blueprint without a migration (Translatable, for
example) surfaces in the first generator run as a proposal to drop its columns,
indexes and tables: `language`, its index, `*_alternates`. That is correct but
destructive. Decide whether the data can go before accepting it, or put the
trait back for now; `--reconcile` keeps the ones that hold data.

### Test and development databases

A site that copied Brando migrations years ago may not replay them from an empty
database: early copies use modules that no longer exist (such as
`Brando.Sequence.Migration`), and `mix brando.gen.migrations` leaves an
existing copy as it is. Production is unaffected, because it only runs the new
migrations.

Copies of Brando's data migrations made before this release can also stop an
empty database with `relation "…" does not exist`, naming one of the
application's own tables (`brando_53` is the first). They find the
application's tables through its current Blueprints, and on an empty database
those tables are created by later migrations. The current templates skip a
table that is not there yet. Rewrite the copies that differ from them, keeping
their names and timestamps, and review the diff, since a copy may have been
edited on purpose:

```shell
mix brando.gen.migrations --refresh
```

A database that has already run a copy is not affected by rewriting it. Load test and development databases from a `structure.sql` instead:
migrate a copy of production, run `mix ecto.dump` (it writes
`priv/repo/structure.sql`), and commit the result. The usual `test` alias runs
`ecto.migrate` on an empty database, which replays every migration, so load the
dump before it:

```elixir
# mix.exs, in aliases/0
test: ["ecto.create --quiet", "ecto.load --skip-if-loaded", "ecto.migrate", "test"]
```

Check `config/runtime.exs` before running the alias. The 0.53 installer's
sets the Repo's `url: System.get_env("BRANDO_DB_URL")` in every environment,
and a `url:` overrides the `database:` in `config/test.exs`. Until it is
guarded with `if config_env() != :test do … end`, `mix test` uses, and its
alias loads and migrates, whatever database the shell names, and
`MIX_ENV=test mix ecto.drop` drops it. `mix brando.migrate55` warns about
such a `url:`, and when `test_paths` names a missing directory;
`mix brando.doctor` checks the same in development.

With the guard in place, `--skip-if-loaded` leaves a database that already
has its migrations table alone, so if the old alias already created the test
database, drop it once (`MIX_ENV=test mix ecto.drop`), or give the test
database a new name instead. Phoenix's generated `config/test.exs` appends
`MIX_TEST_PARTITION` to it (`"myapp_test#{System.get_env("MIX_TEST_PARTITION")}"`),
so `MIX_TEST_PARTITION=_055 mix test` creates and loads `myapp_test_055`; to
keep the new name without the variable, change it in `config/test.exs`.
`ecto.migrate` then runs only the migrations newer than the dump.

Before touching a shared database:

1. Read every generated `up/0` and `down/0`.
2. Resolve data prerequisites such as duplicate unique values and null backfills.
3. Run all migrations forward, backward, and forward again on a disposable
   database.
4. Commit each Blueprint, Ecto migration, and snapshot together.

Only then run:

```shell
mix brando.migrate
# With named environments, after public migrations:
mix brando.migrate --tenants
```

`mix brando.migrate` runs the public migrations. Brando's own migrations that
work "in every environment" (their notes in the CHANGELOG say so) change
`public` and every environment schema in that run. `--tenants` then runs the
tenant migrations in each environment, including the Blueprint migrations of
content stored there; tenant discovery needs the public migrations first.

The migrations update every row of many tables (the generated Blueprint
migrations backfill `edited_at` from `updated_at`, for example). PostgreSQL
returns rows from a query without `ORDER BY` in storage order, and an update
moves a row, so any page built on such a query may change order: the first
category of a menu, or articles with equal `sequence`. `mix brando.migrate55`
already gave calls to the application's `list_*` queries that ordered a
Sequenced schema only by `sequence` a tiebreak, and listed the calls with no
`order:` with file and line. Give each of those an order before diffing public
pages against the old site, and check other queries (`Repo` and `Ecto.Query`)
by hand.

## 4. Repair derived data

After the database migration succeeds, rebuild persisted block rendering and
identifiers:

```shell
mix brando.entries.resave
mix brando.identifiers.sync
mix brando.images.adopt
```

All three accept `--yes`, so they can run from a script, and
`mix brando.upgrade.database` runs them, then `mix brando.check.image_texts`,
then rebuilds the search index.

The tasks write to the database, not to a running server's cache. A server
that was running meanwhile keeps serving the pages it cached before (pages
are cached without expiry): restart it, or use Configuration → Cache → Empty
all caches in its admin.

`mix brando.images.adopt` records which config each image was made with, for
the images whose files already match it, so Utilities → Recreate changed
images only recreates the ones that differ. Try it with `--dry-run` first;
`--verbose` names each image's difference (`sizes: missing ["xlarge"]`,
`formats: has [:jpg], config [:jpg, :avif]`,
`large: file missing: images/site/default/large/x.jpg`) and ends with a count
per config target and reason. Run it where the media is: on a copy without
the media files it stops with `No image files found under <media path>`, and
the doctor and Utilities say the same instead of recommending a recreate. A
`formats` difference is real (the default config gained `:webp`, say) and the
images need recreating on the server; a missing file on a machine without
the media is not. See [Media](media.md#images-made-before-fingerprints).

The comparison reads the image files, so it means something only where the
media is. In a local checkout without the production media every image
"differs", and `mix brando.doctor` and Utilities then recommend recreating
them all. Do not press Recreate changed images on that advice. Run
`mix brando.images.adopt --dry-run --verbose` with the real media first (a
copy of the server's `media` folder in the rehearsal checkout), and decide
from its counts.

Run these against staging first and inspect counts and representative entries.
They mutate application data and are not reversed by `mix ecto.rollback`.

Some 0.55 features need a step of their own; the CHANGELOG's Breaking notes
describe each:

- Rebuild the admin search index once in each environment, from
  Configuration → Utilities → Search index. `brando_212` creates the table
  empty.
- An application that sets `config :brando, Oban` itself adds the
  `content_events`, `webhooks`, `search_index` and `notifications` queues, and
  `Brando.Worker.WebhookDeliveryPurger` to its crontab.
- With group authorization, grant the Notifications permission
  (`brando.notifications.manage`) to the groups that should manage
  notification routes; see [Notifications](notifications.md).

`mix brando.doctor` reports migrations that have not run, in `public` and in
each environment, and Oban queues that are missing.

Image alt text, title and credits are now translated maps. Templates that print
them without the `i18n` filter (`{{ entry.cover.alt | i18n }}`) show the raw map.
Module, container and menu templates live in the database, so the source
migration cannot see them; list the ones to fix with:

```shell
mix brando.check.image_texts
```

A multi module's code that reads its entries the 0.53 way,
`{% for link in entries %}{{ link.data.vars.url }}{% endfor %}`, renders
nothing now: each entry is a block, with its vars at `link.vars.url` and its
refs at `link.refs`. `brando_219` rewrites the stored module code: a loop
over `entries`, a variable assigned an entry (`{% assign first_entry = entries.first %}`),
and those paths read directly or through a variable assigned the list.
`mix brando.doctor` lists module code that still reads `.data.vars` or
`.data.refs` (Module entry paths). The migration runs with the others, before
`mix brando.entries.resave`; a site that has resaved already resaves again
after it.

### Check what the tasks may have missed

The source tasks and checks find most of the following now. A site that ran
`mix brando.migrate54`, `mix brando.migrate55` or the conversion migrations
with an earlier Brando revision can still have them: each let a 0.53 site
compile and then fail at runtime or lose content. Check each one from the
application's root:

1. **`.html` on fragments and partials.** Fragments have no `html` since the
   blocks conversion, so a read such as `@partials["footer"].html` raises a
   `KeyError` on every page that renders it.

   ```shell
   grep -rnE '(\]|\w)\.html([^.a-zA-Z_"]|$)' lib
   ```

   Read `rendered_blocks` instead, or render the fragment with
   `Brando.Pages.render_fragment/1`.
2. **`:entries` relations mapped to `entry_id`.** An `:entries` relation
   (`relation :related_entries, :entries`) now holds join rows that point at
   an identifier, so `Enum.map(entry.related_entries, & &1.entry_id)` raises a
   `KeyError`.

   ```shell
   grep -rnE 'relation :\w+, :entries' lib
   grep -rn '\.entry_id' lib
   ```

   For each relation the first command lists, preload the identifier
   (`preload: [related_entries: :identifier]`) and map
   `& &1.identifier.entry_id`.
3. **`:multi_select` on a `has_many` without `relation:`.** The admin form
   crashes on open with "Multi selects for a :has_many relation needs a
   `relation_key` and a `relation`".

   ```shell
   grep -rn -A6 ':multi_select' lib
   ```

   Give each such input `relation:` as well as `relation_key:`: the
   `belongs_to` in the join schema that `relation_key` points at
   (`relation_key: :category_id, relation: :category`).
4. **`sources:` options on an `:entries` input that mention `sequence` or
   `preload`.** The options load identifiers (`content_identifiers`), which
   have `title`, `language`, `status`, `url`, `schema`, `entry_id`, `cover` and
   `updated_at`, and no associations. An order on `sequence` crashes the form
   with `column c0.sequence does not exist`.

   ```shell
   grep -rn -A4 'sources:' lib | grep -E 'sequence|preload'
   ```

   Order by identifier columns (`%{order: "asc language, asc title"}`) and
   drop `preload:`.
5. **Module code in the database that reads `data.vars` or `data.refs`.** A
   multi-module's children are blocks now, so a template that reads
   `{{ link.data.vars.url }}` in `{% for link in entries %}` renders them
   empty. `brando_219` rewrites these paths (see above) and leaves a
   variable it cannot follow, such as one assigned an entry and then assigned
   again; `mix brando.doctor` lists what is left under Module entry paths.
   Change `.data.vars.` to `.vars.` and `.data.refs.` to `.refs.` in each
   module it lists, then run `mix brando.entries.resave`.
6. **Refs that lost their image.** A `brando_133` copied before the fix
   emptied a picture ref whose image had no live row, and left such images
   out of galleries. `mix brando.check.legacy_conversion` lists each one, and
   `mix brando.repair.legacy_media` restores those it can tell were lost in
   the conversion (see [Legacy snapshots](#legacy-snapshots)). The legacy
   Villain column is then the only copy of that image data, so run both
   before anyone drops it.
7. **Every admin form, opened once.** On one 0.53 site, two of the four
   crashes showed only in the admin: open an entry of every Blueprint there
   before the gate below. Restart the server after any CLI repair task
   (`mix brando.entries.resave`, `mix brando.identifiers.sync`, a repair of
   your own): the task runs outside the server, which keeps serving the pages
   it has cached until it restarts.

## 5. Reconcile Gettext catalogs

`mix brando.migrate55` has already completed incomplete `Plural-Forms` headers
in existing catalogs, and copied the translations of each Blueprint's 0.53
domains into the one it uses now. 0.53 translated a Blueprint's strings into
`<domain>_<schema>_naming`, `_forms` and `_listings`; since 0.54 they are all
extracted to `<domain>_<schema>`, so `menu_menuitem_naming.po` and
`menu_menuitem_listings.po` became `menu_menuitem.po`. It also copied the
`default` domain's translations of the labels `mix brando.migrate54` moved from
`gettext/1` to `t/1`. The merge keeps a translation only when the new domain's
`.po` already has it, so run the task before extracting. It reports messages
the old domains translated differently.

Then run:

```shell
mix brando.gettext.reconcile --dry-run
mix brando.gettext.reconcile
```

It extracts the messages, merges each Gettext backend's existing locales (and
only those, with the `Plural-Forms` header the locale's catalogs use), fills an
empty single-line translation from the same `msgid` in a sibling catalog, and
deletes the old `_naming`/`_forms`/`_listings` catalogs the merge leaves
empty. It then lists, per Blueprint domain and locale, the translations
carried over and the ones dropped because their `msgid` is no longer in the
source; on a 0.53 site these are mostly the old generator's action labels
("Edit vacancy", "Are you sure?"). Review the catalog diff before committing.
It does not guess multiline, plural, or contextual translations; reconcile
those by hand.

By hand, the same is `mix gettext.extract`, then
`mix gettext.merge priv/gettext/<backend> --locale <locale>
--plural-forms-header "nplurals=2; plural=(n != 1);"` per backend and locale,
then `bash scripts/sync_gettext.sh priv/gettext/<backend>/<locale>/LC_MESSAGES`.
Avoid `mix gettext.extract --merge DIR --locale LOCALE` here: it merges every
backend it extracted, whatever directory it is given, and creates `LOCALE` in
each one (a `frontend/en` or `backend/se` the site never had).

## 6. Final deployment gate

Before deploying, run the application unit suite and its full serial E2E suite,
including a clean database reset. Verify at least forms, listings, uploads,
LivePreview, block rendering, identifier-backed selections, rollback, and a
second forward migration. If the application has no meaningful tests, the
public-page comparison below is the gate.

Compare the public pages before and after the upgrade with
`mix brando.upgrade.snapshot`, against the old site started in
[Keep the old site running](#keep-the-old-site-running) (on port 4000, say).
In the upgraded application, once its database is migrated:

```shell
mix brando.upgrade.snapshot urls --output urls.txt --base-url http://localhost:4000
mix brando.upgrade.snapshot capture tmp/before --base-url http://localhost:4000 --urls urls.txt
# start the upgraded site on another port
mix brando.upgrade.snapshot capture tmp/after --base-url http://localhost:4001 --urls urls.txt
mix brando.upgrade.snapshot diff tmp/before tmp/after
```

`urls` picks, for each Blueprint other than pages, the entry with the most
blocks in each language. With `--base-url` it asks the old site for each
entry URL, leaves out those it answers with 404 (a language whose routes are
switched off, for instance) and tries the next-heaviest entry instead. Add
entries you know are unusual to the list by hand.

It reports status, visible text, `<head>` tags and element structure
separately, so a moved `data-src` or a reordered list shows even when the
text is the same. Then open a page with a video in a browser: a site's own
video script may read markup 0.55 changed (see the CHANGELOG's Breaking
notes).

If the upgrade must be abandoned, restore both the pre-upgrade application
release and database backup. Code rollback plus `mix ecto.rollback` does not
undo entry resaves, identifier synchronization, or manual Gettext changes.
