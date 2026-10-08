---
name: brando-deploy
description: Deploy this Brando site with Florist, or debug a deployed release. Use when building or uploading a release, running remote migrations, rolling back, switching blue/green environments, or reasoning about where static assets and media live on the server.
---

# Deploying a Brando site with Florist

Brando sites deploy with [Florist](https://github.com/brandocms/florist): a
Docker build produces an OTP release, which is uploaded over SSH and
activated, optionally blue/green.

## Read first

- `deps/brando/usage-rules/deployment.md`.
- `deps/brando/guides/deployment.md` for commands, configuration and
  troubleshooting.

## Where things live

- Static assets are built inside the Docker build and baked into the release's
  `priv/static/`. There is no separate asset upload, and `priv/static/` is
  rebuilt from scratch on every build: never keep state there.
- Media live in the persistent `media/` directory on the server, outside the
  release, and are symlinked into it. Blue and green share the same media and
  database.
- Rolling back blue/green switches traffic to the other environment; nothing
  is rebuilt.

## Before deploying

- Run `mix brando.doctor` and fix what it reports.
- Commit everything; the build uses the committed source.
- Review pending migrations, and know how the deploy runs them
  (see "Running migrations" in the guide).
- Keep `.envrc.<flavor>` out of git; it is uploaded as the runtime
  environment.
