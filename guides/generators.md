# Installation and generators

Start a new Brando 0.54 consumer with the Mix installer, then build its assets and
initialize its database. The installer writes an application scaffold; it is not
an in-place updater for a site that already contains application code or content.
For an existing application, follow [Migrating to 0.54](migrating_to_054.md).

This walkthrough uses the developing `next` branch and a classic, single-site
consumer named **Studio**. Keep the Elixir package and JavaScript package on the
same Brando revision. The flow was checked with Elixir 1.20.3/OTP 28.4.1, a local
PostgreSQL database, and the generated Vite consumers. You also need the Phoenix
project generator, Node.js, pnpm, Yalc, and a build environment supported by
Image/Vix. [Media](media.md) explains image processing; no Sharp CLI is required.

## 1. Create the consumer

Use this directory layout so the generated local dependency resolves correctly:

```text
workspace/
├── brando/          # framework checkout
└── sites/
    └── studio/      # Phoenix consumer
```

From `workspace`:

```bash
git clone --branch next https://github.com/brandocms/brando.git brando
mkdir -p sites
cd sites
mix phx.new studio --module Studio --no-install --no-assets --no-dashboard --no-mailer
cd studio
```

Add `{:brando, path: "../../brando"}` to the `deps/0` list in Studio's `mix.exs`,
then run:

```bash
mix deps.get
mix brando.install --module Studio --tenancy-mode none
mix deps.get
```

The generated `mix.exs` uses that same local path. For a consumer using a Git
revision instead, restore its explicit dependency after installation, for example
`{:brando, github: "brandocms/brando", ref: "YOUR_REVIEWED_COMMIT"}`, and publish
BrandoJS from that exact checkout. Do not assume a development branch is a released
Hex version or that the Elixir dependency includes the JavaScript package.

The installer replaces `assets/`, the Phoenix root/home templates, and numerous
application/configuration files. Use a fresh project or commit your work before
running it. File-copy prompts are not a guarantee that every existing file is
preserved. It also attempts to move the test directory; check the generated
`test_paths` and your actual `test/unit` layout before adding application tests.

The scaffold includes the application supervision tree, repo, endpoint/router,
admin dashboard/menu, page controller/templates, Gettext backends, live preview,
frontend/backend Vite projects, release files, seeds, and migrations. Versioned
Brando migrations come from the maintained upgrade templates in numeric order;
they must create their prerequisite tables before later migrations use them.

## 2. Review configuration and storage

Review `config/brando.exs`, `config/runtime.exs`, and `.envrc`. Set the database URL,
public URL, local port, secret key base, and default language for this consumer.
Use a new development database, not another application's database. The runtime
file reads `BRANDO_DEFAULT_LANGUAGE`; set it to `en` to match this walkthrough.
The generated content-language list includes English and Norwegian.

Load the reviewed environment with `source .envrc`, or use `direnv allow` if that
is how you manage project environments. Create writable media storage at the
configured `media_path`. Set `lockdown` and its password deliberately before
checking the public homepage; a locked-down site may show its coming-soon screen.
Replace placeholder organization details, fonts, deployment hosts, and production
secrets before deploying the scaffold. The scaffold disables Swoosh’s unused HTTP
client; configure a delivery adapter and its required client when adding email.

`--tenancy-mode none` is the classic `public`-schema setup. The other choices are:

```bash
mix brando.install --tenancy-mode single --site-key studio
mix brando.install --tenancy-mode multi
```

Choose the mode **once during installation**, not by rerunning these three
commands. `single` requires a lowercase URL-safe site key. Without a mode flag,
the task prompts and defaults to `none`; `--no-tenancy-prompt` selects that default
noninteractively. Follow [Sites and environments](tenancy_and_environments.md)
for provisioning named environments after public migrations.

## 3. Build the JavaScript and CSS consumers

Publish the matching BrandoJS source into Yalc's local store. From Studio:

```bash
(cd ../../brando/assets && yalc publish)
(cd assets/backend && yalc add @brandocms/brandojs && pnpm install && pnpm build)
(cd assets/frontend && pnpm install && pnpm build)
```

The two Vite builds write to Studio's `priv/static`, with separate
`admin_manifest.json` and `manifest.json` files. `yalc publish` packages the
framework source; the consuming application's build compiles it. A standalone
build in Brando's root `assets/` is not a consumer validation step.

For frontend HMR, run `pnpm dev` in the appropriate asset directory and keep the
consumer's HMR configuration consistent with it. The generated frontend uses
port 3000 and backend 3333. If you are serving the compiled assets, disable HMR
in the consumer so it does not request a stopped Vite server. A blank/unformatted
admin is a reason to inspect network errors and the admin manifest before
changing server-side form code.

When Brando changes, publish/update the Yalc dependency and rebuild the backend:

```bash
(cd ../../brando/assets && yalc publish)
(cd assets/backend && yalc update @brandocms/brandojs && pnpm install && pnpm build)
```

