# Page metadata

A Blueprint metadata schema maps an entry into `<meta>` tags. The controller adds
those values to the connection, and the layout renders them with language-specific
[SEO fallbacks](identity_and_seo.md). The document's `<title>` is a separate value;
set it deliberately so the browser tab and sharing title agree.

This example assumes a `MyApp.News.Post` Blueprint with `title`, `summary`, and
`language`, `trait :meta` for the editable metadata fields, and a public controller.

<!-- usage-rules:start topic="seo" -->

## Define the metadata schema

Inside the Blueprint:

```elixir
meta_schema do
  field ["title", "og:title"], &fallback([&1.meta_title, &1.title])
  field ["description", "og:description"], fn entry ->
    case fallback([entry.meta_description, {:strip_tags, entry.summary}]) do
      nil -> nil
      text -> Brando.HTML.truncate(text, 155)
    end
  end
  field "og:image", & &1.meta_image
  field "og:locale", &encode_locale(to_string(&1.language))
end
```

Each callback receives the **whole entry**. Truncate the entry's description or
summary, not the entry struct. A target may be a single key or a list of keys
sharing the same value. Declare each target once unless duplicate tags are
intentional; listing two title callbacks is not a fallback mechanism.

<!-- usage-rules:end -->

`fallback/1` tries values in order; `fallback/2` tries paths on the supplied data:

```elixir
Brando.Blueprint.Value.fallback([nil, {:strip_tags, "<p>Our story</p>"}])
#=> "Our story"

Brando.Blueprint.Value.fallback(%{meta_title: nil, title: "Our story"}, [:meta_title, :title])
#=> "Our story"
```

<!-- usage-rules:start topic="seo" -->

Fallback skips `nil`, not every falsey-looking value: an empty string remains a
value. If your import stores blank strings and you want defaults, normalize them
before metadata extraction. Use `try_path(entry, [:association, :field])` for
optional nested data and preload any association the callback needs.

A callback returning nil is omitted. Reading a missing key is also omitted;
other exceptions propagate so a broken callback stays visible. The locale helper
expects a string: `"en"` becomes `"en_US"`, and `"no"`/`"nb"` become `"nb_NO"`.
Read the entry's `language`, not Ecto's `__meta__` storage metadata.

<!-- usage-rules:end -->

<!-- usage-rules:start topic="seo" -->

## Put values on the connection

```elixir
defmodule MyAppWeb.PostController do
  use BrandoWeb, :controller
  alias MyApp.News
  alias MyApp.News.Post

  action_fallback BrandoWeb.FallbackController

  def show(conn, %{"slug" => slug}) do
    with {:ok, post} <- News.get_post(%{
           matches: %{slug: slug, language: conn.assigns.language},
           status: :published,
           preload: [:meta_image]
         }) do
      title = Brando.Blueprint.Value.fallback([post.meta_title, post.title])

      conn
      |> assign(:post, post)
      |> put_title(title)
      |> put_meta(Post, post)
      |> render(:show)
    end
  end
end
```

The `News` context must define the `slug` and `language` matches used here; see
[Querying](querying.md). The browser pipeline must establish `conn.assigns.language`
and the appropriate tenant before the query and SEO lookup.

`put_title/3` sets the document title. `Brando.Utils.get_page_title(conn)` applies
the identity's prefix/postfix; use `skip_prefix: true` and/or `skip_postfix: true`
when the supplied title already includes them. `put_meta/3` supplies metadata,
including Open Graph, without setting the document title on its own.

<!-- usage-rules:end -->

<!-- usage-rules:start topic="seo" -->

## Render the head once

If the layout already uses `<Brando.HTML.head conn={@conn}>`, it renders metadata,
JSON-LD, canonical/alternate links, and the document title. Do not add a second
set beside it. In a custom head, the minimal equivalent for title and metadata is:

```heex
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{Brando.Utils.get_page_title(@conn)}</title>
  <Brando.HTML.render_meta conn={@conn} />
  <Brando.HTML.render_hreflangs conn={@conn} />
</head>
```

<!-- usage-rules:end -->

Metadata rendering fills absent title, description, and image values from the
current language's SEO record. It supplies site name, type, and current URL, and
includes identity custom metadata and links. `og:*` keys use `property`; other
keys use `name`. Image records are turned into absolute image URLs with type and
dimensions; a URL string is accepted too. Preload `:meta_image` and configure real
image sizes/CDN delivery before relying on that output.

<!-- usage-rules:start topic="seo" -->

Without a language assign, `render_meta` renders no tags. Without a configured
fallback, absent values stay absent. Neither case should be mistaken for an
application crash or proof that your page schema ran.

<!-- usage-rules:end -->

### X cards

`render_meta` also writes the tags X (Twitter) reads, copied from the final
Open Graph values:

