# Markdown alternates

An entry's page can also be read as Markdown, which AI tools and answer
engines parse more reliably than a designed HTML page. Brando serves it:

* at the page's URL with `.md` appended: `/projects/sommerro.md`, and
  `/index.md` for the site's root;
* at the page's own URL, to a request that prefers `text/markdown` in its
  `Accept` header.

The HTML page names it in its head (`render_hreflangs`):

```html
<link rel="alternate" type="text/markdown" href="https://example.com/projects/sommerro.md">
```

## Which entries

A blueprint has a Markdown version when it has a URL of its own
(`absolute_url`), block fields (`Brando.Trait.Blocks`) and `Brando.Trait.Meta`.
Turn it off for one:

```elixir
trait :meta, markdown: false
```

Only the entry a page's controller loads is served, so the Markdown follows
the same rules as the HTML: drafts, scheduled entries, another site's entries
and pages behind a login are not found as Markdown. Brando checks again that
the entry is published, past any publish time and not deleted. A path that is
not about an entry (a listing, a search page) has no Markdown version and
gives `404`.

## Set it up

Add `Brando.Plug.Markdown` to the endpoint, before the router (`mix
brando.install` does this for new projects):

```elixir
plug Brando.Plug.LivePreview
plug Brando.Plug.Markdown
plug MyAppWeb.Router
```

The page's controller must pass the entry to `put_meta/3`, `put_hreflang/2` or
`put_json_ld/3`, as Brando's generated controllers do. That is how the plug
knows which entry the page is about.

`.md` never shadows a route of its own: a path matching a route whose last
segment is literally `….md`, and static files served before the plug, are left
alone. A route that takes a `.md` file name as a parameter (`/docs/:file`)
can't be told apart from an entry URL; keep it out with `:except`:

```elixir
plug Brando.Plug.Markdown, except: ["/admin", "/api", "/docs"]
```

The default is `["/admin", "/api"]`.

## The response

```text
HTTP/1.1 200 OK
content-type: text/markdown; charset=utf-8
vary: Accept
etag: W/"md-…"
link: <https://example.com/projects/sommerro>; rel="canonical"
```

The `Link` header names the HTML page as canonical, so search engines don't
index the Markdown as a duplicate. `If-None-Match` with the `ETag` gives `304`.
The HTML of a page with a Markdown version also says `Vary: Accept`, so a
cache in front of the site keeps the two apart. The Markdown is rendered for
each request; Brando has no page cache of its own.

Static builds (`Brando.SSG`) do not write `.md` files yet, and a static host
can't negotiate on `Accept`.

## What the Markdown holds

The entry's title as a heading, then its block fields, rendered by
`Brando.Villain.Markdown`:

* A **module** renders its HTML template, and that HTML becomes Markdown:
  headings, paragraphs, lists, quotes, tables, links and emphasis keep their
  meaning; layout wrappers are read through; scripts, styles, SVG, forms,
  buttons and navigation are left out. Its refs are written plainly for this:
  rich text as it is, a heading as a heading, a picture as `![alt](url)` with
  its caption, a gallery as its images, a video or a file as a link. Maps,
  SVG, comments and form inputs are left out. Variables the template prints
  are kept.
* A **container** renders its children; its own template is layout.
* A **fragment** gives its published HTML as Markdown.
* Inactive and deleted blocks are left out.

### A module's Markdown template

When the default reads poorly (a card grid, a module that is mostly layout),
give the module a **Markdown template** in the module editor, under its HTML
template. It is a Liquid template with the same refs and variables, and
`{{ content }}` for a multi module's entries. `{% ref refs.name %}` gives the
ref as Markdown:

```liquid
## {{ heading }}

{% ref refs.text %}

- Floor area: {{ floor_area }}
- Rooms: {{ rooms }}
```

Leave it empty to use the default. The template is stored in the module's
`markdown_code`; it is not carried by module definition files or content
transfer archives yet.
