- **`mix brando.migrate54` moves Villain editors to form-level `blocks`.**
  It replaced `attribute :data, :villain` with a `:blocks` relation but left
  `input :data, :blocks` in its fieldset, which then referenced an unknown
  field. The input now becomes `blocks :blocks` on the form, with its
  options, and a fieldset or tab it leaves empty is removed. Rerunning the
  task moves an input an earlier run left behind.

- **`mix brando.migrate54` points templates at `rendered_blocks`, and lists
  the template code 0.54 breaks.** A Blueprint moved from Villain lost its
  `html` field, so `@entry.html |> raw` failed on every page. In the schema's
  own templates (`<singular>_html/`, `templates/<singular>/`), reads of
  `entry`, `@entry` or the singular are rewritten to `rendered_blocks`
  (`hero_html` to `rendered_hero_blocks`), and `@page.html` in page templates
  too. The task then warns, by file and line, about other Villain `html`
  reads, navigation items read as 0.53 structs (`item.url`), and
  `Brando.Pages.get_var/2` calls, whose page must be loaded with
  `preload: [:vars]`.

- **`Brando.Pages.get_var/2` and `has_var?/2` say when page vars are not
  loaded.** They raised a `Protocol.UndefinedError` on
  `%Ecto.Association.NotLoaded{}`; they now raise an `ArgumentError` naming
  `preload: [:alternate_entries, :vars]`. `get_page` still loads only what it
  is asked for. The 404 and 410 pages load their vars, and `has_var?/2`
  returns `false`, not `nil`, for a page without vars.