| Tag | Value |
| --- | --- |
| `twitter:card` | `summary_large_image` when there is an `og:image`, otherwise `summary` |
| `twitter:title` | `og:title` |
| `twitter:description` | `og:description` |
| `twitter:image` | `og:image` |
| `twitter:site` | `@handle`, when one of the identity's links is an `x.com` or `twitter.com` profile |

A value the page or the identity's custom metadata already set wins, so
`put_meta(conn, "twitter:card", "summary")` keeps a small card on a page with an
image. Blueprints do not need `twitter:*` fields in their `meta_schema`.

## Canonical URL

A page has one URL, `Brando.Plug.HTML.page_url/1`, and its canonical link,
`og:url`, its own language's alternate and the `@id`s and `url`s of its
JSON-LD all name it. It is chosen when the head is rendered, so the order a
controller calls these functions in does not matter. The first of these that
gives a URL is the page's:

1. the URL given to `put_page_url/2`;
2. the URL of the entry given to `put_hreflang/2`, its blueprint's
   `absolute_url`, whatever path the request used (`/about/`, `/about?ref=x`,
   or another route to the same page);
3. the request URL, without a trailing slash or its query string.

The entries given to `put_meta/3` and `put_json_ld/3` do not decide it. A
controller often describes several routes with one section page
(`/projects/:slug`, `/news/page/2`): each route keeps its own URL. When the
page's URL is none of these, set it:

```elixir
conn
|> put_meta(Page, section_page)
|> put_page_url("/projects")
```

An error response (the 404 and 410 pages, any status outside 200–299) has
no URL, and gets no canonical link, `og:url`, own-language alternate or
`WebPage` node: a static build serves its 404 page at every missing path,
so a URL there would name the wrong page.

The page's own-language alternate is always the page's URL: an alternate
given to `put_hreflang/2` for the page's language is replaced by it, so the
head lists one link per language.

A page's URL has no trailing slash, as the entry's URL and the sitemap's
entries have none: `/about/` is `https://example.com/about`, and its nodes
are `https://example.com/about#webpage` and `…/about#article`. The front
page's URL is the bare origin, `https://example.com`, and its nodes take the
`/` that is its path: `https://example.com/#webpage`. A listing paginated on
a query string (`/news?page=2`) has the URL without it, the first page's;
paginate on the path (`/news/page/2`) to give each page its own.

For content first published elsewhere, or
duplicated across entries, an editor can override it: `trait :meta` adds a
**Canonical URL** field to the entry's meta drawer (`meta_canonical_url`). It
takes a full `https://` or `http://` address; left empty, nothing changes.

`put_meta/3` and `put_hreflang/2` pick the override up from the entry, and
`render_hreflangs` and `og:url` use it. Language alternates are still written.
For a page that is not an entry, set one yourself:

```elixir
put_canonical(conn, "https://example.com/original-article")
```

## Snippet limits

`trait :meta` adds **No snippet** (`meta_nosnippet`) and **Snippet length**
(`meta_max_snippet`, in characters) to the meta drawer. They limit the text
search engines and AI answers may quote from the page, and are written as the
page's robots meta tag:

```html
<meta name="robots" content="nosnippet">
<meta name="robots" content="max-snippet:120">
```

No snippet wins over a length; a length of `0` also means no snippet; empty
leaves it to the search engine. They are what keeps a page's text out of
Google's AI Overviews and AI Mode, which `Google-Extended` in robots.txt does
not. `put_meta/3` and `put_hreflang/2` pick them up from the entry; directives
the page set itself (`put_meta(conn, "robots", "noarchive")`, or
`put_robots(conn, ["noarchive"])`) are kept in the same tag.

## Markdown alternate

When the entry has a [Markdown version](markdown_alternates.md),
`render_hreflangs` adds
`<link rel="alternate" type="text/markdown" href="…/entry.md">`.

## Previews in the meta drawer

The meta drawer's **Previews** tab shows the page as a search result, as an
Open Graph card (Facebook, LinkedIn) and as an X card, with the values
`render_meta` would write: the `meta_schema` first, then the SEO settings'
fallbacks. The cards follow the form as it is edited. The image is the one
`og:image` names, in the size that is shared (`:largest`); when that size is
cropped, as the meta image's is, Brando cut it around the image's focal point,
and the card shows that file cut to the card's shape the way the platform
does, with a ring where the focal point lands (`Brando.SEO.SharePreview`).
The tab also shows the [Markdown version](markdown_alternates.md).

## Check the rendered result

Open the **page source** for a published post. Verify one `<title>`, matching
`og:title`, a plain-text description, the expected locale, and a fetchable absolute
sharing-image URL. Repeat with empty custom metadata to exercise the site
fallbacks, and with a Norwegian post to catch cross-language cache/config mistakes.

You can inspect the schema result separately:

```elixir
Brando.Blueprint.Meta.extract_meta(MyApp.News.Post, post)
```

That checks callback extraction, not the final fallback-enriched layout. Test both.
Use [JSON-LD](jsonld.md) for structured data rather than adding a JSON object as a
meta tag.
