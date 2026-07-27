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

Brando projects are deployed using [Florist](https://github.com/brandocms/florist) (`/Users/trond/dev/elixir/florist`), a zero-downtime deployment tool for Elixir applications.

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
├── log/
├── sql/
└── etc/
```

- Blue and green each run their own systemd service on different ports
- Media is shared: `blue/current/media → ../../media` (symlink created by Florist)
- Traffic switching: Florist updates Traefik/nginx config to point to the new port
- Health check polls the inactive environment before switching traffic
- Keeps last 5 releases per environment, cleans up older ones

### Key implications for Brando development

- **Assets are baked into the release** — `priv/static/` is built during Docker build and included in the tarball. There is no separate asset upload step.
- **Media lives outside the release** — `media/` is persistent on the server and symlinked into the release. Never assume `media/` is inside `priv/`.
- **Blue/green means two running instances** — both share the same database and media directory, but each has its own release with its own `priv/static/`.
- **Rollback is instant** — switch traffic back to the other color. No rebuild needed.
- **`priv/static/` is ephemeral** — it gets rebuilt from scratch in every Docker build. Don't store persistent state there.
