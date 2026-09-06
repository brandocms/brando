<p align="center">
    <sup><em>A helping hand.</em></sup>
</p>

<p align="center">
<img src="https://raw.githubusercontent.com/brandocms/brando/master/priv/static/brando.png" width="350">
</p>

<p align="center">
    <a href="https://github.com/brandocms/brando/actions/workflows/ci.yml">
      <img src="https://github.com/brandocms/brando/actions/workflows/ci.yml/badge.svg">
    </a>
    <a href="https://coveralls.io/github/brandocms/brando?branch=master">
      <img src="https://coveralls.io/repos/github/brandocms/brando/badge.svg?branch=master">
    </a>
</p>

<p align="center">
*EXPERIMENTAL, NOT RECOMMENDED TO USE BEFORE IN MORE STABLE FORM!*
</p>


## Install

For Brando 0.54, follow [Installation and generators](guides/generators.md).
The walkthrough creates a fresh Phoenix consumer, runs `mix brando.install`,
builds its frontend and admin assets through Vite/Yalc, applies migrations,
initializes languages, and creates the first administrator before seeding.

Keep the Elixir and BrandoJS dependencies on the same revision. The `next` branch
contains the developing 0.54 API; existing applications should follow
[Migrating to 0.54](guides/migrating_to_054.md) instead of rerunning the installer.

## Dependencies

Brando 0.54 processes images through the Image library and Vix/libvips. The
current processor does not require the former `sharp-cli` or `gifsicle` tools.
See [Videos](guides/videos.md) for video processing and provider requirements.

## Languages and content

[Languages and translations](guides/i18n.md) covers Gettext, content languages,
translated pages, alternates, and routes. Continue with [Pages and fragments](guides/pages.md)
and [Navigation](guides/navigation.md) to build a translated site.

## Documentation

Start with the [Brando 0.54 guide index](guides/overview.md) for task-oriented
reading paths. The [coverage audit](https://github.com/brandocms/brando/blob/next/docs/documentation-coverage.md) records
coverage and the validation used for the guide workflows.

- [Migrating to Brando 0.54](guides/migrating_to_054.md) — ordered source,
  database, derived-data, and Gettext upgrade workflow.
- [Blueprint system](guides/blueprints.md) — schema, validation, relations,
  assets, traits, listings, forms, and compile-time boundaries.
- [Blueprint migrations](guides/blueprint_migrations.md) — generation,
  rollback, storage options, legacy snapshots, hand-written migrations, and
  rebaselining.
- [Tenancy and named environments](guides/tenancy_and_environments.md) —
  installer modes, tenant migrations, routing, safe copy and rollback,
  scheduling, and current implementation boundaries.


## Media and deployment

Use [Images, files, and galleries](guides/media.md) for field configuration and
frontend rendering, and [CDN and object storage](guides/cdn.md) for S3-compatible
storage and delivery URLs. Application assets and media have different deployment
paths; see [Deployment](guides/deployment.md) for the release workflow.
