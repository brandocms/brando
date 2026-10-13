- **`mix brando.migrate54` preloads page vars read on `assigns[:page]`.**
  The task added `:vars` to `Pages.get_page/1` options only when a template
  read vars on `@page`; a layout reading `Brando.Pages.get_var(assigns[:page],
  …)` left every page load without it. Reads on `assigns[:page]` and
  `assigns.page` now count, and when vars are read on something other than
  the page, the `Pages.get_page/1` calls are listed with file and line
  beside the reads.

- **`mix brando.migrate54` merges a Create/Update pair whose header is plain
  text.** A pair was left for hand-merging when its `<:header>` slot held
  text such as `Opprett artikkel` instead of a `gettext` call. The 0.55 form
  shows no header, so text and expressions in the slot no longer count as an
  edit; markup still does.

- **`mix brando.migrate54` scopes flat admin routes that share a route
  helper.** Two FormLives with the same name in different domains
  (`Articles.CategoryFormLive`, `Projects.CategoryFormLive`) share
  `admin_category_form_path`. The task fixed this only for a plain domain
  scope; routes listed flat in `admin_routes`, as the 0.53 generator wrote
  them, were listed. A domain's adjacent flat routes are now wrapped in
  `scope "/projects/categories", MyAppAdmin.Projects, as: :projects do`, and
  its Blueprints get `router_scope: :projects`. Routes with another route
  between them are still listed, with the reason.

- **`mix brando.migrate54` converts more legacy listing templates.** Markup
  after the update link goes into `update_link`'s `:outside` slot,
  `{% for c in entry.categories %}` becomes
  `:for={c <- @entry.categories || []}`, Liquid outputs in attributes become
  expressions, and `entry.a[0]` reads `Enum.at(@entry.a || [], 0)`. A loop
  variable that shadows `entry` is read as the loop variable.

- **A list and a selection datasource may share a name again.** 0.53 allowed
  `list :all` beside `selection :all`, and content modules store a
  datasource's type beside its name. Since 0.54 the Blueprint refused to
  compile `datasource :all` twice. Names are now unique per type, and every
  lookup passes the type (`Brando.Datasource.list_results/5`; without one,
  the list is found first).

- **`mix brando.migrate54` keeps `Ecto.Query` imported.** Removing
  `use Brando.Datasource` also removed its `import Ecto.Query`, so a
  datasource callback with `from t in …` no longer compiled. A Blueprint
  whose functions call Ecto.Query's macros now gets `import Ecto.Query` in
  the `use`'s place, which replaces a partial `import Ecto.Query, only: […]`.

- **`mix brando.migrate54` writes readable meta and datasource functions.**
  A captured mutator such as `&encode_locale/1` is called by name,
  `encode_locale(get_in(entry, [Access.key(:language)]))`, instead of
  `(&encode_locale/1).(value)`.

- **`mix brando.migrate55` splits a Plural-Forms rule that ran into the next
  header.** Older Poedit releases wrote the Plural-Forms line without its
  `\n`, so Gettext read `plural=(n != 1);X-Generator: Poedit 3.0.1` and
  warned once per catalog per compile although the rule was complete. The
  task reads the header with Expo, gives the rule a line of its own, and
  drops text that is no header (a stray `"3.0.1;\n"`) or a header set again
  later.

- **`mix brando.migrate55` reads `:entries` inputs' `sources:` when deciding
  `persist_identifier`.** A join schema was listed for a decision because the
  file with the `:entries` input named it elsewhere (in a `has_many`). Only a
  Blueprint an input's `sources:` names, or any Blueprint when the sources
  cannot be read, is kept now, so join schemas get `persist_identifier
  false`.

- **`mix brando.migrate55` copies Blueprint translations only into the
  Blueprint's Gettext backend.** Catalogs were created in every backend that
  had a 0.53 `_naming`, `_forms` or `_listings` catalog, including the
  frontend's, where nothing reads them and `mix brando.gettext.reconcile`
  left them as orphans.

- **A `:single` datasource's options are listed again.** The assistant's
  `list_selection_options` and the `set_block_selection` check looked up the
  `:selection` datasource only, so a module on a `:single` one showed no
  options and valid choices were refused.

- **`mix brando.doctor` checks the sender each site sends from.** A site's
  own placeholder sender beside a valid general one went unreported, and a
  placeholder general sender failed a site that sends from its own.

- **`mix brando.migrate55` reads `Config.config_env()` in runtime.exs.** A
  Repo URL read only under `if Config.config_env() == :e2e` was listed as
  one `mix test` reads.

- **A `:single` datasource block renders its chosen entry.** The assistant
  can choose the entry of a `:single` datasource block, but both template
  adapters rendered only `:list` and `:selection` datasources, so the block
  showed nothing. It now renders the entry the datasource's `get` returns
  for the block's first identifier, as `entries`.
