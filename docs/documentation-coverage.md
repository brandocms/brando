# Brando 0.54 documentation coverage

The entry-point audit in [#627](https://github.com/brandocms/brando/issues/627)
identified missing application-developer guidance. The remaining writing packages
are completed by [#2771](https://github.com/brandocms/brando/issues/2771), with live
preview delivered separately in [#2770](https://github.com/brandocms/brando/pull/2770).
The reader entry point is [Brando 0.54 guides](../guides/overview.md).

Coverage reviewed on 6 September 2026 against the developing 0.54 source. A guide
here means practical instructions with prerequisites, current APIs, an example,
and relevant failure states. It does not imply every provider or deployment
combination has been exercised against an external service.

## Original topic inventory

All 23 topics from the original issue now have developer guidance. Revisions,
which were not listed separately in that checklist, also have a complete guide.

| Original topic | Guide | Scope |
| --- | --- | --- |
| Datasources | [Datasources](../guides/datasources.md) | List/selection/single contracts, ordering, vars, request context, metadata, invalidation |
| Villain | [Block editor](../guides/block_editor.md), [parser](../guides/villain_parser.md), [text styles](../guides/villain_text_styles.md) | Modules, refs, vars, Liquex/HEEx rendering, rich text |
| Identity | [Identity and SEO](../guides/identity_and_seo.md) | Translated defaults, contact details, links, frontend access, cache/render refresh |
| SEO and redirects | [Identity and SEO](../guides/identity_and_seo.md), [permalink redirects](../guides/blueprints.md#permalink-redirects) | Fallbacks, robots, manual patterns/captures, language and fallback-controller behavior |
| Sitemap | [Sitemaps](../guides/sitemaps.md) | Public filters, struct-preserving URL queries, generation, XML output, schedule and storage |
| CDN | [CDN](../guides/cdn.md) | Global/field S3 settings, upload transports, media URLs versus object keys, tenant boundaries |
| Users | [Users and sessions](../guides/users.md) | Creation, restricted accounts, login eligibility, tokens, deactivation, content transfer |
| Pages/Sections | [Pages and fragments](../guides/pages.md) | Context writes, public routes, templates, vars, homepage URI, hierarchy, breadcrumbs, fragments |
| Generator | [Installation and generators](../guides/generators.md) | Fresh consumer through first login, asset builds, migration/seeding order, task catalog and overwrite boundaries |
| Authorization | [Authorization](../guides/authorization.md) | Modes, scoped groups, policies, application enforcement and revocation |
| META schemas | [Page metadata](../guides/meta.md) | Whole-entry callbacks, fallbacks, locale, controller/title/layout integration and output checks |
| JSONLD schemas | [JSON-LD](../guides/jsonld.md) | Graph relationships, supported identity fields, controllers, custom schemas |
| Image fields | [Images, files, and galleries](../guides/media.md#configure-a-cover-image) | Image/Vix processing, focal crop, formats, sizes/srcset, captions and alt text |
| File fields | [Images, files, and galleries](../guides/media.md#add-a-pdf-download) | MIME/size limits, replacement versus association selection, download URLs and headers |
| Live Preview | [Live preview](../guides/live_preview.md) | Unsaved data, preloads/assigns, cache invalidation, independent targets, sharing |
| Soft delete | [Content lifecycle](../guides/content_lifecycle.md#deletion-and-restoration) | Authorized delete/restore, obfuscated unique fields, collisions, purge and shared media |
| Sequence | [Content lifecycle](../guides/content_lifecycle.md#choose-sequence-behavior) | Append/strict modes, language scope, stable ordering, authorized reorder and nested rows |
| Gallery | [Images, files, and galleries](../guides/media.md#add-an-ordered-mixed-gallery) | Mixed media configuration, placement overrides, ordering, rendering, independent duplication |
| Status | [Content lifecycle](../guides/content_lifecycle.md#status-and-valid-publication) | Four status values, required-field validation, public queries and mutation side effects |
| Scheduled publishing | [Scheduled publishing](../guides/scheduled_publishing.md) | Entry dates versus frozen revisions, cancellation, time zones, retries, permissions and environments |
| I18n | [Languages and translations](../guides/i18n.md) | Admin/content languages, Gettext, translated entries, alternates, routes and helpers |
| Navigation | [Navigation](../guides/navigation.md) | Translated menus, link identifiers, nesting, rendering, ordering and cache refresh |
| Query | [Querying](../guides/querying.md) | Contexts, filters, ordering, pagination, association loading, caching and mutation behavior |

Additional guides cover [Revisions](../guides/revisions.md), Blueprint migrations,
tenancy/environments, videos, deployment, and migration to 0.54. There are no
heading-only guide stubs left in this inventory.

## Verification for the remaining writing packages

The guide review followed the implementation and focused behavior checks, rather
than using internal skill files as evidence that public documentation existed.

| Package | Verification |
| --- | --- |
| Onboarding and everyday content | Generated a disposable Phoenix consumer; compiled it, migrated an empty PostgreSQL database through Brando 170, built both Vite consumers using matching Yalc source, seeded and rendered English/Norwegian homepages. `test/brando/guides/workflows_test.exs` verifies seed output, page save/reload, nested translated menus, and public query filtering. Installer tests verify every maintained migration is copied exactly once in numeric order. Existing pages, alternates, locale and plug tests cover routing/language behavior. |
| Media and delivery | Focused Vix processor, sizing, image URL/config, file replacement, mixed-gallery config/duplication, and CDN tests. Reviewed UploadManager transport/ownership contracts against source and the upload architecture. External S3/video-provider accounts were not used; deployment credentials, remote headers, webhooks and delivery URLs require the consumer checks described in the guides. |
| Preview and publishing | Existing revision tests check snapshot/restore behavior; authorization operation tests cover publication and schedule boundaries; tenant-job tests exercise captured environment context. Reviewed scheduler cancellation, retries and retention against the publisher/revision/worker implementations. Live-preview configuration and target checks belong to #2770. |
| Site output and lifecycle | Focused metadata extraction/rendering, redirects, sitemap XML, datasource, soft-delete and permission tests. New workflow tests verify that public URL queries retain Blueprint structs and exclude drafts and entries without URLs. Reviewed translated cache callbacks, datasource invalidation, sequence and purge code. |
| Account workflows | Users and authorization group/operation tests, plus a password component regression for Blueprint HTML-safe labels. Reviewed login/token/logout, deactivation and content-transfer implementations; completed the fresh consumer’s initial password setup and a page save/reopen in a headless browser. |

The fresh-consumer exercise exposed prerequisites that documentation alone could
not fix: the installer's frozen/incomplete migration set, a removed migration API,
Vite target/dependency mismatches, Swoosh's absent default HTTP client, stale seed
fields and missing initial rendering, and the first-login password label crash.
These fixes accompany the walkthrough and have focused regressions where relevant.

The focused checks above total **187 passing tests** (83 content/output checks,
87 media/access checks, 9 installer/workflow checks, and 8 input-component checks).
The isolated test database needed the latest authorization migration before the
permission tests could run; those affected tests passed after it was applied.

## Documentation checks and maintenance

Keep `guides/overview.md`, ExDoc extras/groups in `mix.exs`, and this table aligned.
Build with `mix docs --warnings-as-errors`, validate local Markdown links and
anchors, and inspect the generated overview. For this update, the strict ExDoc
build passed; all 160 local links/guide anchors and 28 extras matched; all 48
Elixir examples in the 14 completed guides parsed; desktop/mobile ExDoc views
were inspected in a headless browser. The README now points at the Mix
installer walkthrough rather than the historical shell installer.

Consumer asset builds can report PostCSS configuration and Vite chunk-size
warnings; successful compilation is not a claim that those baseline warnings
were eliminated. No root framework asset build is used as a consumer validation
gate. Live remote providers and production deployment remain consumer-specific
checks, not results implied by the local documentation build.
