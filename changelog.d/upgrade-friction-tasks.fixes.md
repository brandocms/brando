- `mix brando.migrate54` moves a Villain `input :data, :blocks` to a form-level `blocks :blocks`
  ([#3161](https://github.com/brandocms/brando/pull/3161)).

- `mix brando.migrate54` rewrites template reads of a Villain `html` field to `rendered_blocks`, and
  lists the template code 0.54 breaks ([#3161](https://github.com/brandocms/brando/pull/3161)).

- `Brando.Pages.get_var/2` and `has_var?/2` raise an `ArgumentError` naming `preload:
  [:alternate_entries, :vars]` when page vars are not loaded, and `has_var?/2` returns `false` for a
  page without vars ([#3161](https://github.com/brandocms/brando/pull/3161)).
  Preload `:vars` wherever you load a page whose vars you read.

- `mix brando.migrate54` replaces generated admin Create/Update LiveViews with one FormLive and its
  routes, and lists edited pairs with the fix
  ([#3161](https://github.com/brandocms/brando/pull/3161)).

- `mix brando.migrate55` copies Blueprint string translations from the 0.53 `_naming`, `_forms` and
  `_listings` catalogs into the new `<domain>_<schema>` catalogs
  ([#3161](https://github.com/brandocms/brando/pull/3161)).
