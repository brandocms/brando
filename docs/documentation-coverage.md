# Documentation coverage and remaining work

Issue [#627](https://github.com/brandocms/brando/issues/627) is now scoped to the
0.54 documentation entry points and this coverage baseline. It is not an
unbounded promise to document every subsystem in one PR.

Audit baseline: `next` at `67191f96d`, 6 September 2026. This records guide content,
not the existence of a Markdown filename or an ExDoc module. The reader entry
point is [Brando 0.54 guides](../guides/overview.md).

## Completion criteria for the rescoped issue

- Account for all 23 top-level topics in the original issue, including redirects
  under SEO.
- Distinguish usable guides, partial coverage, heading-only stubs, and missing
  dedicated guides.
- Publish a task-oriented index from both README and ExDoc.
- State remaining deliverables and their verification requirements; do not mark
  a topic complete merely because its file exists.

## Original topic inventory

**Guide** means substantial usable guidance exists, without claiming an exhaustive
audit of every example. **Partial** means selected APIs or recipes are covered.
**Stub** means the dedicated file has only a heading. **Missing** means no dedicated
guide exists, though source/API documentation may be available.

| Original topic | Coverage at baseline | Existing guidance and remaining deliverable |
| --- | --- | --- |
| Datasources | Partial | [Datasource examples](../guides/datasources.md), [Blueprint DSL](../guides/blueprints.md#datasources). Cover list/selection/single callback contracts, ordering, vars, runtime context, and invalidation with current examples. |
| Villain | Guide | [Block editor](../guides/block_editor.md), [parser](../guides/villain_parser.md), [text styles](../guides/villain_text_styles.md). Keep both Liquex and HEEx examples in sync with rendering tests. |
| Identity | Partial | [JSON-LD identity](../guides/jsonld.md#identity-type-specific-fields). Add translated identity setup, links, frontend access, defaults, and cache refresh. Source: `lib/brando/sites/identity.ex`, `lib/brando/sites.ex`. |
| SEO and redirects | Partial | [Permalink redirects](../guides/blueprints.md#permalink-redirects) covers automatic redirects. Add the SEO configuration form, fallback values, manual patterns/captures, language scoping, and redirect testing. Source: `lib/brando/sites/seo.ex`, `lib/brando/sites/redirects.ex`. |
| Sitemap | Stub | `guides/sitemaps.md`. Explain sitemap DSL, publication/status filtering, language URLs, generation schedule, storage, and an output check. Source: `lib/brando/sitemap.ex`. |
| CDN | Stub | `guides/cdn.md`. Cover field/default S3 settings, image/file upload flow, media URL versus object key, tenant paths, and verification. Source: `lib/brando/cdn/cdn.ex`. |
| Users | Partial | [Authorization](../guides/authorization.md) covers access and group management. Add account creation, login eligibility, sessions, deactivation, and deletion/content transfer. Source: `lib/brando/users/users.ex`. |
| Pages/Sections | Stub | `guides/pages.md`. Define current pages, hierarchy, templates, vars, fragments, homepage URLs, breadcrumbs, and frontend rendering. Source: `lib/brando/pages/pages.ex`. |
| Generator | Stub | `guides/generators.md`. Give a fresh-install path and task catalog with generated files, follow-up commands, and overwrite boundaries. Source: `lib/mix/tasks/`. |
| Authorization | Guide | [Authorization](../guides/authorization.md). Covers opt-in groups, legacy compatibility, scopes, policies, enforcement, and testing. |
| META schemas | Partial | [Meta](../guides/meta.md), [Blueprint metadata](../guides/blueprints.md#metadata-and-json-ld). Correct stale callback examples and show a complete controller/layout result with fallbacks. |
| JSONLD schemas | Guide | [JSON-LD](../guides/jsonld.md). Covers graph relationships, controller integration, supported schema fields, and custom schemas. |
| Image fields | Partial | [Blueprint assets](../guides/blueprints.md#assets) and internal [upload architecture](UPLOADER.md). Add a public recipe for field configuration, Image/Vix processing, focal crop, sizes/srcset, and rendering. |
| File fields | Partial | [Blueprint assets](../guides/blueprints.md#assets), internal [upload architecture](UPLOADER.md). Add allowed types/limits, replacement, download URLs, and persisted field behavior. |
| Live Preview | Stub | `guides/live_preview.md`. Explain configuration, unsaved data, preloads, assigns, invalidation, independent targets, and sharing. Implementation is tracked in [#2485](https://github.com/brandocms/brando/issues/2485); update coverage when its guide lands. |
| Soft delete | Partial | [Query status/deletion](../guides/querying.md#status-language-and-soft-deletion), [traits](../guides/blueprints.md#traits). Add delete/restore, obfuscated unique fields, conflicts, and purge behavior. Source: `lib/brando/traits/soft_delete.ex`. |
| Sequence | Partial | [Traits](../guides/blueprints.md#traits), [ordering](../guides/querying.md#ordering). Add append/strict semantics, stable ordering, nested rows, and authorized reorder. Source: `lib/brando/traits/sequenced.ex`. |
| Gallery | Partial | [Blueprint assets](../guides/blueprints.md#assets), internal [upload architecture](UPLOADER.md). Add mixed image/video configuration, ordering, usage overrides, independent duplication, and rendering. |
| Status | Partial | [Query status/deletion](../guides/querying.md#status-language-and-soft-deletion). Explain draft/pending/published/disabled values as defined by the current status type, required-field behavior, and publication side effects. Source: `lib/brando/traits/status.ex`. |
| Scheduled publishing | Stub | `guides/scheduled_publishing.md`. Separate publishing an entry status from scheduling a revision, including time zones, cancellation, retries, permissions, and tenant context. Source: `lib/brando/publisher.ex`. |
| I18n | Stub | `guides/i18n.md`. Explain admin/content languages, Gettext, translated entries/alternates, route scoping, and frontend helpers. Existing migration guidance covers Gettext upgrades only. |
| Navigation | Stub | `guides/navigation.md`. Give a complete menu, nested item, identifier-backed link, language lookup, rendering, and cache refresh example. Source: `lib/brando/navigation/navigation.ex`. |
| Query | Guide | [Querying](../guides/querying.md). Covers generated contexts, options, association loading, caching, revisions, and mutations. |

Other existing guides cover Blueprint migrations, tenancy/environments, videos,
and deployment. `guides/revisions.md` is also a heading-only stub, although it
was not named separately in the original checklist. In total, nine of the 23
guide files present at this baseline are heading-only stubs.

## Prioritized writing packages

Each package is suitable for a focused follow-up PR. These are remaining work,
not completed acceptance criteria for the current implementation.

1. **Onboarding and everyday content:** complete generators/install, pages and
   fragments, navigation, and I18n. Walk through a fresh consumer setup, one
   translated page and menu, and a saved/reloaded content edit. Replace the
   README's historical shell-installer path with the verified 0.54 workflow.
2. **Media and delivery:** public image, file, gallery, and CDN recipes. Use the
   current Image/Vix processor, current video providers, and the sticky upload
   manager; verify consumer rendering and distinguish local paths from CDN keys.
3. **Preview and publishing:** live preview (#2485), revisions, scheduled
   publishing, and status lifecycle. Show unsaved previews, selected revisions,
   cancellation, invalid saves, and execution in the intended environment.
4. **Site output and lifecycle:** identity, SEO/manual redirects, sitemaps,
   datasource expansion, metadata correction, soft-delete/restore, and sequence.
   Verify rendered output, language boundaries, and dependency/cache invalidation.
5. **Account workflows:** extend authorization guidance with actual user session,
   deactivation, and content-transfer behavior, with a restricted-account example.

A guide is ready when it states prerequisites, uses current public APIs, includes
one complete practical example, explains its important failure/empty state, and
has its commands or example behavior checked against the consumer or focused
tests. API inventories and internal agent skills complement these guides; they
do not replace the application developer's walkthrough.

## Maintaining the index

Keep `guides/overview.md`, ExDoc's extras in `mix.exs`, and this table aligned when
a guide lands. Build docs with `mix docs`, check local Markdown links and anchors,
and inspect the generated overview. Record unresolved baseline warnings rather
than describing a warning-filled build as warning-free.
