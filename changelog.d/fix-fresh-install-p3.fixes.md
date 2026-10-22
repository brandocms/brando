- A navigation link to a front page is active only on that front page
  ([#3234](https://github.com/brandocms/brando/pull/3234)).

- Pages from `mix brando.gen --public-route` sit in the site's container
  ([#3234](https://github.com/brandocms/brando/pull/3234)).
  In an existing site's `modules.css`, add `.page-section` to the `main > [b-tpl]` and `main >
  [b-tpl] > .inner` rules, add `main > .page-section:first-child { @space padding-top xl; }`, and
  regenerate or edit the HTML modules.

- The installed frontend build no longer prints `[PLUGIN_TIMINGS]`
  ([#3234](https://github.com/brandocms/brando/pull/3234)).
  In an existing site, add `checks: { pluginTimings: false }` under `build.rolldownOptions` in the
  frontend `vite.config.js`.
