- `mix brando.migrate54` adds `:vars` to the `preload` of `Pages.get_page/1` calls when a template
  reads `get_var/2` or `has_var?/2` on `@page`, and lists the loads it cannot update
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
