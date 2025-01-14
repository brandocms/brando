## 0.54.0

Before running the migration script, you must fix some `form` syntax in your blueprints.
If you're passing parameters to the `form` macro, they must be moved to their own functions.
For instance, if you have:

```elixir
form default_params: %{"status" => "draft"} do
  # ...
end
```

You must change this to:

```elixir
form do
  default_params %{"status" => "draft"}
  # ...
end
```

Then pull down migration changes with `mix brando.upgrade`.

Commit all changes before running the migration script with `mix brando.migrate54`

Then run migrations with `mix ecto.migrate`

Finally resave entries with `mix brando.entries.resave`, sync identifiers with `mix brando.identifiers.sync`
then sync translations with `chmod +x scripts/sync_gettext.sh` then `./scripts/sync_gettext.sh priv/gettext/backend/no/LC_MESSAGES`
if your translations are in `priv/gettext/backend/no/LC_MESSAGES`.

* BREAKING: Add `config :brando, repo_module: MyApp.Repo` to your `config/brando.exs`

* BREAKING: If you upgrade to Vite 5+, they have moved the default manifest directory to `.vite`.
  To fix, edit your `assets/front/vite.config.js` and replace `manifest: true`
  with `manifest: 'manifest.json`.

* BREAKING: Changed Listings dsl (moved to Spark). See full example in listings.md in guides.

* BREAKING: Changed JSON-LD dsl (moved to Spark). See full example in jsonld.md in guides.
  `json_ld_field` has been renamed to `field`

* BREAKING: Changed Meta dsl (moved to Spark). See full example in meta.md in guides.
  `meta_field` has been renamed to `field`

* BREAKING: Run `mix brando.identifiers.sync` to create missing identifiers,
  delete orphaned identifiers and update URLs

* BREAKING: If you are updating to the new block system, resave your entries:
  `mix brando.entries.resave`

* BREAKING: The new `gettext` update requires some changes to your code.
  Replace all occurrences of
      `import MyAppAdmin.Gettext`
  with
      `use Gettext, backend: MyAppAdmin.Gettext`

  Also update your app's `gettext.ex` from
      `use Gettext, otp_app: :my_app, priv: "priv/gettext/backend"`
  to
      `use Gettext.Backend, otp_app: :my_app, priv: "priv/gettext/backend"`

* BREAKING: Consolidated admin `Create` and `Update` views to `Form`. If you have
  any custom logic in your `Create` view, move this to your `Update` view and add a
  conditional check in your mount:
  ```
  if socket.assigns.live_action == :create do
    # ...
  end
  ```
  Then add a conditional check for the heading in your `render`:
  ```
  <%= if @live_action == :create do %>
    <%= gettext("Create project") %>
  <% else %>
    <%= gettext("Update project") %>
  <% end %>
  ```
  Then rename your `Update` view to (i.e.) `ProjectFormLive` and delete your `Create` view,
  finally change your routes in your `router.ex`:
  ```
  scope "/projects", MyAppAdmin.Projects do
    live "/projects", ProjectListLive
    live "/projects/create", ProjectFormLive, :create
    live "/projects/update/:entry_id", ProjectFormLive, :update
  end
  ```

* BREAKING: Simplified `:entries` (for related entries) -- removed the indirection
  of adding `_identifiers` to the assoc's name, so if you have
  ```
  relation :related_entries, :entries, constraints: [max_length: 3]
  ```
  in your code, there will be no auto generated `:related_entries_identifiers`. This means
  the `:related_entries` will be the join table between your schema and the identifiers table.
  ```
  identifiers = Enum.map(case.related_entries, &1.identifier)
  case_ids = Enum.map(case.related_entries, &1.identifier.entry_id)
  related_cases = Cases.list_cases!(%{matches: %{ids: ids}})

  # or
  identifiers = Enum.map(case.related_entries, &1.identifier)
  Brando.Content.get_entries_from_identifiers(identifiers, %{preload: [:categories, :cover]})
  ```

* BREAKING: `Brando.Villain.list_villains/0` is now `Brando.Villain.list_blocks/0`
* BREAKING: change `trait Brando.Trait.Villain` to `trait Brando.Trait.Blocks`
* BREAKING: remove old `data` attributes with type `:villain` and add has_many relation `:blocks`:

    relations do
      relation :blocks, :has_many, module: :blocks
    end

