- `mix brando.migrate54` removes or repairs the Phoenix.View-era `ErrorHelpers`, `view/0` and
  `view_helpers/0` that stop a pre-1.7 site's first compile on `use Phoenix.HTML`
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
  When it keeps them, add `{:phoenix_html_helpers, "~> 1.0"}` to `mix.exs`.
