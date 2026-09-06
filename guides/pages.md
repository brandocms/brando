# Pages and fragments

Use a **page** for content with a public address and a **fragment** for a reusable
piece of content, such as a footer or a campaign banner. Both have block content,
language, status, revisions, and scheduled publishing. A fragment can belong to
a page for organization; it does not acquire a public route of its own.

This walkthrough assumes a migrated Brando consumer with a working admin,
`MyAppWeb.PageHTML`, and the generated browser pipeline. Start with
[Installation and generators](generators.md) if those are not in place.

## Create and reload a page

Open **Pages**, create a page, and set title **About**, language **English**, and
URI **about**. Keep the default template, add a text block in the Blocks tab, and
save. Reopen the page: its title and block text should survive the reload. A new
page starts as a draft; use [live preview](live_preview.md) to inspect unsaved
content, then set its status to **published** and save before visiting `/about`.

The same basic record can be created through the context. Here `current_user` is
an authenticated actor permitted to create pages in the selected environment:

```elixir
alias Brando.Pages

{:ok, page} =
  Pages.create_page(%{
    title: "About",
    uri: "about",
    template: "default.html",
    language: "en",
    status: :draft
  }, current_user)

{:ok, page} = Pages.update_page(page, %{title: "About our studio"}, current_user)
{:ok, reloaded} = Pages.get_page(%{matches: %{id: page.id}})
true = reloaded.title == "About our studio"
```

Context mutations return `{:error, changeset}` when validation fails. Keep the
changeset and display its errors; a failed save has not published the edit.
Use the admin block editor to author blocks, or follow the [block editor
guide](block_editor.md) for programmatic content construction.

## Resolve and render public pages

Keep `page_routes()` **after** application-specific routes: its catch-all would
otherwise handle requests intended for your controllers. It adds `/`, `/*path`,
and supporting routes for previews, robots, and sitemaps.

A minimal controller using the current page query API is:

```elixir
defmodule MyAppWeb.PageController do
  use BrandoWeb, :controller

  alias Brando.I18n
  alias Brando.Pages

  action_fallback BrandoWeb.FallbackController

  def index(conn, _params), do: show(conn, %{"path" => conn.path_info})

  def show(conn, %{"path" => path}) do
    {language, path} = I18n.parse_path(path)

    with {:ok, page} <- Pages.get_page(%{
           matches: %{path: path, language: language, has_url: true},
           status: :published,
           preload: [:vars, :alternate_entries],
           cache: {:ttl, :infinite}
         }) do
      conn
      |> assign(:page, page)
      |> put_title(page.title)
      |> put_meta(Pages.Page, page)
      |> put_hreflang(page)
      |> render(page.template)
    end
  end
end
```

In `lib/my_app_web/controllers/page_html/default.html.heex`:

```heex
<main id="content">
  <h1>{@page.title}</h1>
  {@page}
</main>
```

`{@page}` uses the page's HTML protocol to output its stored `rendered_blocks`.
It does not perform a fresh block render on every request. Context saves and
content dependency changes drive rendering; keep the configured rendering queue
running. For request-dependent data, use the dynamic rendering recipe in
[Datasources](datasources.md#request-dependent-content).

The template selector discovers functions in `MyAppWeb.PageHTML` (or legacy
`PageView` templates). Add a HEEx template and expose it through the usual
`embed_templates "page_html/*"`. The stored value includes `.html`, such as
`"default.html"`; a stored template without a matching function cannot render.

## Homepage, hierarchy, and breadcrumbs

The root path resolves to URI `"index"`, with one record per language. Set
`is_homepage: true` for the homepage's admin marker and empty breadcrumb trail,
and use URI `"index"` for root routing. A homepage flag alone is not a substitute
for the URI used by the controller.

`parent_id` records hierarchy. Store the complete URI yourself: a child of
`about` needs `uri: "about/team"` to resolve at `/about/team`. Changing the parent
does not concatenate or rewrite the child's URI. The parent selector limits its
choices to the page's language; keep that boundary in programmatic writes too.
Use `has_url: false` for organizational content that should not be public, and
filter that flag in your controllers and [sitemap](sitemaps.md).

Page context creates and updates recompute `breadcrumbs` for the page and its
non-deleted descendants. Each element has string keys `"title"` and `"uri"`.
The stored trail starts with the configured app name at `/`, followed by the
ancestors and current page. It stores `"/" <> page.uri`; it does **not** add a
language prefix. Localize those URLs in a multilingual breadcrumb component,
and verify both languages. Raw `Repo` writes bypass this recomputation; after a
controlled import use `Brando.Pages.update_breadcrumbs(page)` and refresh any
application caches that hold the old page.

## Page variables

Add a string variable with key `intro` under **Advanced → Page variables**.
Preload `:vars` and access its rendered value:

```heex
<p :if={Brando.Pages.has_var?(@page, "intro")}>
  {Brando.Pages.get_var(@page, "intro")}
</p>
```

A missing key returns `nil`. Image, file, video, and gallery vars return their
asset value for the matching [media component](media.md), not an HTML string.
Preload the corresponding asset associations when using them outside the form.

## Reuse a translated footer

In Pages, create a fragment with parent key `partials`, key `footer`, and
language `en`. Add its blocks and publish it. Create the translated counterpart
with the same keys and language `no`. The parent key is a namespace; `page_id`
is optional organization, not the lookup key.

Query the current language explicitly and filter status for public output:

```elixir
{:ok, partials} = Brando.Pages.get_fragments(%{
  filter: %{parent_key: "partials", language: conn.assigns.language},
  status: :published,
  cache: {:ttl, :infinite}
})

conn = Plug.Conn.assign(conn, :partials, partials)
```

```heex
<footer :if={fragment = @partials["footer"]}>
  {fragment}
</footer>
```

This empty state omits an absent footer. The `render_fragment` convenience
helpers instead render a visible **Missing page fragment** diagnostic for an
unknown key. Rendering a fragment struct directly also applies its optional
wrapper, which accepts `{{ content }}`, `{{ parent_key }}`, `{{ key }}`, and
`{{ language }}` substitutions. `render_fragment/1` outputs the stored content
without that wrapper.

`Brando.Plug.Fragment, parent_key: "partials", as: :partials` is convenient for
loading a group after the locale plug, but its current query does not restrict
status. Neither do all of the older fragment lookup helpers. Use the explicit
query above when a draft fragment must remain private.

Saving or deleting a fragment through its context queues affected block entries
for rendering. Check the direct footer and a page that references the fragment
as a block after saving; both should reflect the change once rendering finishes.

## Check the result

Verify `/about`, a translated page such as `/no/om`, and a missing URI. Only the
published page in the requested language should resolve. Reload the editor to
check persistence, change a parent title to inspect descendant breadcrumbs, and
unpublish the footer to confirm your public empty state. See
[I18n](i18n.md) for linking translated pages and emitting alternate URLs.