* BREAKING: added `url` field to identifiers. Go through your blueprints and ensure
  that `persist_identifier false` is set for all schemas you don't want to create identifiers for.

  Run `mix brando.identifiers.sync` to create missing identifiers, delete orphaned identifiers and update URLs

* BREAKING: added `link` type vars to navigation items. You can iterate menu items with some new components:
  ```
  <section :if={assigns[:navigation]} class="main">
    <ul>
      <.menu :let={item} menu={@navigation}>
        <li>
          <.menu_item :let={text} conn={@conn} item={item}>
            <%= text %>
          </.menu_item>
        </li>
      </.menu>
    </ul>
  </section>
  ```

* BREAKING: added `<.head>` component. Switch out your regular `<head>` in your frontend app with this to take advantage of properly ordered head elements:
  ```
  <.head
    conn={@conn}
    fonts={[{:woff2, "/fonts/MyFont-Regular.woff2?vsn=d"}]}
  >
    <:prefetch>
      <link href="//player.vimeo.com" rel="dns-prefetch" />
    </:prefetch>

    <link rel="shortcut icon" href="/ico/favicon.ico" />
    <meta name="format-detection" content="telephone=no" />
  </.head>
  ```

* Added `wrapped_labels` option to multi select.


## 0.53.0

* BREAKING: Switch out `import Phoenix.LiveView.Helpers` with `import Phoenix.Component`

* Upgrade deps:
  ```
  {:phoenix_live_view, "~> 0.20"},
  {:phoenix_live_dashboard, "~> 0.8"},
  ```

* BREAKING: If you upgrade to Vite 3, they suddenly output `admin/main.css` instead of `admin/admin.css`.
  To fix, edit your `assets/backend/vite.config.js` and replace `manifest: false`
  with `manifest: 'admin_manifest.json`. You can also add in a hash since we now use a manifest:
  ```
  entryFileNames: `assets/admin/admin-[hash].js`,
  chunkFileNames: `assets/admin/__[name]-[hash].js`,
  assetFileNames: `assets/admin/admin-[hash].[ext]`
  ```

* BREAKING: Svelte's Vite plugin is requiring type = module now so there are some changes to do:
  - Upgrade Vite + plugins > 4
  - Set `assets/backend/package.json` type to `module` -> `"type": "module"`
  - Rename `assets/backend/postcss.config.js` to `assets/backend/postcss.config.cjs`
  - Rename `assets/backend/europa.config.js` to `assets/backend/europa.config.cjs`
  - Upgrade `assets/backend` europacss to `> 0.12`

* BREAKING: Updated Sentry to 10.x. Add to your `Dockerfile` before mix release:

    RUN mix sentry.package_source_code
    RUN mix release

  Then remove the `included_environments` key from the `:sentry` config in `config/prod.exs``
  and copy the sentry cfg to other env configs you might want to enable sentry on,
  for instance `config/staging.exs`.

* BREAKING: Change Presence module — in your `lib/my_app/presence.ex`:

    use BrandoAdmin.Presence,
      otp_app: :my_app,
      pubsub_server: MyApp.PubSub,
      presence: __MODULE__

* To enable presence in your update forms, add `presences={@presences}` to your
  `Form` live components in update views:

  ```
  <.live_component module={Form}
    id="page_form"
    entry_id={@entry_id}
    current_user={@current_user}
    presences={@presences}
    schema={@schema}>
    <:header>
      <%= gettext("Edit page") %>
    </:header>
  </.live_component>
  ```

* BREAKING: Replace `<%= csrf_meta_tag %>` with ´<.csrf_meta_tag />`

