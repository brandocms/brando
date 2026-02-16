# Deployment

Brando projects are deployed using [Florist](https://github.com/brandocms/florist),
a zero-downtime deployment tool for Elixir applications. Florist handles the full
lifecycle: building Docker releases, uploading to servers, managing systemd services,
configuring web servers, database operations, and blue/green deployments.

## Prerequisites

- **Florist** installed locally (`mix escript.install github brandocms/florist`)
- **Docker** for building releases
- **SSH access** to your server with key-based authentication
- A server running Linux with PostgreSQL and either Traefik or nginx

## Quick start

```bash
# 1. Initialize config
florist init

# 2. Set up the server (one-time)
florist prod bootstrap

# 3. Deploy
florist prod release:deploy
```

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

### Runtime environment (.envrc.runtime)

Create `.envrc.runtime` in your project root (add to `.gitignore`). This file is
uploaded to the server and sourced by the systemd service before starting your app:

```bash
export BRANDO_SECRET_KEY_BASE="generate-with-mix-phx-gen-secret"
export BRANDO_DB_URL="postgresql://myapp:password@localhost/myapp_prod"
export BRANDO_URL_SCHEME="https"
export BRANDO_URL_HOST="example.com"
export BRANDO_URL_PORT="443"
export PORT="4000"
export POOL_SIZE="15"
```

Upload it with:

```bash
florist prod env:upload
```

## Bootstrapping a server

Bootstrap sets up everything on a fresh server. Run it once per target:

```bash
florist prod bootstrap
```

This runs through the following steps:

1. Creates the remote system user and group
2. Creates the directory structure on the server
3. Uploads your `media/` and `etc/` directories
4. Creates the PostgreSQL database and user
5. Configures systemd services (one per blue/green environment)
6. Configures the web server (Traefik or nginx)
7. Sets up log rotation
8. Uploads `.envrc.runtime`
9. Sets file permissions and ownership
10. Optionally sets up automated database backups (pgbackup + rclone)

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
