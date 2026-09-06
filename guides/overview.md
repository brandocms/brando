# Brando 0.54 guides

Brando combines Phoenix and Ecto with a Blueprint system for content schemas,
admin forms, and structured content. This index covers the developing **0.54**
API on the `next` branch. Use documentation from your application's Brando
version when maintaining an older installation.

## Start with your task

| I want to… | Start here | Then read |
| --- | --- | --- |
| Upgrade an existing application | [Migrating to 0.54](migrating_to_054.md) | [Blueprint migrations](blueprint_migrations.md) |
| Define a content type and its admin screens | [Blueprints](blueprints.md) | [Querying and mutations](querying.md) |
| Build reusable page content | [Block editor](block_editor.md) | [Villain parser](villain_parser.md) |
| Configure video storage or playback | [Videos](videos.md) | [Blueprint assets](blueprints.md#assets) |
| Control who can read and edit content | [Authorization](authorization.md) | [Sites and environments](tenancy_and_environments.md) |
| Configure a site or publish a static build | [Sites and environments](tenancy_and_environments.md) | [Deployment](deployment.md) |
| Add search and sharing metadata | [Blueprint metadata](blueprints.md#metadata-and-json-ld) | [JSON-LD](jsonld.md) |

For a new installation, start with the installer mode examples in
[Sites and environments](tenancy_and_environments.md). They explain classic,
single-site, and multi-site configuration. A complete fresh-install walkthrough,
including frontend asset setup, is still an open documentation task.

## Schemas and application code

[Blueprints](blueprints.md) explains attributes, relations, assets, traits,
identifiers, URLs, forms, listings, and validation. Start with an existing
application Blueprint when adding a similar content type.

[Blueprint migrations](blueprint_migrations.md) covers generated migrations,
snapshots, rollback, and legacy storage. [Querying](querying.md) covers context
queries and mutations, filtering, ordering, pagination, association loading,
caching, and status/language/deletion options.

## Content and media

The [block editor](block_editor.md) guide introduces modules, refs, vars, and
frontend rendering. [Villain parser](villain_parser.md) covers custom output;
[text styles](villain_text_styles.md) covers reusable rich-text styles.

The [video guide](videos.md) covers upload strategies and providers. Image,
file, and gallery field declarations are introduced in
[Blueprint assets](blueprints.md#assets). Full field-by-field media recipes are
still needed; the presence of an API module does not imply a complete guide.

## Operations and access

[Authorization](authorization.md) explains scoped groups, resource policies,
application enforcement, and the distinction between legacy and group modes.
[Sites and environments](tenancy_and_environments.md) covers installation modes,
routing, content environments, asset sets, and static publication.
[Deployment](deployment.md) covers application deployment through Florist.

## Documentation still being written

Pages/fragments, navigation, live preview, revisions, scheduled publishing,
sitemaps, CDN, language setup, and generators need complete standalone guides.
The older datasource and metadata examples also need review and expansion.
For those areas, consult the relevant API module and the consuming application's
configuration; heading-only guide files are not implementation instructions.

The repository's [documentation coverage audit](https://github.com/brandocms/brando/blob/next/docs/documentation-coverage.md)
records the original #627 topics, the existing source of guidance, and concrete
acceptance criteria for the remaining work. Update the audit when a guide lands.