* BREAKING: Switch out `<%= google_analytics(...) %>` calls in your code with
  `<.google_analytics code="...." />

* BREAKING: Dropped `use Phoenix.HTML` so your `error_tag` in `error_helpers.ex` won't
  work anymore. Check out https://github.com/phoenixframework/phoenix/blob/main/installer/templates/phx_web/components/core_components.ex for how to implement errors in the frontend.

* BREAKING: If updating frontend to Vite 5, you need to explicitly set the manifest path.
  So change `manifest: true`, to `manifest: 'manifest.json'`

* BREAKING: Rewritten `:entries` (related entries). Now stores identifiers in a table and
  references this table for related entries.

  Blueprint setup is same as before:

      relation :related_entries, :entries, constraints: [max_length: 3]

  and form setup:

      input :related_entries, :entries,
        label: t("Related entries"),
        sources: [{__MODULE__, %{preload: [], order: "asc title", status: :published}}],
        filter_language: true


* BREAKING: Datasources — *selection* list callback should return identifiers
  instead of entries, and the select callback itself receives identifiers as the
  sole argument:

  ```elixir
  selection :featured,
    fn schema, language, _vars ->
      Brando.Content.list_identifiers(schema, %{language: language})
    end,
    fn identifiers ->
      entry_ids = Enum.map(identifiers, & &1.entry_id)

      results =
        from t in __MODULE__,
          where: t.id in ^entry_ids,
          order_by: fragment("array_position(?, ?)", ^entry_ids, t.id)

      {:ok, MyApp.Repo.all(results)}
    end
  ```

* BREAKING: Updated `mix brando.upgrade` script. Copy the new script into
  your application:

  ```zsh
  $ cp deps/brando/priv/templates/brando.install/lib/mix/brando.upgrade.ex lib/mix/brando.upgrade.ex
  ```

* BREAKING: Deprecated `:many_to_many` for now. This might return later if
  there's a usecase for it. Right now it is replaced by `:has_many` `through`
  associations instead.

  Before:

  ```elixir
  relation :contributors, :many_to_many,
    module: Articles.Contributor,
    join_through: Articles.ArticleContributor,
    on_replace: :delete,
    cast: true
  ```

  After:

  ```elixir
  relation :article_contributors, :has_many,
    module: Articles.ArticleContributor,
    preload_order: [asc: :sequence],
    on_replace: :delete_if_exists,
    cast: true

  relation :contributors, :has_many,
    module: Articles.Contributor,
    through: [:article_contributors, :contributor],
    preload_order: [asc: :sequence]
  ```

  If you use the `ArticleContributor` schema for a multi select, you must
  add `@allow_mark_as_deleted true` to this schema. Also you need to add a
  `relation_key` to the input declaration:

  ```elixir
  input :article_contributors, :multi_select,
    options: &__MODULE__.get_contributors/2,
    relation_key: :contributor_id,
    resetable: true,
    label: t("Contributors")
  ```
* BREAKING: `ErrorView` is now `ErrorHTML`. If you are using Brando's error
  templates, you must swap your endpoint's `render_errors` key with:
  ```elixir
  config :my_app, MyApp.Endpoint,
    render_errors: [
      formats: [html: Brando.ErrorHTML, json: Brando.ErrorJSON], layout: false
    ]
  ```
  Also switch out the view in your `fallback_controller.ex`:
  ```elixir
  |> put_view(html: <%= application_module %>Web.ErrorHTML)
  ```
* BREAKING: Add `delete_selected` as a built-in action for listing selections.
  This means you should remove your own `delete_selected` from your listing's
  `selection_actions`

* BREAKING: Added default actions for listings:
  - edit
  - delete
  - duplicate

  This means you should remove these from your listings (unless you want them doubled)

* BREAKING: `@identity` now refers to the current language identity, instead
  of a map of all languages
* BREAKING: Remove datasource block and introduce module blocks with
  datasource instead. Run `mix brando.upgrade && mix ecto.migrate`
  to convert your existing datasource blocks to module blocks.
* BREAKING: Admin now reads JS and CSS from `priv/static/admin_manifest.json`.
  Make sure to set this in `assets/backend/vite.config.js` to:
  `manifest: 'admin_manifest.json`
* BREAKING: CDN config is now per asset module, so instead of
  ```elixir
  config :brando, Brando.CDN, #...
  ```
  add
  ```elixir
  config :brando, Brando.Images, cdn: [enabled: false]
  config :brando, Brando.Files, cdn: [enabled: true, ...]
  ```
* BREAKING: Switch out your `<%= live_patch gettext("Create new") ...` calls
  in your list views. Replace with
  ```elixir
  <.link navigate={@admin_create_url} class="primary">
    <%= gettext("Create new") %>
  </.link>
  ```
