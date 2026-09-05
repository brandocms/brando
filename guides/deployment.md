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
(add them to `.gitignore`). Florist reads `.envrc.<flavor>` locally and uploads
it to the server as `.envrc.runtime`, which the systemd service sources before
starting your app. The `.runtime` name only ever exists on the server.

```bash
export BRANDO_SECRET_KEY_BASE="generate-with-mix-phx-gen-secret"
export BRANDO_DB_URL="postgresql://myapp:password@localhost/myapp_prod"
export BRANDO_URL_SCHEME="https"
export BRANDO_URL_HOST="example.com"
export BRANDO_URL_PORT="443"
export POOL_SIZE="15"
```

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

The database password in `BRANDO_DB_URL` must match `FLORIST_DB_PASSWORD_PROD`,
since florist uses the latter to create the database user that your app then
authenticates as.

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
> pull the old server's dump down, restore it locally, run `mix ecto.migrate`
> so the schema matches the release you are about to deploy, and only then
> bootstrap. Step 9 then ships the migrated production data for you.
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
├── log/
├── sql/
└── etc/
```

Key points:

- Blue and green each run their own systemd service on separate ports
- Media is shared via symlinks (Florist creates these automatically)
- Only the `active-environment` file and web server config determine which
  environment receives traffic
- Florist keeps the last 5 releases per environment and cleans up older ones

## The Docker build

Brando projects use a multi-stage Dockerfile that builds the OTP release:

```
Stage 1: deps          → mix deps.get
Stage 2: compile_deps  → mix deps.compile
Stage 3: compile_app   → mix compile
Stage 4: assets_backend  → yarn build (admin Svelte app)
Stage 5: assets_frontend → yarn build (site CSS/JS via Vite + EuropaCSS)
Stage 6: digest        → mix brando.digest (fingerprint static assets)
Stage 7: release       → mix release (create OTP release tarball)
```

Assets (CSS, JS) are built inside the Docker container and baked into the release
at `priv/static/`. There is no separate asset upload step — everything ships as
one tarball.

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

# 2. Create .envrc.runtime
# Add to .gitignore

# 3. Bootstrap server
florist prod bootstrap
florist prod traefik:setup    # if using Traefik

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
