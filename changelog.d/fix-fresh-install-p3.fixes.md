- **A navigation link to `/` is active only on the front page**. `menu_item`
  matched a link to `/` against `/*`, so a Home item carried
  `data-link-active` on every page. Other links still match their subpages.

- **Pages from `mix brando.gen --public-route` sit in the site's container**.
  The generated index and entry pages wrap their heading, list and back link
  in `.page-section` wrappers and render the blocks as direct children of
  `main`, so both get `@space container;` like the seeded modules. The
  installed `modules.css` styles `main > .page-section` with the module rule;
  in an existing site, add `.page-section` to the `main > [b-tpl]` and
  `main > [b-tpl] > .inner` rules, and regenerate or edit the HTML modules.

- **The installed frontend build no longer prints `[PLUGIN_TIMINGS]`**. The
  frontend `vite.config.js` turns off Rolldown's plugin timing check, which
  `vite-plugin-eslint` tripped on every `pnpm build`. In an existing site, add
  `checks: { pluginTimings: false }` under `build.rolldownOptions`.
