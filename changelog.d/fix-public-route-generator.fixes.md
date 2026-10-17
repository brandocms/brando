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
  the Blueprint's block fields after its title. For a Blueprint with a
  `language` field the context gets `language` filter and match clauses and
  the pages show the request's language, so translations can share a slug.
  The notice says what to wire by hand without the CMS site, prints the
  `absolute_url` that matches the route when the Blueprint has
  `absolute_url false`, and mentions `--public-route` only when it was not
  given.

- **CMS-authored error pages render with the CMS page templates** (#3230).
  With `use_default_errors: false`, `BrandoWeb.FallbackController` rendered
  the 404 or 410 page's template (`default.html`, say) with the view of the
  controller that found nothing, so from any controller but the page
  controller it raised instead of rendering the 404; and running the
  `:browser` pipeline put phx.new's root layout over the site's. It now
  renders with `:page_html_module` (or `YourWeb.PageView`/`PageHTML`, as the
  page template list finds them) in the root layout the controller had chosen.
  The fallback's `put_namespace_layout` plug, which never ran, is removed.
