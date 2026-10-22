- `mix brando.install` moves the application's version to a `VERSION` file, where Florist reads it,
  and adds `:brando` to `import_deps` in `.formatter.exs`
  ([#3199](https://github.com/brandocms/brando/pull/3199)).

- `mix brando.gen.site` adds the site's 404 and 500 pages and a lockdown page at `/coming-soon`, so
  `lockdown: true` no longer crashes ([#3199](https://github.com/brandocms/brando/pull/3199)).
  Rerun `mix brando.gen.site` on an existing site to add the lockdown page.
