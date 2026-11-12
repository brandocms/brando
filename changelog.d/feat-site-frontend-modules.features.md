- Each site can render in its own root layout and page templates: register a `Brando.Site.Frontend` module per site key (or per site and environment) in `site_frontends`, with `default_site_frontend` as the fallback, and add `Brando.Plug.SiteFrontend` after `Brando.Plug.Tenant`; the template selector, 404 and 410 pages follow the site's templates, and in `:multi` a site with no entry answers 404 once the registry has one.

- A live preview target's `layout` takes a function of the entry, as `template` does, and `site_assigns true` gives the preview the site's layout and page assigns.
