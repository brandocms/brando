- Liquid in text and Markdown refs, vars, globals and captions prints as text, also in HEEx modules.
  Run `mix brando.doctor`, move what should run (listed under Liquid in editor text) into the module's code, and run `mix brando.entries.resave`.

- Liquid templates print `entry`, `identity`, `navigation`, ref data and datasource `entries` as escaped text; rich-text fields print sanitized.
  Add `| raw` where a template prints a plain field that holds markup on purpose: `{{ entry.embed | raw }}`.
  A project's filter that returns markup for a record returns `{:safe, html}`, a record it returns reads like entry data, and a map it builds from `block`, `globals` or a multi module entry's `vars` it wraps with `Brando.Villain.TemplateView.wrap/2`; a project's tag reads its argument with `Brando.Villain.TemplateView.eval/2`.
