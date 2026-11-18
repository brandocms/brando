# Pages and fragments

Use a **page** for content with a public address and a **fragment** for a reusable
piece of content, such as a footer or a campaign banner. Both have block content,
language, status, revisions, and scheduled publishing. A fragment can belong to
a page for organization; it does not acquire a public route of its own.

This walkthrough assumes a migrated Brando consumer with a working admin,
`MyAppWeb.PageHTML`, and the generated browser pipeline. Start with
[Installation](installation.md) if those are not in place.

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

<!-- usage-rules:start topic="rendering" -->

## Resolve and render public pages

Keep `page_routes()` **after** application-specific routes: its catch-all would
otherwise handle requests intended for your controllers. It adds `/`, `/*path`,
and supporting routes for previews, robots, and sitemaps.

A minimal page controller is:

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

Content written outside `Brando.Query` (a seed or `mix run` script, a data
migration, `Repo.update_all`) neither renders the entries again nor evicts
the cached pages and fragments, which are read with no expiry. After such a
write, call `Brando.Cache.clear_content/1` first, which empties the current
site's cached pages, fragments and modules and rebuilds its identity, SEO,
globals, palettes and menus, and then render what changed with
`Brando.Content.Blocks.render_entry/2`: a render reads those caches, and
before the clear it would store what they held. Clearing the caches renders
nothing: an entry shows its stored HTML until it is rendered. A script in its
own VM reaches only the nodes its PubSub reaches, and a data migration runs
without the caches, so it clears nothing; for a running server, a superuser
uses **Configuration → Utilities → Clear content caches** once the script or
migration has run.

The template selector discovers functions in `MyAppWeb.PageHTML` (or legacy
`PageView` templates). Add a HEEx template and expose it through the usual
`embed_templates "page_html/*"`. The stored value includes `.html`, such as
`"default.html"`; a stored template without a matching function cannot render.