Commit the consumer's intended package manifests and lockfiles according to its
dependency workflow. Do not accidentally ship another checkout's Yalc version.

## 4. Migrate, initialize languages, and create an administrator

From Studio, with its environment loaded:

```bash
mix brando.upgrade
mix ecto.create
mix ecto.migrate
mix brando.gen.languages
mix brando.gen.admin
mix run priv/repo/seeds.exs
```

`brando.upgrade` copies missing migration files; it does not apply them. Review
the files before `ecto.migrate`. The language task creates identity/SEO defaults
and prints config to apply; enter English (`en`) and Norwegian (`no`) for the
unmodified scaffold. The admin task prompts for name, email, and password and
creates a Superuser. The seeds expect that first account at ID 1, so run them only
after account creation on this fresh database. They add sample menus, a content
module, translated homepages, and footer fragments.

Do not use `mix ecto.setup` as the first command here: its seed step would run
before the administrator exists. Do not rerun the sample seeds as an upgrade
strategy; they are not an idempotent merge into an existing site.

For `single`/`multi` mode, public migrations still come first, but public sample
content is not the tenant site. Follow the provisioning/seeding path in
[Sites and environments](tenancy_and_environments.md) for that mode. Group-based
authorization is a separate explicit setup described in [Authorization](authorization.md).

## 5. Start and verify

```bash
mix phx.server
```

Open `/admin/login`, sign in with the account you just created, and visit `/` and
`/no`. The seeds render the sample homepages and refresh navigation. Subsequent
editorial changes use the rendering queue, so keep its worker running. In a
controlled import, render a specific page with
`Brando.Content.Blocks.render_entry(Brando.Pages.Page, page.id)`.

Edit a page title and block, save, reload the editor, and inspect the public page.
Check a translated menu and the identity/SEO form for each configured language.
A missing page should reach the fallback controller; a missing asset should be
visible in the network log. These checks establish a working consumer, not merely
a successful file-copy command.

## Generate a content type

From a working consumer:

```bash
mix brando.gen.blueprint
```

Enter a domain such as `Catalog` and schema `Product`. The task creates
`lib/studio/catalog/product.ex`. Fill in the Blueprint's attributes, assets,
relations, forms, listings, identifier, and URL. Then compile and generate the
surrounding resource:

```bash
mix compile
mix brando.gen
```

Enter `Studio.Catalog.Product`. This generates/extends the context and creates
controller, HTML, admin list/form LiveViews, and a schema test. Review the diff and
add the printed admin routes inside `admin_routes`. It does not automatically
complete your public routing or authorization policy.

Generate and review storage separately:

```bash
mix brando.gen.blueprint_migration Studio.Catalog.Product
mix ecto.migrate
```

See [Blueprint migrations](blueprint_migrations.md) for snapshots, subsequent
changes, rollback, and tenant-owned migrations. Do not run a generator repeatedly
over customized templates without reviewing its overwrite behavior.

## Task reference

Run `mix help TASK` in the consumer for task-specific flags. These are distinct
operations, not a sequence to run wholesale:

| Task | Result and follow-up |
| --- | --- |
| `brando.install` | Fresh application scaffold; review config, build assets, migrate and seed |
| `brando.gen.blueprint` | Blueprint source file; define the content model |
| `brando.gen` | Context/web/admin resource around an existing Blueprint; wire routes and review generated tests |
| `brando.gen.blueprint_migration` | Storage migration and Blueprint snapshot; review and apply |
| `brando.upgrade` | Consumer-owned task copies missing framework migrations; apply with `ecto.migrate` or `brando.migrate` |
| `brando.gen.languages` | Identity/SEO defaults and printed language configuration |
| `brando.gen.admin` | Interactive initial Superuser creation |
| `brando.gen.sitemap` | `lib/studio_web/sitemap.ex`; adapt public filters and generate XML |
| `brando.gen.authorization` | Legacy authorization module template; use the authorization guide for group mode |
| `brando.gen.backend` / `brando.gen.frontend` | Asset scaffolds; review overwrites, install packages, and rebuild |
| `brando.gen.mail` | Mailer, emails, and contact-form modules; configure actual delivery separately |
| `brando.gen.release` / `brando.install.fabfile` | Release/deployment scaffolds; review hosts, paths, and credentials |
| `brando.gen.tenant_migration` | Migration for existing tenant schemas; see the tenancy guide |
| `brando.setup.tenancy` / `brando.migrate_to_tenant` | Optional tenancy source preparation/data conversion, not fresh content generators |
| `brando.ssg` | Static build workflow; see sites/environments and deployment |

For install failures, keep the first compiler, migration, or asset error and fix
that stage before seeding or starting the server. Do not mark a migration applied
just to skip an error. On existing installations, use a reviewed upgrade and
backup workflow instead of deleting tables to imitate a fresh install.
