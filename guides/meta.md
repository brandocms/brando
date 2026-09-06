# Page metadata

A Blueprint metadata schema maps an entry into `<meta>` tags. The controller adds
those values to the connection, and the layout renders them with language-specific
[SEO fallbacks](identity_and_seo.md). The document's `<title>` is a separate value;
set it deliberately so the browser tab and sharing title agree.

This example assumes a `MyApp.News.Post` Blueprint with `title`, `summary`, and
`language`, `trait :meta` for the editable metadata fields, and a public controller.

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

`fallback/1` tries values in order; `fallback/2` tries paths on the supplied data:

```elixir
Brando.Blueprint.Value.fallback([nil, {:strip_tags, "<p>Our story</p>"}])
#=> "Our story"

Brando.Blueprint.Value.fallback(%{meta_title: nil, title: "Our story"}, [:meta_title, :title])
#=> "Our story"
```

Fallback skips `nil`, not every falsey-looking value: an empty string remains a
value. If your import stores blank strings and you want defaults, normalize them
before metadata extraction. Use `try_path(entry, [:association, :field])` for
optional nested data and preload any association the callback needs.

A callback returning nil is omitted. Reading a missing key is also omitted;
other exceptions propagate so a broken callback stays visible. The locale helper
expects a string: `"en"` becomes `"en_US"`, and `"no"`/`"nb"` become `"nb_NO"`.
Read the entry's `language`, not Ecto's `__meta__` storage metadata.

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

Metadata rendering fills absent title, description, and image values from the
current language's SEO record. It supplies site name, type, and current URL, and
includes identity custom metadata and links. `og:*` keys use `property`; other
keys use `name`. Image records are turned into absolute image URLs with type and
dimensions; a URL string is accepted too. Preload `:meta_image` and configure real
image sizes/CDN delivery before relying on that output.

Without a language assign, `render_meta` renders no tags. Without a configured
fallback, absent values stay absent. Neither case should be mistaken for an
application crash or proof that your page schema ran.

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
