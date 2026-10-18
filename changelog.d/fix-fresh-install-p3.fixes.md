- **A navigation link to a front page is active only on that front page**
  (#3234). `menu_item` matched a link to `/` against `/*`, and a link to a
  language's front page (`/no`, `/no/`) against `/no/*`, so a Home item
  carried `data-link-active` on every page of the site or language. A front
  page link now matches only its front page, also when the locale plug's
  `force_path` adds the language to the path. Other links still match their
  subpages.

- **Pages from `mix brando.gen --public-route` sit in the site's container**
  (#3234). The generated index and entry pages wrap their heading, list and
  back link in `.page-section` wrappers and render the blocks as direct
  children of `main`, so both get `@space container;` like the seeded modules,
  and the heading gets the seeded hero's `@space padding-top xl;` below the
  navigation. The installed `modules.css` styles `main > .page-section` with
  the module rule; in an existing site, add `.page-section` to the
  `main > [b-tpl]` and `main > [b-tpl] > .inner` rules, add
  `main > .page-section:first-child { @space padding-top xl; }`, and
  regenerate or edit the HTML modules.

- **The installed frontend build no longer prints `[PLUGIN_TIMINGS]`**
  (#3234). The frontend `vite.config.js` turns off Rolldown's plugin timing
  check, which `vite-plugin-eslint` tripped on every `pnpm build`. In an
  existing site, add `checks: { pluginTimings: false }` under
  `build.rolldownOptions`.
