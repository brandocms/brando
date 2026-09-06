---
name: brando-sites
description: Work on Brando identity, global sets, SEO settings, redirects, metadata, JSON-LD, and their caches. Also use when resolving the distinction between tenant sites/environments and translated site content.
user-invocable: true
---

# Site content, metadata, and caches

Paths are repository-relative. `lib/brando/sites.ex` owns identity, SEO, global
sets, and preview context queries/mutations. `lib/brando/sites/site.ex` instead
represents a tenant site in the shared installation registry; these are different
kinds of records. Read `guides/tenancy_and_environments.md` for registry operations.

## Shared content and invalidation

- `lib/brando/sites/identity.ex` holds translated identity content, including
  links, meta, and type-specific embedded configuration. It is not the account
  or authorization site membership record.
- `lib/brando/sites/global_set.ex` owns ordered typed vars. The globals cache
  groups language, set key, and variable key; values are Var records with type-
  specific fields/associations, not universally strings.
- Read `lib/brando/cache/globals.ex`, `lib/brando/cache/identity.ex`, and
  `lib/brando/cache/seo.ex` before changing cache shape. Use the Brando cache
  boundary so tenant/environment namespacing remains intact.
- Site mutations run cache refresh and Villain dependency invalidation callbacks.
  Confirm both when a shared value changes but rendered content stays stale.
  `lib/brando/villain/render_invalidation.ex` covers HEEx and Liquid references.

## SEO and structured data

- `lib/brando/sites/seo.ex` stores per-language defaults and redirect entries;
  `lib/brando/sites/redirects.ex` handles redirect matching/testing and permalink
  additions. Test language scoping, captures, and existing redirect replacement.
- Metadata starts in the Blueprint `meta_schema`; controller helpers in
  `lib/brando/plugs/html.ex` populate the conn for layout rendering. Read
  `guides/meta.md` alongside the actual helper signatures before copying examples.
- `lib/brando/json_ld/json_ld.ex` builds the connected JSON-LD graph. The content
  DSL is validated separately under `lib/brando/blueprint/json_ld/`.
  Read `guides/jsonld.md` for identity, WebSite, WebPage, breadcrumb, and content
  relationships. Keep stable `@id` links and escaping when changing serialization.
- Rendering a content entity does not replace the site identity or WebPage node.
  Custom schemas need the actual fields and `build/1` contract expected by the DSL.

## Verification

Use `test/brando/sites/globals_test.exs`, `test/brando/sites/redirects_test.exs`,
`test/brando/jsonld/render_test.exs`, and `test/brando/tenant_cache_test.exs`.
Check the final rendered metadata/JSON-LD as well as the cached intermediate
value; include two languages or tenant prefixes when changing key construction.
Read [pages](../brando-pages/SKILL.md) for hierarchy/URI changes and
[media](../brando-media/SKILL.md) for identity or meta-image processing.
