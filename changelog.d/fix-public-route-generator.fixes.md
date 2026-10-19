- Pages from `mix brando.gen --public-route` belong to the CMS site: its pipeline, lockdown, layout
  and 404 page, a slug route when the Blueprint has a slug, and routes per language
  ([#3230](https://github.com/brandocms/brando/pull/3230)).
  Rerun the generator after adding a language, or on routes generated before the language scopes, to
  add the missing scopes.

- `brando.gen` templates overridden in `priv/templates/brando.gen` keep entry pages at `:id`
  ([#3230](https://github.com/brandocms/brando/pull/3230)).
  Update an overridden `controller.ex` or `html.ex` from the default to route by slug.

- With `use_default_errors: false`, CMS-authored 404 and 410 pages render with the CMS page
  templates from any controller ([#3230](https://github.com/brandocms/brando/pull/3230)).

- A page title in a language without an identity no longer raises `MatchError`
  ([#3230](https://github.com/brandocms/brando/pull/3230)).
