- A page's canonical link, `og:url`, own-language alternate and JSON-LD `@id`s and `url`s now name one URL, the entry's, without a trailing slash, however the page was requested (`/about/`, a query string, a static build): `@id`s are `https://example.com/about#webpage`, no longer `…/about/#webpage`.

- The 404 and 410 pages, and other error responses, get no canonical link, `og:url` or JSON-LD `WebPage` node, which named the requested path (on a static build, the build's probe path for every missing page).
