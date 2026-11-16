- With tenancy, a site's absolute URLs (canonical and alternate links, `og:url`, the `.md` alternate, JSON-LD `@id`s and URLs, sitemap entries and index, IndexNow) name the host of the environment rendered, and a static build's pages the built environment's domain, instead of the endpoint's host.
  `Brando.Utils.hostname/0` now returns that base URL. Replace a `*_url` route helper or `url(~p"…")` that builds a link to the site's own pages with `Brando.Utils.hostname(path)`; keep the endpoint's URL for links into the admin.

- What is stored or cached for a site names its public base URL, the live environment's domain (`Brando.Utils.public_hostname/0`), so it stays right across a live switch and a copy: JSON-LD from the `json_ld` filter and `<.json_ld>` in block HTML, the sitemap files and the identity's service URLs. Changing the live environment's domain renders those blocks again in every environment of the site.

- "Generate sitemap", and `Brando.Sitemap.generate_sitemap/1` in any environment of a site, generate from the site's live environment, which the utilities screen names when another is selected.

- `put_hreflang/2` with a list of paths, as its documentation shows, no longer raises; with `{helper, args}` it keeps the alternates as paths for `<.alternate_url>`, and the alternate link tags in the head get the site's base URL.
