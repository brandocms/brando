<p align="center">
    <sup><em>A helping hand.</em></sup>
</p>

<p align="center">
<img src="https://raw.githubusercontent.com/brandocms/brando/main/priv/static/brando.png" width="350">
</p>

<p align="center">
    <a href="https://github.com/brandocms/brando/actions/workflows/ci.yml">
      <img src="https://github.com/brandocms/brando/actions/workflows/ci.yml/badge.svg">
    </a>
    <a href="https://codecov.io/gh/brandocms/brando">
      <img src="https://codecov.io/gh/brandocms/brando/branch/main/graph/badge.svg">
    </a>
</p>

Brando is a content management system for Phoenix applications. You describe
content types as Blueprints, and Brando generates their schemas, migrations,
queries and LiveView admin screens. Pages are built in a block editor from
reusable modules.

> **Brando is pre-1.0.** APIs change between minor versions. Each release comes
> with migration tasks and an upgrade guide.

## Features

- **Content modelling** — [Blueprints](guides/blueprints.md) declare attributes,
  relations, assets, listings and forms;
  [Blueprint migrations](guides/blueprint_migrations.md) generate the storage.
- **Block editor** — [modules, refs and vars](guides/block_editor.md), rich text,
  [datasources](guides/datasources.md), and module definitions you can
  [export and edit as files](guides/module_definitions.md).
- **Editing workflow** — [live preview](guides/live_preview.md) of unsaved
  changes, [revisions](guides/revisions.md),
  [scheduled publishing](guides/scheduled_publishing.md) and an
  [activity log](guides/activity.md).
- **Media** — [images, files and galleries](guides/media.md) processed through
  Image/libvips, [videos](guides/videos.md), and
  [S3-compatible storage with CDN delivery](guides/cdn.md).
- **Languages** — [translated entries, routes and alternates](guides/i18n.md),
  with [navigation](guides/navigation.md) that follows the active language.
- **Search and sharing** — [SEO and redirects](guides/identity_and_seo.md),
  [metadata](guides/meta.md), [JSON-LD](guides/jsonld.md),
  [sitemaps](guides/sitemaps.md) and [content scoring](guides/content_seo.md).
- **Operations** — [users](guides/users.md),
  [scoped authorization](guides/authorization.md),
  [multiple sites and content environments](guides/tenancy_and_environments.md),
  [content import and export](guides/content_transfer.md) and
  [deployment with Florist](guides/deployment.md).

## Install

Brando 0.55 needs Elixir 1.18 or newer, Phoenix 1.8, LiveView 1.2 and
PostgreSQL. Images are processed with Image and Vix/libvips. `sharp-cli` and
`gifsicle` are no longer used. The admin assets are built with Node.js and pnpm.

Follow [Installation and generators](guides/generators.md). It creates a
Phoenix application, runs `mix brando.install`, builds the frontend and admin
assets through Vite/Yalc, runs the migrations, sets up languages and creates the
first administrator.

Keep the Elixir and BrandoJS dependencies on the same revision.

## Upgrading

0.55 is developed on `main`. The `0.54` branch only receives bug fixes.

Projects on 0.54 run `mix brando.migrate55`. Projects still on 0.53 run
`mix brando.migrate54` first. The complete steps, covering source, database,
derived data and Gettext, are in
[Migrating from 0.53 or 0.54](guides/migrating_from_053.md). Breaking changes
are listed in the [changelog](https://github.com/brandocms/brando/blob/main/CHANGELOG.md).

Projects already on 0.55 pick up new Brando migrations with
`mix brando.gen.migrations`, then run them with `mix brando.migrate`, followed
by `mix brando.migrate --tenants` when they have named environments.

## Documentation

Start with the [guide index](guides/overview.md). It suggests what to read for
each task, such as starting a site, defining a content type or deploying.

## License

[MIT](https://github.com/brandocms/brando/blob/main/LICENSE.md)
