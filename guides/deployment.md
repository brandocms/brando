# Deployment

Brando projects are deployed using [Florist](https://github.com/brandocms/florist),
a zero-downtime deployment tool for Elixir applications. Florist handles the full
lifecycle: building Docker releases, uploading to servers, managing systemd services,
configuring web servers, database operations, and blue/green deployments.

This guide's `deploy` and `rollback` commands refer to the running Phoenix/OTP
application. A site whose `delivery_mode` is `:static` also has an independent
artifact lifecycle in Brando's **Publishing** screen: SSG build, preview, static
deploy, and static rollback. Rolling back one does not roll back the other.

## Prerequisites

- **Florist** installed locally (`mix escript.install github brandocms/florist`)
- **Docker** for building releases
- **SSH access** to your server with key-based authentication
- **Passwordless sudo** for the SSH user on the server. Florist runs `sudo` over
  SSH exec channels without a TTY, so it cannot answer a password prompt and
  will fail on its first command without this.
- A server running Linux with PostgreSQL and either Traefik or nginx

<!-- usage-rules:start topic="deployment" -->

### Health endpoint

Blue/green deployments require a health endpoint. Florist starts the new colour,
polls `/health` until it answers, and only then switches traffic over. Add the
plug to your endpoint, above the router:

```elixir
# lib/my_app_web/endpoint.ex
plug Brando.Plug.Media, at: "/media"
plug Brando.Plug.Health
```

`Brando.Plug.Health` answers `GET`/`HEAD /health` before the request reaches the
router, returning `200` when healthy and `503` otherwise. Without it, the health
check never passes and the deploy stalls on the new colour.

<!-- usage-rules:end -->

### Formatting florist.config.exs

Florist's DSL relies on `locals_without_parens`, but florist is installed as an
escript rather than a dependency, so `import_deps` cannot pick that up and
`mix format` will add parens throughout your config. Mirror the DSL in your
project's `.formatter.exs`:

```elixir
florist_locals_without_parens = [
  set: 2,
  target: 2,
  project_module: 1,
  project_name: 1,
  ssh: 1,
  rclone: 1,
  database: 1,
  docker: 1,
  remote: 1,
  deployment: 1,
  webserver: 1
]

[
  # ... your existing config
  locals_without_parens: florist_locals_without_parens
]
```

## Quick start

```bash
florist init
florist local config:generate
florist prod traefik:setup
florist prod bootstrap
florist prod release:deploy
```

The order matters. `config:generate` writes the systemd, Traefik and logrotate
configs into `etc/`, which `bootstrap` uploads and symlinks. `traefik:setup`
both reads `etc/traefik/traefik.yml` and installs the Traefik binary, which
`bootstrap` checks for before it will configure the web server.

### Release helpers

<!-- usage-rules:start topic="deployment" -->

Florist builds a standard Mix release in Docker, copies
`/opt/app/_build/prod/<app>-<version>.tar.gz` out of the image and migrates
with `bin/<app> eval "MyApp.ReleaseTasks.migrate"`. `mix brando.install`
creates `MyApp.ReleaseTasks` (`migrate/0`, `rollback/2`, `migrate_tenants/0`)
and adds a release for the app to `mix.exs` with
`steps: [:assemble, :tar]`, which writes that tarball. Its tasks lift the
console logger's burst limit, so migrating an empty database logs every
migration rather than stopping partway through. An existing
ReleaseTasks module and release definition are kept, with a notice when the
module has no `migrate/0` or the release does not write the tarball.

An application installed before Brando did this gets the same with:

```bash
mix brando.gen.release
```

It leaves existing release settings, runtime configuration, secrets and
deployment files alone, and a ReleaseTasks file that differs from its
template stops it with an issue. When `mix.exs` already defines releases but
none named after the application, it adds none, since a second release makes
the unnamed `mix release` fail, and a notice says what Florist needs: the
release named like Florist's `project_name`, `steps: [:assemble, :tar]`, and
the only release or `default_release`. The task requires Igniter.

Florist names the release after the version in the `VERSION` file, falling
back to a literal `@version "..."` in `mix.exs`. `mix brando.install` moves
phx.new's inline `version: "0.1.0"` to `VERSION` and makes `mix.exs` read it,
so bump the version in `VERSION`. Florist writes `current/VERSION` on the
server itself when it unpacks a release, so the release needs no copy, but the
Docker build evaluates `mix.exs` and needs `COPY VERSION` next to `mix.exs`.
Brando's Dockerfile template has it, and the installer adds it after each
`COPY` of `mix.exs` in an existing Dockerfile (such as
`mix phx.gen.release --docker`'s), with a notice when it cannot.

<!-- usage-rules:end -->

### Media and log paths

<!-- usage-rules:start topic="deployment" -->

A release evaluates `config/config.exs` and `config/prod.exs` when it is
built, in the Docker image. The installer's `config/brando.exs` sets
`media_path: Path.expand("./media")` and `log_dir: Path.expand("./log")` for
development; in a release those would name the image's `/opt/app`. So the
installer also writes relative paths to `config/prod.exs`:

```elixir
config :brando, media_path: "./media", log_dir: "./log"
```

They resolve at runtime in the release's working directory, the `current`
directory the systemd unit starts in, where Florist links the persistent
`media/` (see [Server directory structure](#server-directory-structure)). A
literal path in the base configuration, a value in `config/prod.exs` or one
set in `config/runtime.exs` is the application's own and is kept.

Uploaded and captured frontend asset sets (`site_assets/`) and each site's
storage and static-site builds (`sites/`) are kept beside the media
directory unless `:site_assets_path` or `:sites_path` is configured. When the
application runs as a release (`RELEASE_ROOT` is set), a media directory that
is a symlink is followed, so on a Florist server they are
`<base>/site_assets` and `<base>/sites`, beside the shared `media/`, not in
the release directory the next deploy replaces. Outside a release, in
development for instance, the link is not followed. On another server where
`media` links to a mounted volume, a release keeps them in the volume's parent
directory; configure both paths to keep them elsewhere.

<!-- usage-rules:end -->

### Ignored files

The installer adds to `.gitignore` what a Brando application builds,
uploads or downloads in its working folder and phx.new does not ignore: the
asset projects' `node_modules`, Yalc copies (`.yalc/`, `yalc.lock`), all of
`/priv/static/`, `/media/` (uploads), `/log/`, and Florist's
`/release-archives/` and `/sql/` (database dumps). `priv/static` holds only
build output: the admin and site builds, the files Vite copies from the asset
projects' `public/` folders (so keep a site's images in
`assets/frontend/public/images`), and what `mix brando.digest` adds. Lines an
existing rule already covers are not added again. A directory line is not
added when the `.gitignore` has an exception (`!` line) anchored inside that
directory, which it would cancel, as Git cannot re-include a file in an
ignored directory; a notice names it instead.

### Migrating from Fabric

Projects still deployed with the legacy Fabric setup (`deployment.cfg` +
`fabfile.py`) get a starting `florist.config.exs` from `mix brando.migrate55`
(part of the 0.54 → 0.55 upgrade). The conversion runs only when both legacy
files exist and there is no `florist.config.exs` yet. It reads literal settings
without evaluating Python and carries over the project/module, production and
staging targets, SSH endpoint, remote paths, database names/users, Docker
host/file, domains and pgbackup intent. It keeps the legacy
`deployment type: :single` / nginx topology, and never touches or removes the
Fabric files.

Check by hand before the first Florist command:

- Passwords are not copied — export `FLORIST_DB_PASSWORD_PROD` (and
  `FLORIST_DB_PASSWORD_STAGING` when a staging target was generated).
- Anything the task warned about; unconvertible Python expressions fall back
  to documented defaults.
- Domains, SSL modes and ports. Where `deployment.cfg` doesn't set them, the
  task takes them from `.envrc.<flavor>`, `etc/nginx/<flavor>.conf` and
  `etc/supervisord`/`etc/systemd`, and otherwise falls back to `8055`
  (production) and `8060` (staging); its warnings say which.
- `plug Brando.Plug.Health` in the endpoint, before the router. The task adds
  it; see [Health endpoint](#health-endpoint).
- The persistent media directory, the legacy `etc/` systemd units or
  supervisord programs, and rclone setup (not migrated).

The full checklist is in "Review a generated Florist configuration" in the
[0.53 migration guide](migrating_from_053.md).

## Configuration

Create `florist.config.exs` in your project root. Run `florist init` to generate
a starter config, then customize it:

```elixir
use Florist.DSL

project_name "myapp"
project_module MyApp

target :prod do
  set :flavor, :prod
  set :mix_env, :prod
  set :base_dir, "/sites/${FLAVOR}"
  set :process_name, "${PROJECT_NAME}_${FLAVOR}"
  set :release_builder, :docker

  ssh do
    set :host, "prod.example.com"
    set :port, 22
    set :user, "deploy"
  end

  remote do
    set :user, "${PROJECT_NAME}"
    set :group, "web"
  end

  database do
    set :name, "${PROJECT_NAME}_${FLAVOR}"
    set :user, "${PROJECT_NAME}"
  end

  docker do
    set :host, "unix:///var/run/docker.sock"
    set :dockerfile, "Dockerfile"
  end

  deployment do
    set :type, :blue_green
    set :blue_port, 8055
    set :green_port, 8056
    set :health_endpoint, "/health"
    set :health_timeout, 5000
  end

  webserver do
    set :type, :traefik
    set :domain, "example.com"
    set :ssl, :auto
  end
end
```

You can define multiple targets (`:prod`, `:staging`, etc.) in the same config file.

A staging target builds the prod release: keep `set :mix_env, :prod` in it,
not the `:staging` in `florist init`'s commented example. A Phoenix application
has no `config/staging.exs`, so `import_config "#{config_env()}.exs"` fails in
a `:staging` build, and the staging host is trusted through the prod
`check_origin`. What differs between the targets is the environment file.

Give each target its own database user, as above. Florist takes one password
per target and leaves an existing user unchanged, so prod and staging sharing
one user on a server would leave the second target's password unused.

### Template variables

These are automatically interpolated in config values:

| Variable | Source |
|----------|--------|
| `${PROJECT_NAME}` | `project_name "myapp"` |
| `${PROJECT_MODULE}` | `project_module MyApp` |
| `${FLAVOR}` | `set :flavor, :prod` |

### Environment variables

Set these before running Florist commands:

```bash
# Required: database password per target
export FLORIST_DB_PASSWORD_PROD="your_database_password"

# Optional: Slack notifications on deploy
export FLORIST_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
```

### Runtime environment (.envrc.&lt;flavor&gt;)

Create one env file per target, named after the target's flavor — `.envrc.prod`
for a `:prod` flavor, `.envrc.staging` for `:staging` — in your project root
(add them to `.gitignore`). Florist reads `.envrc.<flavor>` locally, uploads
it to the server as `.envrc.runtime` and copies it into each release. The
`.runtime` name only ever exists on the server.

The systemd service runs `bin/<app> start`, which does not read the file by
itself: the release's `rel/env.sh.eex` sources it. Without that script, none
of the variables reach the application.

```sh
# rel/env.sh.eex
if [ -f "$RELEASE_ROOT/.envrc.runtime" ]; then
  . "$RELEASE_ROOT/.envrc.runtime"
fi

export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=${RELEASE_NODE:-<%= @release.name %>@127.0.0.1}
```

Florist's blue/green services set `RELEASE_NODE` per colour
(`<app>_<target>_<colour>@127.0.0.1`) and only patch an existing `env.sh` to
respect it, so keep the `${RELEASE_NODE:-...}` form. For `:single`
deployments, set a per-target default in the env file, also in that form, so
prod and staging on one server don't share a node name:
`export RELEASE_NODE="${RELEASE_NODE:-myapp_staging@127.0.0.1}"`.

`mix brando.install` generates both files and `rel/env.sh.eex` for a new
application (see [Deployment hosts](generators.md#deployment-hosts)), with the
variables a Phoenix `config/runtime.exs` reads: `PHX_HOST`, `PHX_SERVER`,
`DATABASE_URL` and `SECRET_KEY_BASE`, plus that `RELEASE_NODE` default. Their
`DATABASE_URL` uses the user `<app>` for prod (Florist's default) and
`<app>_staging` for staging, whose target sets
`set :user, "${PROJECT_NAME}_staging"`. Use whichever
names your own `config/runtime.exs` reads; the example below is for one that
reads Brando's `BRANDO_*` variables.

```bash
export BRANDO_SECRET_KEY_BASE="generate-with-mix-phx-gen-secret"
export BRANDO_DB_URL="postgresql://myapp:password@localhost/myapp_prod"
export BRANDO_URL_SCHEME="https"
export BRANDO_URL_HOST="example.com"
export BRANDO_URL_PORT="443"
export POOL_SIZE="15"
```

<!-- usage-rules:start topic="deployment" -->

> #### Do not set PORT for blue/green {: .warning}
>
> With `deployment type: :blue_green`, systemd sets `PORT` per environment —
> blue and green each get their own. Since `rel/env.sh.eex` sources
> `.envrc.runtime` *after* systemd has set the environment, a `PORT=` line in
> your env file overrides it and puts both colours on the same port.
>
> Florist guards against this: `florist prod bootstrap` and `env:upload` halt
> with an explicit error if they find `PORT=` in the env file. For a `:single`
> deployment, setting `PORT` is fine and expected.

The database user and password in the env file's database URL must match the
target's database user and `FLORIST_DB_PASSWORD_<TARGET>` (for example
`FLORIST_DB_PASSWORD_PROD`), since florist uses those to create the database
user that your app then authenticates as.

<!-- usage-rules:end -->

Upload it with:

```bash
florist prod env:upload
```

## Bootstrapping a server

Bootstrap sets up everything on a fresh server. Run it once per target:

```bash
florist prod bootstrap
```

This runs through the following steps, in this order:

1. Creates the remote system user and group
2. Creates the directory structure on the server, including the blue and green
   environments
3. Uploads your local `media/` directory
4. Uploads your local `etc/` directory
5. Creates the PostgreSQL database and user
6. Configures systemd services (one per blue/green environment)
7. Configures the web server (Traefik or nginx)
8. Sets up log rotation
9. **Dumps your local database and loads it onto the server**
10. Uploads `.envrc.<flavor>` as `.envrc.runtime`
11. Sets file permissions and ownership
12. Sets up automated database backups (pgbackup and rclone)

> #### Step 9 loads your local database {: .warning}
>
> `bootstrap` seeds the server with a dump of whatever is in your **local**
> development database. Make sure that is the data you want on the server.
>
> When migrating an existing site, the clean way is to prepare locally first:
> pull the old server's dump down, restore it locally, run `mix brando.migrate`
> (and `mix brando.migrate --tenants` with named environments) so the schema
> matches the release you are about to deploy, and only then bootstrap. Step 9 then ships the migrated production data for you.
>
> If you bootstrap with dev data by mistake, replace it afterwards:
>
> ```bash
> florist prod db:drop
> florist prod db:create
> florist prod db:load:local
> ```
>
> Either way, take a final dump during the cutover freeze so you do not lose
> edits made on the old server in the meantime.

Note that step 7 requires the web server to already be installed. With Traefik,
`bootstrap` halts with `Traefik is not installed` unless you have run
`florist prod traefik:setup` beforehand — see the ordering in
[Quick start](#quick-start).

Verify the bootstrap completed successfully:

```bash
florist prod bootstrap:verify
```

### Traefik setup

If using Traefik (recommended for blue/green), install it separately:

```bash
florist prod traefik:setup
```

SSL certificates are issued automatically via Let's Encrypt on the first HTTPS request.

## Server directory structure

### Single deployment

```
/sites/prod/myapp/
├── current → releases/1.2.0/    # symlink to active release
├── releases/
│   ├── 1.1.0/
│   └── 1.2.0/
│       ├── bin/myapp            # release binary
│       ├── lib/                 # compiled code
│       ├── priv/static/         # built CSS/JS (baked into release)
│       └── .envrc.runtime       # environment variables
├── media/                       # persistent media uploads
├── site_assets/                 # uploaded frontend asset sets (beside media/)
├── sites/                       # site storage and static-site builds (beside media/)
├── log/                         # application logs
├── sql/                         # database backups
└── etc/                         # configuration files
```

### Blue/green deployment

```
/sites/prod/myapp/
├── blue/
│   ├── current → releases/1.2.0/
│   └── releases/
│       └── 1.2.0/
│           └── media → ../../../media   # symlink to shared media
├── green/
│   ├── current → releases/1.1.0/
│   └── releases/
│       └── 1.1.0/
│           └── media → ../../../media   # symlink to shared media
├── active-environment           # contains "blue" or "green"
├── media/                       # shared between blue and green
├── site_assets/                 # beside media/, so shared too
├── sites/                       # beside media/, so shared too
├── log/
├── sql/
└── etc/
```

<!-- usage-rules:start topic="deployment" -->

Key points:

- Blue and green each run their own systemd service on separate ports
- Media is shared via symlinks (Florist creates these automatically); Brando
  keeps `site_assets/` and `sites/` beside the directory the link leads to
- Only the `active-environment` file and web server config determine which
  environment receives traffic
- Florist keeps the last 5 releases per environment and cleans up older ones

<!-- usage-rules:end -->

## The Docker build

Brando projects use a multi-stage Dockerfile that builds the OTP release:

```
Stage 1: deps          → mix deps.get
Stage 2: compile_deps  → mix deps.compile
Stage 3: compile_app   → mix compile
Stage 4: assets_backend  → pnpm build (admin Svelte app)
Stage 5: assets_frontend → pnpm build (site CSS/JS via Vite + EuropaCSS)
Stage 6: digest        → mix brando.digest (fingerprint static assets)
Stage 7: release       → mix release (create OTP release tarball)
```

<!-- usage-rules:start topic="deployment" -->

Assets (CSS, JS) are built inside the Docker container and baked into the release
at `priv/static/`. There is no separate asset upload step — everything ships as
one tarball.

`mix brando.install` writes Brando's
[Dockerfile](https://github.com/brandocms/brando/blob/main/priv/templates/brando.install/Dockerfile)
and `.dockerignore` when the application has none. An existing Dockerfile,
such as `mix phx.gen.release --docker`'s, is kept, with a notice naming what
Brando's build needs that it lacks: the `assets_backend` and
`assets_frontend` stages, `mix brando.digest`, and the release built in
`/opt/app`. phx.gen.release's Dockerfile builds a runtime image instead,
which Florist does not use. To switch to Brando's, move yours aside and rerun
the installer.

Brando's Dockerfile builds on `twined/fehn:4.2`: Elixir 1.20.4 on OTP
28.5.0.8, on Ubuntu 24.04, the versions Brando's CI tests with and a new
install's `.tool-versions` pins. Brando requires Elixir 1.18 or newer, so a
Dockerfile from an earlier install that builds on an older tag (`4.0` has
Elixir 1.17, the `3.x` tags older ones) cannot compile it: change its
`FROM … twined/fehn:<tag>` line to the 4.2 variant for the server's Ubuntu
release (below). `mix brando.gen.backend --upgrade` rewrites other parts of
the Dockerfile but not `FROM`; it names an older tag in a notice.

The release runs on the server outside Docker, with the ERTS and NIFs such as
`:crypto` built in the image, so the image's Ubuntu release decides which
servers it starts on: a server with an older glibc, or without the OpenSSL
the `:crypto` NIF links, cannot start it, which shows as
`GLIBC_2.3x not found` or a `:crypto` that fails to load. Pick the fehn 4.2
variant that matches the server's Ubuntu release:

| Server       | `FROM` image                                      | Elixir, OTP      | glibc, OpenSSL |
| ------------ | ------------------------------------------------- | ---------------- | -------------- |
| Ubuntu 24.04 | `twined/fehn:4.2` (the same image as `4.2-noble`) | 1.20.4, 28.5.0.8 | 2.39, 3.0      |
| Ubuntu 22.04 | `twined/fehn:4.2-jammy`                           | 1.20.4, 28.5.0.8 | 2.35, 3.0.2    |
| Ubuntu 20.04 | `twined/fehn:4.2-focal`                           | 1.19.5, 28.4.3   | 2.31, 1.1.1f   |

hexpm no longer publishes current Elixir and OTP for Ubuntu 20.04, so
`4.2-focal` has Elixir 1.19.5 on OTP 28.4.3, behind the other variants
(Brando's CI tests Elixir 1.19.5 on OTP 28 too). A site that builds on it pins Erlang 28.4.3
and Elixir 1.19.5-otp-28 in its `.tool-versions` or `.mise.toml`, to develop on
what its releases are built with. Moving a 20.04 server to Ubuntu 22.04 or
24.04, or to a new server, is the better path.

Check the server before its first deploy from a new image:

```bash
lsb_release -a    # the Ubuntu release
ldd --version     # glibc: no older than the image's
openssl version   # OpenSSL: the image's major version
```

The fehn 4.0 and 4.1 images are Ubuntu 24.04, so a site moving from them to
`4.2` needs nothing new on a server that already runs their releases. The
fehn 3.x images are Ubuntu 20.04: a site moving from 3.x keeps its server on
`4.2-focal`, or on `4.2-jammy` or `4.2` once the server is upgraded to 22.04
or 24.04 (or the site moves to a new server).

Florist sends the build context, the project directory, to the Docker daemon
on every build, and that daemon may be remote. The `.dockerignore` keeps out
dependencies and build output, `node_modules`, `media/`, Florist's
`release-archives/` and `sql/` dumps, and the `.envrc*` files with secrets.
An existing `.dockerignore` gets the exclusions it misses appended, with
`.envrc*` unless one pattern already covers every `.envrc*` name (exact names
such as `.envrc.prod` leave a `.envrc.prod.bak` in the context). An appended
line comes last, so it would override a `!` exception that re-includes part
of what it covers: such exclusions are named in a notice instead. Exceptions
that cannot touch them, such as phx.gen.release's `!.git/HEAD`, do not stop
the rest being appended. `priv/static` is excluded too: the build makes it from the two
asset projects, so keep static files such as images and fonts in
`assets/frontend/public`, which Vite copies there. A file left in
`priv/static` works in development and is missing from the release, so the
installer takes out the ones `mix phx.new` writes: its `favicon.ico` goes
(Brando writes its own to `assets/frontend/public`), and `images/logo.svg`
moves to `assets/frontend/public/images/logo.svg`. With the CMS public site,
which a new install adds unless given `--no-public-site`, its `robots.txt` goes too, with `robots.txt` in `static_paths/0` of the web module,
so `BrandoWeb.SEOController` answers `/robots.txt` in development as in the
release. Without the public site, `robots.txt` moves to
`assets/frontend/public/robots.txt`, and `Plug.Static` serves the frontend
build's copy. Only files still as phx.new wrote them are touched; a changed one is
kept, with a notice saying where it belongs.

Both asset stages install with the pnpm version pinned in the Dockerfile and
`pnpm install --frozen-lockfile`, so commit `assets/backend/pnpm-lock.yaml` and
`assets/frontend/pnpm-lock.yaml`. `mix brando.assets.setup` writes them. After
updating BrandoJS, from npm or through Yalc, run `pnpm install` in
`assets/backend` and commit the lockfile it changes; the build stops on a stale
one rather than resolving different packages. The admin stage installs
BrandoJS from npm, or copies `assets/backend/.yalc` when the admin takes it
from a checkout (`mix brando.assets.setup --local`); a deploy then ships
whatever that copy holds.

<!-- usage-rules:end -->

### Source maps

Source maps are kept out of the release. Vite builds them with
`sourcemap: 'hidden'`, so the scripts carry no `sourceMappingURL` comment, and
`mix brando.digest` deletes every `*.map` file under `priv/static` before the
release is assembled. Pass `--keep-source-maps` to the digest task if a site
should publish them after all.

To keep readable stack traces in Sentry, upload the maps in the
`assets_frontend` stage, before the digest deletes them. The generated
Dockerfile does this when it gets a `sentry_auth_token` build secret:

1. Commit `assets/frontend/.sentryclirc` with the organisation and project
   (add `url` for a self-hosted Sentry). It holds no secret:

   ```ini
   [defaults]
   org = my-org
   project = my-site
   ```

2. Create an auth token with the `project:releases` scope and pass it to the
   build as a secret. It never lands in an image layer:

   ```bash
   export SENTRY_AUTH_TOKEN=sntrys_...
   docker build --secret id=sentry_auth_token,env=SENTRY_AUTH_TOKEN .
   ```

The step injects debug IDs into the built scripts and uploads the maps with
`sentry-cli`, so Sentry pairs them with an event without a matching release
name. Your frontend still has to report errors with `@sentry/browser`. Without
the secret the step does nothing.

Projects generated before 0.55 move their frontend maps to
`priv/static/assets/__srcmaps/`, which `Plug.Static` still serves. The digest
now deletes them there too. To upload them, replace those `mkdir`/`mv` lines
with the `RUN --mount=type=secret,id=sentry_auth_token` step from the
[Dockerfile template](https://github.com/brandocms/brando/blob/main/priv/templates/brando.install/Dockerfile).

## Deploying

### Full deploy (build + upload + activate)

```bash
florist prod release:deploy
```

This single command:

1. Builds the Docker image and creates the release tarball
2. Copies the tarball from the Docker image
3. Uploads it to the server via SSH
4. Unpacks and activates it

For blue/green deployments specifically:

1. Identifies the inactive environment (blue or green)
2. Unpacks the release to the inactive environment
3. Creates the media symlink
4. Starts the inactive environment's systemd service
5. Polls the health endpoint until it responds 200
6. Updates the web server config to route traffic to the new environment
7. Stops the old environment

Skip the pre-deploy database backup with `--skip-backup`.

### Step-by-step deploy

If you prefer more control, run each step individually:

```bash
# Build
florist prod release:build

# Extract from Docker
florist prod release:copy_from_docker

# Upload to server
florist prod release:upload

# Unpack and activate
florist prod release:unpack
```

### Running migrations

After deploying, run migrations if there are schema changes:

```bash
florist prod db:migrate
```

## Rollback

> #### Application rollback versus static-site rollback {: .info}
>
> `florist prod rollback` switches the running OTP release (and optionally its
> database). In `/admin/config/publishing`, **Roll back** republishes an older
> `sites/{site_key}/ssg/builds/{version}` artifact to that site's rsync or S3
> target. Static artifacts live outside release `priv/static`, so they survive
> blue/green switches and Florist release pruning.

### Blue/green rollback (instant, zero-downtime)

```bash
florist prod rollback
```

This switches traffic back to the previous environment. Since both environments
remain on disk with their releases, the switch is instant.

### Rollback to a specific version

```bash
# List available versions
florist prod rollback --list

# Rollback to a specific version
florist prod rollback --to=1.1.0
```

### Rollback with database restore

```bash
florist prod rollback --restore-db
```

Restores the database backup that was taken before the deployment you're rolling
back from.

### Pinning releases

Prevent a release from being cleaned up (Florist keeps the last 5 by default):

```bash
florist prod release:pin --id=1.1.0
florist prod release:unpin --id=1.1.0
```

## Blue/green environment management

```bash
# Check which environment is active and their status
florist prod env:status

# Manually switch traffic to the other environment
florist prod env:switch

# Force switch to a specific environment
florist prod env:switch:blue
florist prod env:switch:green

# Check health of the active environment
florist prod env:health
```

## Database operations

```bash
# Create database and user (done during bootstrap)
florist prod db:create

# Run migrations
florist prod db:migrate

# Backup remote database
florist prod db:dump

# Download latest backup to local sql/ directory
florist prod db:download

# Replace remote database with local data
# WARNING: destroys all remote data
florist prod db:load:local

# Dump local database to sql/
florist local db:dump
```

### Automated backups

Set up daily PostgreSQL backups:

```bash
florist prod pgbackup:setup
```

With `set :pgbackup_enabled, true` in the target's database settings,
Florist uploads the project's `etc/pgbkup.sh` and runs it from the postgres
user's crontab. The installer does not write it; copy Brando's before the
first `bootstrap` or `pgbackup:setup`:

```bash
mkdir -p etc
cp deps/brando/priv/templates/brando.install/etc/pgbkup.sh etc/pgbkup.sh
chmod +x etc/pgbkup.sh
```

It backs up every database on the server to `/backups/postgres`; its
settings are at the top of the file.

Optionally sync backups to cloud storage (DigitalOcean Spaces, S3, etc.):

```bash
florist prod rclone:setup
```

## Media files

```bash
# Download media from server to local
florist prod media:download

# Upload local media to server (requires confirmation)
florist prod media:upload
```

Both commands use rsync with compression and progress reporting.

## Service management

```bash
florist prod service:start
florist prod service:stop      # requires confirmation
florist prod service:restart
florist prod service:status
```

### Debugging startup issues

If the application won't start, run it in the foreground to see errors directly:

```bash
florist prod service:debug
```

This stops the systemd service and runs the release binary in foreground mode,
showing all output in your terminal.

## Logs

```bash
# Tail application logs in real-time
florist prod logs:tail

# Show last 100 lines
florist prod logs:show

# Search logs for a pattern
florist prod logs:grep

# Show systemd service logs
florist prod logs:systemd

# Display current environment variables on server
florist prod logs:env
```

## Web server management

### Traefik

```bash
florist prod traefik:setup          # install and configure
florist prod traefik:status         # check service status
florist prod traefik:restart        # restart service
florist prod traefik:upload_config  # upload config files
florist prod traefik:certs          # check SSL certificate status
florist prod traefik:dashboard      # open SSH tunnel to dashboard
```

### nginx

```bash
florist prod nginx:test     # test config for errors
florist prod nginx:reload   # reload config (zero-downtime)
florist prod nginx:restart  # restart service
florist prod nginx:status   # check status
```

## Other commands

```bash
# Block/allow search engine indexing
florist prod noindex:enable
florist prod noindex:disable
florist prod noindex:status

# Clear Brando application cache
florist prod cache:clear

# Show overall status
florist prod status

# Upload configuration files
florist prod bootstrap:upload_etc

# Upload/reload environment variables
florist prod env:upload
florist prod env:reload    # upload + restart service
```

## Typical deployment workflow

### First time setup

```bash
# 1. Configure
florist init
# Edit florist.config.exs with your server details
florist local config:generate

# 2. Create .envrc.<flavor> (e.g. .envrc.prod) — uploaded as .envrc.runtime
# Add to .gitignore

# 3. Bootstrap server (Traefik first: bootstrap checks it is installed)
florist prod traefik:setup    # if using Traefik
florist prod bootstrap

# 4. First deploy
florist prod release:deploy
florist prod db:migrate

# 5. Verify
florist prod status
florist prod logs:tail
```

### Regular deployments

```bash
# Make your changes, commit, then:
florist prod release:deploy
florist prod db:migrate       # only if schema changed
```

### Emergency rollback

```bash
# Instant rollback (blue/green)
florist prod rollback

# Check it worked
florist prod env:status
florist prod logs:tail
```

## Troubleshooting

### Health check fails during deploy

```bash
# Check what's happening
florist prod logs:tail

# Run manually to see startup errors
florist prod service:debug

# Common causes:
# - Missing environment variables in .envrc.runtime
# - Database connection issues
# - Port conflict
```

### Can't connect via SSH

```bash
# Test connection manually
ssh deploy@prod.example.com

# Ensure SSH key is loaded
ssh-add -l

# Add server to known_hosts
ssh-keyscan prod.example.com >> ~/.ssh/known_hosts
```

### Application starts but pages don't load

```bash
# Check web server
florist prod traefik:status    # or nginx:status

# Check active environment
florist prod env:status

# Check environment variables
florist prod logs:env
```