* BREAKING: With moving to Phoenix 1.7+, we've tossed out Phoenix.View from
  Brando and use the new `embed_templates` setup instead. If your app depends
  on Phoenix.View, then you must add it as a dependency:
  ```
  {:phoenix_view, "~> 2.0"},
  ```

  You can use a prefab'ed MyAppWeb setup by replacing your `use MyAppWeb, :controller` (etc)
  with `use BrandoWeb, :controller` (etc). You can also use

  `use BrandoWeb, :legacy_controller`

  for utilizing the new layouts setup, but use regular template views.

  Convert your layout templates to heex, rename the layout view to
  `MyAppWeb.Layouts`, move it to `my_app_web/components/layouts.ex` and add

  ```elixir
  use BrandoWeb, :html

  embed_templates "components/layouts/*"
  embed_templates "components/partials/*"
  ```

  Move your partials from `templates/page` into `components/partials`,
  rename them to drop the leading `_` and reference them in your `app.html.heex`
  layout as `<.navigation {assigns} />`, `<.footer {assigns} />` etc.

* BREAKING: Update your `live_preview.ex` to the new format for setting layout
  and template:

  Old:
  ```elixir
  layout_module MyAppWeb.ProjectView
  layout_template "app.html"
  view_module MyAppWeb.ProjectView
  view_template "detail.html"
  ```

  New (for Phoenix.Template integrations):
  ```elixir
  layout {MyAppWeb.Layouts, :app}
  template {MyAppWeb.ProjectHTML, "detail"}
  # or
  template fn e -> {MyAppWeb.ProjectHTML, e.template} end
  ```

  New (for Phoenix.View integrations):
  ```elixir
  layout {MyAppWeb.LayoutView, "app.html"}
  template {MyAppWeb.ProjectView, "detail.html"}
  # or
  template fn e -> {MyAppWeb.ProjectView, e.template} end
  ```

* Use Finch for emails:
  - Add `finch` as a dep to your `mix.exs`:
  ```elixir
  {:finch, "~> 0.13"},
  ```
  - Add to your config:
  ```elixir
  config :swoosh, :api_client, MyApp.Finch
  ```
  - Add to your application supervisor in `lib/my_app/application.ex`
  ```diff
    children = [
      # Start the Ecto repository
      MyApp.Repo,
      # Start the Telemetry supervisor
      MyAppWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: MyApp.PubSub},
      # Start Finch
  +   {Finch, name: MyApp.Finch},
      # Start the Endpoint (http/https)
      MyAppWeb.Endpoint,
      # Start the Presence system
      MyApp.Presence,
      # Start the Brando supervisor
      Brando
      # Start a worker by calling: MyApp.Worker.start_link(arg)
      # {MyApp.Worker, arg},
    ]

* Add `:preview_expiry_days` config. Default is two days.
  I.e `config :brando, :preview_expiry_days, 31`
* Add alternate entries
* Add default actions to listing rows: `edit`, `delete`, `duplicate`
* Add `select` var type
* Add `video_file_options/1` callback to Villain parser. Return a kw list of
  options you want to use for video blocks.
* Add split dropdown button to form tabs for more advanced save options
* Update revisions when saving entry without redirecting
* Add scheduled publishing for revisions
* Fix max width for #content
* Presence in update forms. Add `presences={@presences}` to your
  `my_schema_update_live.ex` live view
* Automatically add uploaded gallery images to gallery
* Add `alert` and `after_save` to forms:

```elixir
forms do
  form :password,
    after_save: &__MODULE__.update_password_config/2,
    tab t("Content") do
      alert :info,
            t(
              "The administrator has set a mandatory password change on first login for this website."
            )

      fieldset do
        size :half
        input :password, :password, label: t("Password"), confirmation: true
      end
    end
  end
end

def update_password_config(entry, _current_user) do
  Brando.Users.update_user(
    entry.id,
    %{config: %{reset_password_on_first_login: false}},
    entry
  )
