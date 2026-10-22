---
name: florist-deploy
description: >
  How Brando projects are deployed with Florist — Docker release build, SSH
  upload, server directory layout, blue/green environments, media symlinks, and
  what that implies for priv/static and asset handling. Use when deploying,
  debugging a release, or reasoning about where assets and media live on a server.
user-invocable: true
---

# Deployment (Florist)

Brando projects are deployed using Florist, a zero-downtime deployment tool for Elixir applications. Its source is the private repository [brandocms/florist](https://github.com/brandocms/florist); a local clone, where there is one, sits next to the main brando checkout as `../florist`. Read the code there when this summary is not enough.

### Deployment flow

```
Local: Docker build → OTP release tarball → Florist uploads via SSH → unpacks on server
```

1. `florist prod release:build` — Docker builds the OTP release (Vite builds CSS/JS inside the container, `mix brando.digest` runs, everything is baked into `priv/static/` inside the release)
2. `florist prod release:copy_from_docker` — extracts tarball from Docker image
3. `florist prod release:upload` — SSH uploads to server
4. `florist prod release:unpack` — extracts to `releases/{version}/`, symlinks `current → releases/{version}`
5. Service restarts via systemd

### Server directory structure (single deployment)

```
/sites/prod/{project_name}/
├── current → releases/x.y.z/   ← symlink to active release
├── releases/
│   ├── 1.0.0/
│   └── 1.1.0/                  ← priv/static/ is inside the release
├── media/                       ← persistent, NOT inside the release
├── site_assets/                 ← beside media/ (see below)
├── sites/                       ← beside media/
├── log/
├── sql/
└── etc/
```

### Server directory structure (blue/green deployment)

```
/sites/prod/{project_name}/
├── blue/
│   ├── current → releases/x.y.z/
│   └── releases/
├── green/
│   ├── current → releases/a.b.c/
│   └── releases/
├── active-environment           ← contains "blue" or "green"
├── media/                       ← shared between blue and green via symlink
├── site_assets/                 ← beside media/, so shared too
├── sites/                       ← beside media/, so shared too
├── log/
├── sql/
└── etc/
```

- Blue and green each run their own systemd service on different ports
- Media is shared: each release links `blue/releases/{version}/media → ../../../media` (symlink created by Florist)
- Traffic switching: Florist updates Traefik/nginx config to point to the new port
- Health check polls the inactive environment before switching traffic
- Keeps last 5 releases per environment, cleans up older ones

### Key implications for Brando development

- **Assets are baked into the release** — `priv/static/` is built during Docker build and included in the tarball. There is no separate asset upload step.
- **Media lives outside the release** — `media/` is persistent on the server and symlinked into the release. Never assume `media/` is inside `priv/`.
- **`site_assets/` and `sites/` sit beside the shared media** — `Brando.Tenant.Storage.media_parent/0` follows the release's `media` link (only when `RELEASE_ROOT` is set, i.e. running as a release), so asset sets and SSG builds land in the base directory, not the release, unless `:site_assets_path`/`:sites_path` are configured.
- **Blue/green means two environments** — both share the same database and media directory, but each has its own release with its own `priv/static/`. Both run during a deploy until traffic switches; then the old one is stopped.
- **Rollback is instant** — switch traffic back to the other color. No rebuild needed. The schema stays as the newer release left it unless the rollback passes `--restore-db`.
- **A deploy does not migrate** — `florist prod release:deploy` builds, uploads and switches; migrations run separately with `florist prod db:migrate`.
- **Blue/green needs `plug Brando.Plug.Health`** in the endpoint, before the router: without it the health check never passes and the switch never happens.
- **No `PORT=` in `.envrc.<flavor>`** — it is uploaded as `.envrc.runtime` and sourced after systemd sets each colour's port, so a `PORT=` line would override it (see `guides/deployment.md`).
- **`priv/static/` is ephemeral** — it gets rebuilt from scratch in every Docker build, and `.dockerignore` keeps the local one out of the build context. Keep static files in `assets/frontend/public/`, which Vite copies there; a file put in `priv/static/` by hand works in development and is missing from the release.
