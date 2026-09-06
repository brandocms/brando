# Identity, SEO settings, and redirects

Identity describes the organization or person behind a site. SEO settings provide
page-metadata fallbacks, robots text, and manual redirects. Both are stored per
content language and, when tenancy is enabled, inside the selected environment.
They are separate from a multi-site installation's site registry record.

This guide assumes configured [languages](i18n.md), migrated identity/SEO tables,
and an account allowed to edit site settings.

## Set up a translated identity

Open **Configuration → Identity**, select English, and enter the organization's
name, contact details, logo, and title prefix/postfix. Choose the structured-data
type and fill its relevant fields; [JSON-LD](jsonld.md#identity-type-specific-fields)
explains what each type contributes. Add a named social link, then save and reload.
Repeat for Norwegian with its translated display text.

For a new language, create defaults once in that environment:

```elixir
Brando.Sites.create_default_identity("en")
Brando.Sites.create_default_seo("en")
Brando.Cache.Identity.set()
Brando.Cache.SEO.set()
```

These helpers insert defaults; they are not idempotent upserts. Check for existing
records first when writing a repeatable seed. The identity contains placeholder
contact/title values that must be replaced before launch. The interactive
`mix brando.gen.languages` task creates the same defaults and prints the language
configuration to add. A newly created row does not automatically refresh every
already-warm cache; the explicit `set/0` calls above do.

Update an existing record through the context so its cache and content consumers
are refreshed:

```elixir
{:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})

{:ok, identity} = Brando.Sites.update_identity(identity, %{
  type: "Organization",
  name: "Studio Example",
  email: "hello@example.com",
  title_prefix: "",
  title_postfix: " | Studio Example",
  links: [%{name: "Instagram", url: "https://www.instagram.com/example/"}]
}, current_user)
```

Embed updates replace the submitted collection, so preserve existing links when
adding one programmatically. In the admin, the normal form handles that collection.

## Use it in the frontend

Run the identity plug after locale and tenant resolution:

```elixir
plug :put_locale
plug Brando.Plug.Tenant
plug Brando.Plug.Identity
```

The current-language identity becomes `@identity`. A small footer can handle
missing configuration without showing placeholder content:

```heex
<footer>
  <p>{Map.get(@identity, :name, "")}</p>
  <a :if={email = Map.get(@identity, :email)} href={"mailto:" <> email}>{email}</a>
  <a :for={link <- Map.get(@identity, :links, [])} href={link.url}>{link.name}</a>
</footer>
```

For code outside a request, `Brando.Cache.Identity.get("en")` returns that
language's record, or `%{}` if absent. It does not fall back to another language.
`Brando.Sites.render_identity("en", :name)` is the scalar convenience API.
Use the cached record's `links` collection for named-link lookup; older unscoped
identity helpers are not a recipe for multilingual output.

Identity updates refresh the cache and enqueue block content referencing identity,
configs, or links for rendering. Direct `Repo` writes skip those callbacks. During
a controlled import, refresh the cache in each affected environment and invoke
`Brando.Sites.update_villains_referencing_identity({:ok, identity})` afterwards.

## Configure metadata fallbacks and robots

Open **Configuration → SEO**, choose the language, and set the fallback title,
description, and sharing image. Use a real public **Base URL** and review Robots.
The page's [metadata schema](meta.md) supplies specific values first; missing
values are filled from these settings when metadata renders.

```elixir
{:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})

{:ok, seo} = Brando.Sites.update_seo(seo, %{
  fallback_meta_title: "Studio Example",
  fallback_meta_description: "Architecture and interiors by Studio Example.",
  base_url: "https://example.com",
  robots: "User-agent: *\nDisallow: /admin/\nSitemap: https://example.com/sitemaps/sitemap.xml"
}, current_user)
```

`Brando.Cache.SEO.get(language)` returns an empty SEO struct if the language has
no row. That keeps lookups possible but does not provide meaningful metadata.
SEO context updates refresh the SEO cache; they do not automatically rerender
arbitrary block templates or rebuild a static deployment. Rebuild those outputs
when they embed settings at build time.

The generated `page_routes()` exposes `/robots.txt`. It returns the current
language's configured robots text, or a default that disallows `/admin/`. Include
the sitemap line explicitly. It does not add an environment-specific crawl block
for you; inspect the intended deployment and configure its policy explicitly.
The base URL field does not reconfigure Phoenix's endpoint or your DNS. Set the
endpoint URL correctly
for canonical URLs, metadata, and [sitemap generation](sitemaps.md).

## Add a manual redirect

In the SEO form's Redirects section, add a rule in the language of the incoming
request. Rules are tried in order; the first match wins. For a pattern:

| Field | Value |
| --- | --- |
| From | `/old-news/:slug` |
| To | `/news/:slug` |
| Code | `301` |

A colon-prefixed path segment captures lowercase letters, digits, hyphens, and
underscores; matching named segments in the destination are replaced. The source
is a regular-expression pattern anchored at the beginning. Use `$` to make a
literal rule end at the requested path, for example `/old-about$`; without it,
`/old-about/team` may match too. For a capture that must end the path, use an
explicit named regex such as `/old-news/(?<slug>[a-z0-9_-]+)$`. The shorthand
`:slug` parser treats the whole segment as its name, so do not append `$` to the
shorthand name. Keep patterns valid; an invalid regex raises during matching.

Test a saved rule from the application shell:

```elixir
{:ok, {:redirect, {"/news/launch", 301}}} =
  Brando.Sites.Redirects.test_redirect(["old-news", "launch"], "en")

{:error, {:redirects, :no_match}} =
  Brando.Sites.Redirects.test_redirect(["unrelated"], "en")
```

The helper takes path segments and an explicit language, not a full URL or query
string. A Norwegian URL may include `no` in the actual incoming path; write and
test the rule against that path rather than assuming the language prefix is
stripped for you.

The standard fallback controller checks these rules when content lookup returns
not found. A still-existing page therefore takes precedence over a manual rule;
this is not an unconditional redirect plug. Code `410` produces a Gone response
through that fallback rather than a Location redirect.

For permalink changes, the admin can offer a confirmed automatic redirect. That
flow stores an escaped exact source, removes stale exact rules on the new URL,
and avoids simple rename-back loops. See [Blueprint permalink redirects](blueprints.md#permalink-redirects).
Do not recreate those internal rules by submitting arbitrary regex text.

Verify with both the helper and `curl -I` on the actual old route. Check the
Location header, status, intended language, a nonmatching path, and a currently
existing page. Finally inspect the head and robots response of the public site,
including a page without custom metadata so the fallback is exercised.