end
```
* Add `confirmation: <bool>` to password inputs
* Implement forced password change if user has `reset_password_on_first_login` as true in config.
  Run `mix brando.upgrade` to bring in a migration that sets this to false for existing users.
* Show media url in file assets listing
* Update villain module list when modules are added/deleted/updated
* Update relation(s) in multi select so they are available for live preview
* Allow uploading SVGs to image fields / picture blocks
* Set img `data-src` as transparent svg when we have `dominant_color`/`svg` placeholder
* Show live preview as shrinked webpage in iframe
* Reapply module ref on update
* Support showing entry URL for slug field with `show_url: true`.
* Improve pagination limits for listings


## 0.52.0

* First LV version
* Config: Add `admin_module: MyAppAdmin` to your `config/brando.exs`
* `Trait.changeset_mutator/4` is now `Trait.changeset_mutator/5`. It receives
  some additional opts from changeset, that normally would not be touched.
* Page properties are now page vars. `get_prop` -> `get_var`
* `render_sections_css` -> `render_palettes_css`
* Added input `:gallery`
* Added input `:color`
* Allow setting additional app specific cron jobs with
  ```
  config :my_app,
    cron_jobs: [
      {"0 0 * * *", MyApp.Worker.RefreshFrontpage}
    ]
  ```
* Added `Brando.Plug.Media`


## 0.51.0

* NOTE: This will be the final GraphQL/Vue version. Next version will be with LiveViews!
* Vite: Respect `hmr` config setting. Set it to `true` in your `dev.exs`, and `false` in `prod.exs`
* Query: Add `mutation :duplicate`
* Images: Add `dominant_color` to image struct.
* Revisions: Adds initial revision support.
* Publisher: Add Oban job support for scheduled publishing
* Pagination: Add `pagination: true` to generate pagination meta for `list` queries
* SSG: Add barebones start
* Villain: Replace $timestamp in Villain HTML
* Villain: Added localized date filter
* Router: Add `Brando.Plug.Fragment` to assign a map of fragments to you connection:
  ```
  plug Brando.Plug.Fragment, parent_key: "partials", as: :partials
  ```


## 0.50.0

* Query: Add `get_<schema>!` version that raises on no result
* Query: Add `insert/update/delete` mutations. See `UPGRADE.md`
* Query: Add `cache` to `get_*`
* Query: Add joined `order_by`:

    `{:ok, posts} = list_posts(%{order: [{:asc, {:comments, :title}]})`

* Soft Delete: Add cron job to check for expired soft deleted entries
* Villain: Removed markdown parsing from `Text` blocks.
* Villain: Refactored `templates` as `modules`, see `UPGRADE.md`
* Villain: Add `{% hide %}` tag for hiding content only in the Villain Editor.
* Router: Add `admin_routes/0` and `page_routes/0`
* Router: Add `:put_extra_secure_browser_headers`
* Frontend: Add Vite tooling, see `UPGRADE.md`
* Releases: Improved `ReleaseTasks` -- works better with Elixir releases


## 0.49.0

* BREAKING: Removed `mogrify`/`imagemagick` -- use `sharp-cli`/`sharp` instead.
* Move to mix releases from Distillery for new project template.
* Add `webp` processing to `png` and `jpeg` assets. Falls back to `png`/`jpeg`
  if browser does not support webp.
* Add `?vsn=d` to all `fonts.pcss` URLs to fix fonts not caching.
* Dynamic redirects.
* Live preview: Changed syntax - see UPGRADE.md
* Live preview: Now sends entry diffs on update to save some bandwidth
* Live preview: Send base64 of images on entry creation
* Villain: Added telemetry for `parse_and_render`
* Try to rotate images by EXIF info on upload
* Add system startup warnings to Brando JS
* Better Villain template authoring experience
* Add `Brando.HTML.preload_fonts/1`


## 0.48.0

* Switch to Liquex.
  `{% for item <- entry.items %}` -> `{% for item in entry.items %}`
  `${global:category_key.global_key}` -> `{{ globals.category_key.global_key }}`
  `${menu:main.en}` -> `{{ navigation.main.en }}`

  Brando checks for old syntax and warns on system startup.

* Villain: Allow undeleting refs in template blocks
* BrandoJS/config: allow `templates` config to be a function. Gets called with `page`
* Add `Brando.Type.Video` with corresponding `KInputVideo`
* Cache navigation menus
* Add Query cache. `Page.list_pages(%{status: :published, cache: true})`
* Add `sizes: "auto"` to `picture_tag`
* Removed `Brando.Registry` and old i18n logic
* English translations for BrandoJS
* Set image meta editing as default true on Image fields in BrandoJS
* Inject `--aspect-ratio` css var for `video_tag`
* Add `address2` and `address3` in `Identity` for extra address lines
* Add `navigation` to villain templates context
* Optimized sequencing query. Now only performs a single query
* Add cache option to `Brando.Query` list functions


## 0.47.0

* Add page properties.
* Fix ordering of translation fragments
* Fix lightbox src with lazyload in `picture_tag`
* Rerender matching templates in Villains when updating globals or identity
* Add `render_caption` callback to Villain parser. Picture blocks call this to render captions.
* Set fehn 3.0 as default Docker image (Ubuntu 20.04)
* Allow parsing RFC 3339z datetime strings in date filter
* Add sitemap logic, `Brando.Sitemap`.
* Add `oban` for cron jobs.
* Add `orientation` filter
* Dynamic navigation V1
* Cleaned up `Brando.Pages.get_page/*` functions
* Added `publish_at` logic to pages.
* Use `imageType` fragment in generator
* Add `select` logic to `Brando.Query`
* Fix nonstandard module naming bugs in generator (NNCA would become Nnca etc)


## 0.46.0

* New parser for template language!
* Added CDN image uploads.
* Deprecated `Pages.list_page_fragments_translations`. Use `Pages.list_fragments_translations` instead.
* Switch frontend bundler to Rollup
* Renamed `User.full_name` to `User.name`. Requires BrandoJS to be updated.


## 0.45.0

* Rewrote upload handling. **Requires** latest BrandoJS to work!
* Please ensure that `|> generate_html()` appears LAST in your schema's `changeset` functions.
  This is to ensure that any `${entry:field}` interpolation passes successfully!
* Mandatory /2 for all parser functions. Second argument is an options list.
  Mostly for futureproofing and caching templates
* Optimized Dockerfile templates.
* `picture_tag` moved `moonwalk` to `<picture>` tag instead of `<img>`
* Simplify needed `brando.exs` config
* Removed deprecated `Brando.Config` genserver.
* Started laying the foundation for authorization. See `UPGRADE.MD`
* Rename mix task `brando.gen.html` -> `brando.gen`
* Add `meta_image` field to `Brando.Page`
* Add `Brando.Datasource`
* Smarter Dockerfile layer caching
* Add globals to identity configuration
* Add variables to Villain templates
* Improve default backend eslint configuration
* Add creator switch to generator
* Copy static files in development
* New JS backend — BrandoJS
* Add `Brando.Datasource`. Allows you to access preset backend queries from Villain.
* Simplify Villain default parser. Now you can `use Brando.Villain.Parser`
for sensible defaults, and override when neccessary.
* KInputTable: Rename `newRows` -> `addRows`


### DEPRECATIONS

* Move `put_creator` to after `cast` but before `validate_required` in your
  changeset functions.


## 0.44.0

* Drag and drop sequence pages.
* Ensure all jpg files are written as `.jpg`
* Move to local backend JS for tighter integration.
* Generator now generates a more complete `staging` config
* Generator separates out the form for backend schemas
* GraphQL rewrite to use Dataloader internally, also when using `brando.gen.html`
* Rename `Brando.Field.ImageField` -> `Brando.Field.Image.Schema`
* Rename `Brando.Field.FileField` -> `Brando.Field.File.Schema`


## 0.43.0

* Add `Brando.HTML.init_js()`
* Change potentially long identity fields to `:text`.
* Adds custom meta from `identity` setup to page


## 0.42.0

* Moved js deps to `@univers-agency` package scope.
* `Brando.User` is now `Brando.Users.User` for consistency.
* In `session_controller.ex`, ensure user has not been soft deleted in `create/3`
* Soft deletion fields have been added.
* Switch out the `:hmr` logic for `css` and `js`
* Run startup checks
* More advanced META and JSONLD handling.
* Added SHARP image processing. Choose this for the fastest/highest quality
* Removed all `import Brando.Images.Optimize` and `optimize/2` in changeset functions.


## 0.41.0

* Tables have been renamed.
* Fragments now belong to pages.


## 0.40.0

* Copy the brando.upgrade mix task from brando src.
* Switch all your image fields to `:jsonb` types in migrations from `:text`.


## 0.39.0

* Clean up time! Lots of deprecations and changes. See UPGRADE.md


## 0.38.0

* Update for Ecto 3, Phoenix 1.4
* More configuration choices in backend/config
* Add opts to body_tag
* Add config genserver
* More flexible cookie_law
* Add rerendering of page fragments
* Larger default image sizes
* Rewritten backend JS
* Rewritten generators
* Rewritten image handling


## 0.37.0

- Guardian was updated. Router changes. See UPGRADE.md
- `render_fragment` has been renamed to `fetch_fragment`.
- `brando_pages` has been incorporated into `brando` core.

## pre 0.37.0
