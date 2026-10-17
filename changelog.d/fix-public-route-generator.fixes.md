- **`mix brando.gen --public-route` pages belong to the CMS site** (#3230).
  With the CMS site from `mix brando.gen.site`, the generated routes pipe
  through `[:browser, :brando_site]`, ahead of the CMS catch-all, so tenant,
  locale, identity, navigation and `Brando.Plug.Lockdown` apply: before, they
  piped through `:browser` only and stayed public while the site was locked.
  The controller renders in `YourWeb.CMS.Layouts` with the `partials`
  fragments and the entry's meta tags, title and hreflang links, as
  `CMS.PageController` does, instead of phx.new's root layout. An entry page
  is at `/path/:slug` when the Blueprint has a slug (it was always `:id`, and
  `/projects/<slug>` raised `Ecto.Query.CastError`). A missing entry or
  malformed id gives the site's 404 page through `BrandoWeb.FallbackController`,
  or without the CMS site raises `Ecto.NoResultsError`, which `ErrorHTML`
  renders as a 404; it was a plain-text "Not found". The entry page renders
  the Blueprint's block fields after its title and loads the associations its
  meta fields return, such as `meta_image`, and each one a fallback reaches
  (`fallback([&1.meta_image, &1.cover])` loads both), which the layout's meta
  tags raised on unloaded. For a Blueprint with a `language` field each language
  gets its routes, as the CMS pages do: the default language's unprefixed and
  the others' in a scope under their code (`/no/articles`), from the
  configured languages; the pages show the request's language through the
  query's `language:` option, by slug or by id, so translations can share a
  slug and the context needs no language clause. Pages by id need an integer
  or UUID primary key named `id`, and the generator stops with an issue for
  another (`primary_key false`, say). The notice says what to wire by
  hand without the CMS site, prints the `absolute_url` that matches the route
  (with `route_i18n` for a translatable Blueprint, also when its own gives
  every language one path), and mentions `--public-route` only when it was
  not given.

- **`brando.gen` consumer templates keep entry pages at `:id`** (#3230).
  `controller.ex` and `html.ex` in `priv/templates/brando.gen` get the new
  bindings `param` (`"slug"` or `"id"`, the show route's param and the
  `show/2` params key), `site_layouts` (the CMS layouts module or nil),
  `language`, `preloads`, `alternates`, `blocks`, `id_type` and `text_field`. While either is overridden, entry
  pages keep the `:id` route, which a template copied from the old default
  matches, and the notice says so; update the template from the default to
  route by slug.

- **CMS-authored error pages render with the CMS page templates** (#3230).
  With `use_default_errors: false`, `BrandoWeb.FallbackController` rendered
  the 404 or 410 page's template (`default.html`, say) with the view of the
  controller that found nothing, so from any controller but the page
  controller it raised instead of rendering the 404; and running the
  `:browser` pipeline put phx.new's root layout over the site's. It now
  renders with `:page_html_module` (or `YourWeb.PageView`/`PageHTML`, as the
  page template list finds them) in the root layout the controller had chosen.
  The fallback's `put_namespace_layout` plug, which never ran, is removed.

- **A page title in a language without an identity no longer raises**
  (#3230). `Brando.Utils.get_page_title/1`, which `Brando.HTML.head/1`
  calls, matched the identity's title prefix on the empty map the identity
  cache gives a language with no identity, so a page with a title in such a
  language raised `MatchError`. It renders the bare title.
