# Brando 0.54 guides

Brando combines Phoenix and Ecto with a Blueprint system for content schemas,
admin forms, and structured content. These guides cover the developing **0.54**
API on the `next` branch. Use documentation from your application's Brando
version when maintaining an older installation.

## Start with your task

| I want to… | Start here | Then read |
| --- | --- | --- |
| Start a new site | [Installation and generators](generators.md) | [Pages and fragments](pages.md) |
| Upgrade an existing application | [Migrating to 0.54](migrating_to_054.md) | [Blueprint migrations](blueprint_migrations.md) |
| Define a content type and its admin screens | [Blueprints](blueprints.md) | [Querying and mutations](querying.md) |
| Build translated pages and menus | [Languages and translations](i18n.md) | [Navigation](navigation.md) |
| Build reusable page content | [Block editor](block_editor.md) | [Datasources](datasources.md) |
| Render images, downloads, or a gallery | [Images, files, and galleries](media.md) | [Videos](videos.md), [CDN](cdn.md) |
| Preview an edit or schedule a release | [Live preview](live_preview.md) | [Revisions](revisions.md), [Scheduled publishing](scheduled_publishing.md) |
| Set up search and sharing output | [Identity, SEO, and redirects](identity_and_seo.md) | [Metadata](meta.md), [Sitemaps](sitemaps.md) |
| Delete, restore, or reorder content | [Content lifecycle](content_lifecycle.md) | [Querying](querying.md) |
| Manage accounts and editing permissions | [Users and sessions](users.md) | [Authorization](authorization.md) |
| Configure environments or publish a static build | [Sites and environments](tenancy_and_environments.md) | [Deployment](deployment.md) |

## Your first working site

Start with [Installation and generators](generators.md): create a fresh consumer,
build both asset projects, migrate, initialize languages, and create an
administrator before seeding. Verify the public homepage and an editor save.

Next, use [Pages and fragments](pages.md) for URLs, templates, page vars, and shared
content. [Languages and translations](i18n.md) connects translated entries to
routes and alternate URLs; [Navigation](navigation.md) turns those entries into
menus that follow the active language.

## Build a content model

[Blueprints](blueprints.md) explains attributes, relations, assets, traits,
identifiers, URLs, forms, listings, and validation. [Blueprint migrations](blueprint_migrations.md)
covers generated storage and snapshots. [Querying](querying.md) covers context
queries and mutations, filtering, ordering, pagination, preloads, and caching.

The [block editor](block_editor.md) guide introduces modules, refs, and vars.
[Villain parser](villain_parser.md) covers custom output, [text styles](villain_text_styles.md)
covers rich text, and [Datasources](datasources.md) connects modules to queried or
selected entries, including ordering and invalidation.

## Edit, preview, and publish

Use [Live preview](live_preview.md) to render unsaved content and configure one or
more destinations. [Revisions](revisions.md) explains saving, comparing, loading,
and restoring snapshots. [Scheduled publishing](scheduled_publishing.md) separates
entry publication dates from revision releases, including cancellation and job
execution. [Content lifecycle](content_lifecycle.md) covers status, soft deletion,
restoration, purge, and sequence ordering.

## Deliver media and public output

[Images, files, and galleries](media.md) gives complete field and rendering recipes.
[Videos](videos.md) covers providers and playback; [CDN](cdn.md) distinguishes local
paths, object keys, and public delivery URLs.

[Identity, SEO, and redirects](identity_and_seo.md) configures translated defaults,
links, robots output, and manual redirect rules. [Metadata](meta.md) adds page-level
search and sharing tags, [JSON-LD](jsonld.md) adds structured data, and
[Sitemaps](sitemaps.md) generates XML from public content.

## Operate the application

[Users and sessions](users.md) covers account creation, login, deactivation, and
content transfer. [Authorization](authorization.md) explains scoped groups,
resource policies, application enforcement, and legacy compatibility.
[Sites and environments](tenancy_and_environments.md) covers installation modes,
routing, content environments, asset sets, and static publication.
[Deployment](deployment.md) covers releases through Florist.

The repository's [documentation coverage record](https://github.com/brandocms/brando/blob/next/docs/documentation-coverage.md)
maps the original documentation topics to guides and records how the remaining
0.54 guide workflows were checked.
