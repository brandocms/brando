- **A Blueprint from `mix brando.gen.blueprint` fills its slug from the
  title and starts new entries as drafts** (#PR). The generated slug input
  read its field from `from:`, which no input reads, so the slug stayed empty
  and the form failed validation until it was typed by hand. It now uses
  `source: :title`. The generated form also sets
  `default_params %{"status" => "draft"}`, so a new entry no longer starts
  with no status.

- **A `blocks` declared inside a `tab`, `fieldset` or `inputs_for` fails to
  compile** (#PR). It compiled and was dropped, leaving an empty fieldset and
  no block editor. A block editor renders as its own form after the entry
  form, so `blocks` belongs directly under `form do`; the error says so and
  why.
