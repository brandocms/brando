- With tenancy, a site's absolute URLs (canonical and alternate links, `og:url`, the `.md` alternate, JSON-LD `@id`s and URLs, sitemap entries and index, IndexNow) name the host of the environment rendered, and a static build's pages the built environment's domain, instead of the endpoint's host.
  `Brando.Utils.hostname/0` now returns that base URL. Replace a `*_url` route helper or `url(~p"…")` that builds a link to the site's own pages with `Brando.Utils.hostname(path)`; keep the endpoint's URL for links into the admin.

- `put_hreflang/2` with a list of paths, as its documentation shows, no longer raises, and with `{helper, args}` gives absolute alternate URLs.