Once a site has a frontend module (see
[Per-site layouts and templates](tenancy_and_environments.md#per-site-layouts-and-templates)),
its templates come from that module's `page_html/0` instead, both in the
selector, which lists the selected site's templates, and when the page and its
404 and 410 pages render. A page's `template` is resolved against the current
site's `PageHTML`, so each site needs the templates its pages name.

<!-- usage-rules:end -->

<!-- usage-rules:start topic="rendering" -->

## The root layout

The CMS site renders its pages in `YourWeb.CMS.Layouts.root/1`, and a site
with a [frontend](tenancy_and_environments.md#per-site-layouts-and-templates)
in its own `Layouts.root/1`. A root layout gets the conn's assigns as a plain
map, not a LiveView's, so `assign/3` raises (`assign/3 expects a socket`).
Add to the map with `Map.merge/2`:

<!-- usage-rules:no-compile -->
```elixir
def root(assigns) do
  assigns = Map.merge(assigns, %{year: Date.utc_today().year})

  ~H"""
  ...
  """
end
```

### Site icons

`<.head>` writes no icon links. The root layout has them, inside `<.head>`,
after the tags Brando writes:

```heex
<.head conn={@conn}>
  <link rel="icon" href="/ico/favicon.ico" sizes="any" />
</.head>
```

`mix brando.install` puts a `favicon.ico` in `assets/frontend/public/`, for
browsers that ask for `/favicon.ico` whatever a page links, and one in
`assets/frontend/public/ico/`, and it and `mix brando.gen.site` add `ico` to
the web module's `static_paths/0`. The frontend build copies `public/` to `priv/static`. To use
the site's own icons, replace both `favicon.ico` files, put the others in
`public/ico/`, and edit the `<link>` lines to match. The generated layout has
commented lines for an SVG icon, a dark-mode SVG (`media="(prefers-color-scheme:
dark)"`), a 32-pixel PNG and an Apple touch icon. A site's frontend made with
`mix brando.gen.site --site KEY` gets the same lines, and in `:multi` its Vite
project in `assets/sites/KEY/` has its own `public/ico/`.

The endpoint reads `static_paths/0` when it starts, so restart the server
after adding a directory to it: the code reloader does not pick that up.

<!-- usage-rules:end -->

<!-- usage-rules:start topic="rendering" -->

## Homepage, hierarchy, and breadcrumbs

The root path resolves to URI `"index"`, with one record per language. Set
`is_homepage: true` for the homepage's admin marker and empty breadcrumb trail,
and use URI `"index"` for root routing. A homepage flag alone is not a substitute
for the URI used by the controller.

`parent_id` records hierarchy. The URI stores the complete path: a child of
`about` needs `uri: "about/team"` to resolve at `/about/team`. In the admin, a new
page's URI follows its title and starts with the chosen parent's URI (the
homepage adds nothing); a URI typed by hand is kept as typed, so a child page can
still live elsewhere. Changing the parent of an existing page does not rewrite
its URI, and programmatic writes must store the full path themselves. The parent selector limits its
choices to the page's language; keep that boundary in programmatic writes too.
Use `has_url: false` for organizational content that should not be public. Such
a page has no URL: `Page.__absolute_url__/1` returns `nil` for it, and the
content SEO audit leaves it out. Filter the flag in your controllers, and use
`Page.__url_filter__/0` in your [sitemap](sitemaps.md).

<!-- usage-rules:end -->

Page context creates and updates recompute `breadcrumbs` for the page and its
non-deleted descendants, those under a trashed page included. Trashing a page (`Pages.delete_page/3`) recomputes its
descendants' trails, and restoring it (`Brando.Authorization.Boundary.restore/2`)
recomputes its own and its descendants'. So does restoring one of its revisions
(`Brando.Revisions.set_entry_to_revision/5`, which the revisions drawer and a
proposal's undo use): the trail a revision holds never comes back. A page's
changeset refuses a `parent_id` that is the page itself or a page under it, and
its save checks again against the tree as it is then, so a revision restore or a
changeset built before another save that would close such a loop returns
`{:error, changeset}`; a
loop already stored ends the trail where it closes. Each element has string keys `"title"` and `"uri"`.
The stored trail starts with the configured app name at `/`, followed by the
ancestors and current page; a deleted ancestor is left out. When the trash
purge deletes a page for good, its remaining children move to the top
(`parent_id` is cleared) and their trails are recomputed. Fragments still on
it lose their `page_id`: those trashed with it are purged with it, and live ones
are listed under Fragments without a page. It stores
`"/" <> page.uri`; it does **not** add a
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

<!-- usage-rules:start topic="rendering" -->

Query the current language explicitly:

```elixir
{:ok, partials} = Brando.Pages.get_fragments(%{
  filter: %{parent_key: "partials", language: conn.assigns.language},
  cache: {:ttl, :infinite}
})

conn = Plug.Conn.assign(conn, :partials, partials)
```

```heex
<footer :if={fragment = @partials["footer"]}>
  {fragment}
</footer>
```

This empty state omits an absent footer. For an unknown key, the
`render_fragment` convenience helpers and `fetch_fragment/2` render a visible
**Missing page fragment** diagnostic in development; elsewhere they render
nothing and log a warning. Rendering a fragment struct directly also applies its
optional wrapper, which accepts `{{ content }}`, `{{ parent_key }}`, `{{ key }}`,
and `{{ language }}` substitutions. The wrapper is printed as it is, so only a
superuser sets it (see [Authorization](authorization.md)); editors edit the
rest of the fragment, and the keys it prints are HTML-escaped.
`render_fragment/1` outputs the stored content without that wrapper.

A parent key or key holds letters, digits, `_`, `-`, `.`, `/`, spaces and
parentheses, and can't start or end with a space, so `about/team`, `/about`,
`site-footer` and a copy's `footer (copy)` all work. A save that changes one to
anything else is refused, with a message that says which rule it breaks. A
content transfer that creates a fragment holds its keys to the same rules. The `{% fragment %}` tag still takes only bare words
(see [the block editor guide](block_editor.md)), so it can't name the others.

Only a published fragment renders. An unpublished one stays in the map with no
content, so `{fragment}`, `<Brando.HTML.fragment fragment={fragment} />`,
`render_fragment(@partials, "footer")` and `fragment.rendered_blocks` all give
nothing rather than the draft or the missing-fragment diagnostic. The same
holds for `Brando.Plug.Fragment, parent_key: "partials", as: :partials`, which
loads a group after the locale plug, for `get_fragments/2`, and for a fragment
struct from `Brando.Pages.get_fragment/2` rendered with the component, the
`render_fragment` helpers or `fetch_fragment/2`. `status: :published` gives
the same map; pass another `:status`, such as `status: :all`, to
`get_fragments/1` for fragments as stored, with their content.

A fragment embedded in a block, through a fragment block, the
`{% fragment %}` tag or `<.fragment>`, is rendered into the entry's stored
HTML. Saving the fragment re-renders the entries holding a fragment block;
an entry embedding it through the tag or component shows the change on its
own next save. The fragment goes in as it was rendered: the entry's Liquid
pass does not evaluate its text a second time.

<!-- usage-rules:end -->

Saving or deleting a fragment through its context queues affected block entries
for rendering. Check the direct footer and a page that references the fragment
as a block after saving; both should reflect the change once rendering finishes.

## Delete a page that has fragments

A fragment is found by its keys and language, not through its page, so a page's
fragments would keep showing on the site after the page is gone. Deleting a page
in the admin lists its fragments and asks where they go:

- **Move them to** a page, by default the nearest page above it that is not in
  the trash, or else the homepage in its language. Choosing **No page** keeps
  them on the site with no page.
- **Delete them with the page**: they go to the trash with it, and restoring the
  page brings them back.

A page without fragments asks as any other entry does. A bulk delete from the
listing, and `Brando.Pages.delete_page/2` from code, move them as the dialog
does by default; pass `fragments:` for another choice:

```elixir
Brando.Pages.delete_page(page.id, user)                                   # to the page above, or the homepage
Brando.Pages.delete_page(page.id, user, fragments: {:move, other_page.id})
Brando.Pages.delete_page(page.id, user, fragments: {:move, nil})          # no page
Brando.Pages.delete_page(page.id, user, fragments: :delete)
```

The fragments change in the page delete's transaction, and a refused fragment
leaves the page where it was: moving takes the right to update each fragment,
and deleting the right to delete it (and to publish it, when it is published).
A fragment already in the trash stays there. Restoring the page brings back the
fragments deleted with it in one transaction too, which takes the right to
restore each of them. Entries embedding a fragment that is deleted, or restored
with its page, are queued for rendering once the change commits.

The pages listing shows the fragments no page holds, in its content language,
under **Fragments without a page**: their page is in the trash or gone, or they
never had one. Edit one to choose its page. `Brando.Pages.list_fragments_without_page/1` returns them, and
`mix brando.doctor` warns about those on a trashed or missing page.

## Check the result

Verify `/about`, a translated page such as `/no/om`, and a missing URI. Only the
published page in the requested language should resolve. Reload the editor to
check persistence, change a parent title to inspect descendant breadcrumbs, and
unpublish the footer to confirm your public empty state. See
[I18n](i18n.md) for linking translated pages and emitting alternate URLs.
