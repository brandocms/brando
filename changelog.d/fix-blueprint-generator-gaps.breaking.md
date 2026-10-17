- **A slug input with `from:` or `for:` fails to compile** (#3229). The slug
  input reads the field it is built from only from `source:`; `from:` (which
  `mix brando.gen.blueprint` used to write) and `for:` (the 0.53 name) were
  accepted and ignored, so the slug never filled in. Write
  `input :slug, :slug, source: :title`. A `blocks` inside a `tab`, `fieldset`
  or `inputs_for`, which compiled and was dropped, now fails to compile too:
  move it directly under `form do`. Other unknown input options are still
  accepted.
