- A slug input with `from:` or `for:` fails to compile
  ([#3229](https://github.com/brandocms/brando/pull/3229)).
  Write `input :slug, :slug, source: :title`; `mix brando.migrate55` rewrites both options.
  The task only lists the slug lines in an application's own
  `priv/templates/brando.gen.blueprint/blueprint.ex`: change those by hand.

- A `blocks` inside a `tab`, `fieldset` or `inputs_for` fails to compile
  ([#3229](https://github.com/brandocms/brando/pull/3229)).
  Move it directly under `form do`.
