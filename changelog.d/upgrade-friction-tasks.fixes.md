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
  too, only in Elixir code: EEx tags, HEEx expressions and parsed `.ex`
  code, never a `<script>` or text. The task then warns, by file and line,
  about other Villain `html` reads, navigation items read as 0.53 structs (`item.url`), and
  `Brando.Pages.get_var/2` calls, whose page must be loaded with
  `preload: [:vars]`.

- **`Brando.Pages.get_var/2` and `has_var?/2` say when page vars are not
  loaded.** They raised a `Protocol.UndefinedError` on
  `%Ecto.Association.NotLoaded{}`; they now raise an `ArgumentError` naming
  `preload: [:alternate_entries, :vars]`. `get_page` still loads only what it
  is asked for. The 404 and 410 pages load their vars, and `has_var?/2`
  returns `false`, not `nil`, for a page without vars.

- **`mix brando.migrate54` replaces generated admin Create/Update LiveViews
  with one FormLive.** 0.54 Blueprints link to `admin_<singular>_form_path`,
  so a site still routing `<Name>CreateLive`/`<Name>UpdateLive` had listings
  that crashed. A pair the generator wrote and nobody edited (any generator
  version since 2021) becomes `<Name>FormLive` from the `brando.gen`
  template, the pair is deleted, and its routes become
  `live "...", <Name>FormLive, :create` and `:update`. Edited pairs, pairs
  whose routes are not plain `live` lines, FormLives that would share a
  route helper (two schemas with the same singular, outside a scope with
  `as:`), and other code still naming a removed module are listed with the
  fix. The commented example routes in the install template's router now
  use a FormLive too.

- **`mix brando.migrate55` keeps the translations of Blueprint strings.**
  0.53 translated a Blueprint's strings into `<domain>_<schema>_naming`,
  `_forms` and `_listings`; 0.55 extracts them to `<domain>_<schema>`. The
  migration guide's `gettext.extract --merge` wrote the new catalogs empty and
  emptied the old ones, so nothing was left for `scripts/sync_gettext.sh` to
  copy. The task now copies each translated message into the new domain's
  `.po` file in every backend and locale, where the merge keeps it, and
  reports messages the old domains translated differently. The guide now
  extracts once and merges each backend with `mix gettext.merge DIR --locale`,
  because `gettext.extract --merge DIR --locale` merges every backend and
  creates the locale in each.
