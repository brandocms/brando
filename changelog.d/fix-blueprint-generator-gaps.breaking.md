- **A slug input with `from:` or `for:` fails to compile** (#3229). The slug
  input reads the field it is built from only from `source:`; `from:` (which
  `mix brando.gen.blueprint` used to write) and `for:` (the 0.53 name) were
  accepted and ignored, so the slug never filled in. Write
  `input :slug, :slug, source: :title`. `mix brando.migrate55` rewrites both
  to `source:` (or removes them beside a `source:`) and lists each line it
  changed. It does not rewrite an application's own copy of the generator
  template, `priv/templates/brando.gen.blueprint/blueprint.ex`, which is EEx:
  it lists the slug inputs there that still name `from:` or `for:`, to change
  by hand. A `blocks` inside a `tab`, `fieldset` or `inputs_for`, which
  compiled and was dropped, now fails to compile too: move it directly under
  `form do`. Other unknown input options are still accepted.
