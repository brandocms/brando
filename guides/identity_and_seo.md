# Identity, SEO settings, and redirects

<!-- llms-description: The site's identity, SEO defaults, robots.txt, AI crawler policy, IndexNow and manual redirects. -->

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

<!-- usage-rules:start topic="seo" -->

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

<!-- usage-rules:end -->

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

<!-- usage-rules:start topic="seo" -->

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
identity helpers are not a recipe for multilingual output. Links also become
`og:see_also` tags, and a link to an X profile (`https://x.com/example`) gives
pages their `twitter:site` handle; see [Page metadata](meta.md#x-cards).

Identity updates refresh the cache and enqueue block content referencing identity,
configs, or links for rendering. Direct `Repo` writes skip those callbacks. During
a controlled import, refresh the cache in each affected environment and invoke
`Brando.Sites.update_villains_referencing_identity({:ok, identity})` afterwards.

<!-- usage-rules:end -->

## Describe your services

The **Services** tab on the identity takes a repeatable list of what the
organization provides: name, description, alternate names (the other
language's wording, industry synonyms), service type, URL and area served.
Each service can link to an entry; it then takes that page's URL and — when it
has no description of its own — the page's meta description or block text, so
the markup describes content that is actually published.

Every service is emitted into the JSON-LD graph as a `Service` node joined to
`#identity`, inheriting the organization's `areaServed` unless it names its
own. Nothing else is needed for the structured data.

Markup alone mostly feeds AI retrieval. Present the services on the page too,
so the nodes describe a real section:

```heex
<Brando.HTML.Services.list language={@language}>
  <:heading>What we do</:heading>
</Brando.HTML.Services.list>
```

The component reads the cached identity, renders one item per service with
its resolved URL and description, and emits only structural classes
(`services`, `service`, `service-name`, `service-description`). Pass
`services` to render a subset, or an `:item` slot to control each entry's
markup. Outside a template, `Brando.HTML.Services.for_language("en")` returns
the resolved list.

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

<!-- usage-rules:start topic="seo" -->

`Brando.Cache.SEO.get(language)` returns an empty SEO struct if the language has
no row. That keeps lookups possible but does not provide meaningful metadata.
SEO context updates refresh the SEO cache; they do not automatically rerender
arbitrary block templates or rebuild a static deployment. Rebuild those outputs
when they embed settings at build time.

The generated `page_routes()` exposes `/robots.txt`. It returns the current
language's configured robots text, or a default that disallows `/admin/`, then
the AI crawler policy below, then a `Sitemap:` line once a sitemap has been
generated (unless the robots text names one). It does not add an environment-specific crawl block
for you; inspect the intended deployment and configure its policy explicitly.
The base URL field does not reconfigure Phoenix's endpoint or your DNS. Set the
endpoint URL correctly
for canonical URLs, metadata, and [sitemap generation](sitemaps.md).

<!-- usage-rules:end -->

### AI crawlers and Content Signals

**Crawlers and AI**, under Indexing, lists the crawlers AI products send
(`Brando.SEO.Crawlers`), grouped by purpose: building an AI search index
(OAI-SearchBot, Claude-SearchBot, PerplexityBot), fetching a page a user asked
for (ChatGPT-User, Claude-User, Perplexity-User) and collecting pages for model
training (GPTBot, ClaudeBot, Google-Extended, Applebot-Extended,
meta-externalagent, Amazonbot, CCBot, Bytespider). Each is allowed or blocked.
Traditional search crawlers are not listed and are never blocked here.

**Use for model training** sets the `ai-train`
[content signal](https://contentsignals.org) for every crawler, including ones
not listed: no preference, allow or don't allow.

`Brando.SEO.Robots` writes the choices after the robots text, between
`# BEGIN Brando AI crawler policy` and `# END Brando AI crawler policy`: a
`Disallow: /` group for each blocked crawler, then the Content Signals policy
text and a `Content-Signal:` line in a `User-agent: *` group of its own:

```text
User-agent: GPTBot
Disallow: /

User-agent: *
Content-Signal: search=yes, ai-input=yes, ai-train=no
```

<!-- usage-rules:start topic="seo" -->

`ai-input` is `no` only when every AI search and user-fetch crawler is blocked.
The robots text is never changed; the block is added when robots.txt is served.
Nothing is added until a crawler is blocked or a training preference chosen,
so a site that never opens the setting serves what it did before. **View
robots.txt** opens the result. The policy is stored per language, like the
robots text, in the SEO entry's `crawler_policy`.

Blocking is a request: the user-fetch crawlers say robots.txt may not apply to
them. Google's AI Overviews use Googlebot, not `Google-Extended`; keep a page
out of them with the entry's **No snippet** and **Snippet length** settings
([Page metadata](meta.md#snippet-limits)).

<!-- usage-rules:end -->

### IndexNow

[IndexNow](https://www.indexnow.org) tells search engines that a page has
appeared, changed or gone, so they visit it soon instead of waiting for
their next crawl. Bing and the search engines and AI products that use its
index (Copilot, DuckDuckGo, Yandex and others) take part; Google doesn't.

**IndexNow**, under the SEO settings, turns it on for the site. That creates
the site's key, served at `/<key>.txt` (`Brando.Plug.IndexNow`, in the
endpoint before the router). From then on an entry's URL is submitted when
the entry is published, saved while published, unpublished or deleted, by
`Brando.IndexNow`, a [content event](webhooks.md) subscriber. Each language
version is its own entry and is submitted when it changes. URLs are gathered
for a minute and sent as one request per host, at most 10,000 URLs a request,
by `Brando.Worker.IndexNowSubmission` on the `:webhooks` queue. The panel
shows the last submission and the answer: `200` or `202` is accepted, `403`
means the key file could not be read, `422` that a URL is not on the key's
host.

<!-- usage-rules:start topic="seo" -->

It is off by default. Only the live environment submits, so a staging copy
never does. Without tenancy the deployment is the site; on a server that is
not the public one, turn IndexNow off in its configuration:

```elixir
config :brando, Brando.IndexNow, enabled: false
```

<!-- usage-rules:end -->

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

### Find the URLs worth redirecting

The fallback controller logs every 404 it serves. **Configuration → SEO** lists
the missing URLs below the form, most requested first, with their hits, the last
hit and the referrer that sent most of them. **Redirect** adds a row for one to
the form's redirects; save the form to keep it. Requests from vulnerability
scanners (`/wp-login.php`, `/.env`) are folded away under them.

`Brando.Sites.FourOhFour` counts hits in memory and writes them to the
`sites_not_found_hits` table every minute, and when the node shuts down, as one
row per URL, referrer and day. A burst of requests for missing pages therefore
costs one database statement a minute, and the log survives deploys. The
referrer is kept without its query string. Rows are deleted after 90 days by
`Brando.Worker.NotFoundPurger`, nightly at 05:25 UTC in every active
environment:

```elixir
config :brando, Brando.Sites.FourOhFour,
  retention_days: 30,
  flush_interval: :timer.seconds(60)
```

<!-- usage-rules:start topic="seo" -->

An application that sets its own `config :brando, Oban` replaces Brando's
crontab and must add `{"25 5 * * *", Brando.Worker.NotFoundPurger}` to its own.
`Brando.Sites.FourOhFour.add_404/1` records a miss from a controller of your own.

<!-- usage-rules:end -->

For permalink changes, the admin can offer a confirmed automatic redirect. That
flow stores an escaped exact source, removes stale exact rules on the new URL,
and avoids simple rename-back loops. See [Permalink redirects](blueprint_traits.md#permalink-redirects).
Do not recreate those internal rules by submitting arbitrary regex text.

Verify with both the helper and `curl -I` on the actual old route. Check the
Location header, status, intended language, a nonmatching path, and a currently
existing page. Finally inspect the head and robots response of the public site,
including a page without custom metadata so the fallback is exercised.
