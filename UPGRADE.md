NOTE: Upgrade notes are in the CHANGELOG now.

## 0.52.0

* Pull in new `mix.exs` and rename to your application's names
  https://github.com/brandocms/brando/blob/master/priv/templates/brando.install/mix.exs

* `mix deps.get` -- you might need to unlock some deps, i.e: `mix deps.unlock phoenix_ecto`

* Switch your backend gettext module in `gettext.ex` from
  `YourApp.Backend.Gettext` to `YourAppAdmin.Gettext`

* Say bye to your Vue backend. Pull in the new backend with
  `$ mv assets/backend assets/backend_old`
  `$ mix brando.gen.backend`

* Replace `use Brando.I18n.Helpers` with `import Brando.I18n.Helpers`

* Delete guardian:
  `$ rm -rf lib/my_app_web/guardian`
  `$ rm -rf lib/my_app_web/guardian.ex`

* Delete graphql
  `$ rm -rf lib/my_app/graphql`

* Pull down a new router from:
  https://github.com/brandocms/brando/blob/main/priv/templates/brando.install/lib/application_name_web/router.ex

* Pull down a new `application_web.ex` from:
  https://github.com/brandocms/brando/blob/main/priv/templates/brando.install/lib/application_name_web.ex

* Pull down a new `endpoint.ex` from:
  https://github.com/brandocms/brando/blob/main/priv/templates/brando.install/lib/application_name_web/endpoint.ex

* Delete the admin channel (or the whole dir, if you don't have anything of your own there):
  `$ rm -rf lib/my_app_web/channels`

* Delete your old session controller:
  `$ rm lib/my_app_web/controllers/session_controller.ex`

* Generate a new auth file:
  `$ mix brando.gen.authorization`

* Set your admin module in `config/brando.exs`:
  `config :brando, admin_module: MyAppAdmin`

* Move all your old schemas and context out of the project

* Generate blueprints:
  `mix brando.gen.blueprint`

* Migrate to blueprints from your old schemas (ugh)

* Grab new migrations
  `$ mix brando.upgrade`

* Create your admin menu template in `lib/my_app_admin/menus.ex`:
```
defmodule MyAppAdmin.Menus do
  use BrandoAdmin.Menu
  import MyAppAdmin.Gettext

  menus do
    menu_item t("Articles") do
      menu_subitem MyApp.Articles.Article
      menu_subitem MyApp.Articles.Category
    end
  end
end
```

* Add `layout: false` to your `error_view` config in `config.exs`:
`render_errors: [view: MyAppWeb.ErrorView, accepts: ~w(html json), layout: false]`

* If you cannot add entries to your legacy Villain blocks, try
  saving the main entry first. It might just be missing UIDs on
  the blocks.

* Change image configs `target_format: :png` to `formats: [:png]`. If you have `webp: true`,
  you should also add `webp` to your formats list.

* Switch your frontend `app.html.eex` to `app.html.heex`. Change your `<%= body_tag %>` call to
  a heex component call: `<.body_tag conn={@conn} id="top"> ... <./body_tag>`


## 0.51.0

* If you use legacy schemas/changeset and use `generate_html` with a custom villain name,
  you must call it by its data name. So for instance, if you have `generate_html(:biography)`,
  switch to `generate_html(:biography_data)`

* Vite: Respect `hmr` config setting. Set it to `true` in your `dev.exs`, and `false` in `prod.exs`

* Move your contexts to the application root:
  `lib/my_app/accounts/accounts.ex` -> `lib/my_app/accounts.ex`

* Rename all `Brando.GraphQL` -> `BrandoGraphQL`

* OTP24 needs a newer `jose` version:

  `$ mix deps.update jose`

* `list_page_fragments` -> `list_fragments`

* Changed `Brando.Plug.Navigation` to require a keyword list as arg:

  ```
  # before
  plug Brando.Plug.Navigation, "main"

  # after
  plug Brando.Plug.Navigation, key: "main", as: :navigation
  ```

* Improved E2E testing. Commit your code, then run:

  `mix brando.gen.e2e`

  First and foremost, edit your `config/runtime.exs` and make sure that
  the DB config won't run under our `:e2e` environment:

  ```
  unless config_env() == :e2e do
    config :your_app, YourApp.Repo,
      url: System.get_env("BRANDO_DB_URL"),
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "15")
  end
  ```

  This is to prevent us from blowing out our database when we reset the
  test db later on.

  If you have edited your `priv/repo/seeds.exs`, they will be overwritten,
  so go through the diff and keep the `Page` and `PageFragment` changes.

  Install cypress:

  `cd e2e && yarn install`

  Update your `aliases` key in `mix.exs`:

  ```
  defp aliases do
    [
      "ecto.setup": [
        "ecto.create",
        "ecto.load",
        "ecto.migrate",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup", "run priv/repo/seeds.exs"],
      "test.all": ["test.unit", "test.e2e"],
      "test.unit": &run_unit_tests/1,
      "test.e2e": &run_e2e_tests/1,
      test: ["ecto.create", "ecto.load --skip-if-loaded", "test"]
    ]
  end
  ```

  Dump your sql structure:

  `mix ecto.dump`

  Reset your test DB (NOTE: make sure you have done the `runtime.exs` changes above):

  `MIX_ENV=e2e mix ecto.reset`

  Ensure your `factory.ex` uses `ExMachina.Ecto`:

  `use ExMachina.Ecto, repo: MyApp.Repo`

  Then run tests:

  `mix test.e2e`

* In order to pass related data to the live preview when *creating* a new entry,
  you must now process `KMultiSelects` in your `<Schema>CreateView`'s `save`
  function in the same way as in `<Schema>EditView`:

  `this.$utils.mapMultiSelects(postParams, ['fieldName'])`

* `video_tag/2` must receive a keyword list as `opts`, not `map`.

* Proper pagination in BrandoJS means some changes! If your application `use`s
  `Brando.GraphQL.Resolver`, the `all` resolver will now return
  `%{entries: entries, pagination_meta: pagination_meta}`.

  With `page` as an example:

  In your `graphql/types/page.ex`, add a new `:object`:

  ```
  object :pages do
    field :entries, list_of(:page)
    field :pagination_meta, non_null(:pagination_meta)
  end
  ```

  Reference this object instead of `list_of(:page)` in your `:pages` query:

  ```
  object :page_queries do
    @desc "Get all pages"
    field :pages, type: :pages do
      arg :order, :order, default_value: [{:asc, :language}, {:asc, :sequence}, {:asc, :uri}]
      arg :limit, :integer, default_value: 25
      arg :offset, :integer, default_value: 0
      arg :filter, :page_filter
      arg :status, :string, default_value: "all"
      resolve &Brando.Pages.PageResolver.all/2
    end
  end
  ```

  Rewrite your query to wrap pages in `entries`:

  ```
  query Pages ($order: Order, $limit: Int, $offset: Int, $filter: PageFilter, $status: String) {
    pages (order: $order, limit: $limit, offset: $offset, filter: $filter, status: $status) {
      entries {
        ...page
      }

      paginationMeta {
        totalEntries
        totalPages
        currentPage
        nextPage
        previousPage
      }
    }
  }
  ```

  In your `PageListView.vue`, you can remove `@more` on the ContentList, and
  the `showMore` method.


* Renamed `Brando.Schema` to `Brando.GraphQL.Schema`.
  Switch out in your app's `graphql/schema.ex`.

* Schemas need `use Brando.Schema` now. This is to help generate identifiers for entries.
  You need to implement `identifier/1` and `absolute_url/1`.

  `identifier/1` tells Brando which field in your schema best describes your entry.

  ```
  use Brando.Schema

  meta :en, singular: "page", plural: "pages"
  meta :no, singular: "side", plural: "sider"

  identifier fn entry -> entry.title end

  absolute_url fn router, endpoint, entry ->
    router.page_path(endpoint, :detail, entry.slug)
  end
  ```

* Revisions:

  Switch out your resolvers with:

  ```
  use Brando.GraphQL.Resolver,
    context: MyApp.MyContext,
    schema: MyApp.MyContext.MySchema
  ```

  OR

  add a check in your resolver's `update` function:

  ```
  def update(%{post_id: post_id, post_params: post_params, revision: revision}, %{
      context: %{current_user: current_user}
    }) do
    if revision do
      Brando.Revisions.create_from_base_revision(
        Post,
        revision,
        post_id,
        post_params,
        current_user
      )
    else
      Post.update_post(post_id, post_params, current_user))
    end
  end
  ```

  In your `SchemaEditView.vue`, you need to add a `$revision` param to your `save` function:
  ```
  async save (setLoader, revision = 0) {
    // ...
    await this.$apollo.mutate({
      mutation: gql`
        mutation UpdatePage($pageId: ID!, $pageParams: PageParams, $revision: ID) {
          updatePage(
            pageId: $pageId,
            pageParams: $pageParams,
            revision: $revision
          ) {
            id
          }
        }
      `,
      variables: {
        pageParams,
        pageId: this.page.id,
        revision
      }
    })

    // only push new route if not force saving a revision
    if (revision === 0) { this.$router.push({ name: 'pages' }) }
    // ...
  ```

  You must also add the `revision` arg to the GraphQL mutation:

  ```
  field :update_page, type: :page do
    arg :page_id, non_null(:id)
    arg :page_params, :page_params
    # add this:
    arg :revision, :id

    resolve &Brando.Pages.PageResolver.update/2
  end
  ```

* If you use custom GraphQL resolvers, make sure you pass your `current_user` to the
  `delete_<singular>` function.

* Status: `published_all` has been removed -- you can replace with `published_and_pending`
  or `published`

* To automatically add the dominant color of an image to its struct, you
  can install `dominant-color` on your server/dev machine:

    `$ npm i -g @univers-agency/dominant-color`

* Call single GraphQL resolvers with args. Using `Project` as an example:
  In your GraphQL schemas, you need to add these new args to your single query:

    ```
    @desc "Matching options for project"
    input_object :project_matches do
      field :id, :id
    end

    @desc "Get project"
    field :project, type: :project do
      arg :matches, :project_matches
      arg :revision, :id
      arg :status, :string, default_value: "all"
      resolve &MyApp.Projects.ProjectResolver.get/2
    end
    ```

  Then fix your `PROJECT_QUERY.graphql`:

    ```
    #import "./PROJECT_FRAGMENT.graphql"
    query Project ($matches: ProjectMatches, $status: String, $revision: ID) {
      project (matches: $matches, status: $status, revision: $revision) {
        ...project
      }
    }
    ```

  Finally your `ProjectEditView.vue` needs an update:

    ```
    apollo: {
      project: {
        query: GET_PROJECT,
        fetchPolicy: 'no-cache',
        variables () {
          return {
            matches: { id: this.areaId }
          }
        },

        skip () {
          return !this.projectId
        }
      },
      // ...
    }
    ```

    If you use **revisions** and have a M2M field or any field that is
    preloaded in your `mutation :update`, you must pass `use_parent: true`
    to the dataloader for that field:

    ```
    field :related_projects, list_of(:project),
      resolve: dataloader(MyApp.Projects, use_parent: true)
    ```

    Otherwise, dataloader will try to load a fresh relation from
    the original entry, not the revision you might be trying to access.


## 0.50.0

* To improve your security headers, add to your `router.ex`'s `:browser` pipeline:

    ```
    plug :put_extra_secure_browser_headers
    ```

    You can override its settings by passing a map of headers to merge in.

* Renamed `Page.key` to `Page.uri`. Change your code under `PageController.show` from

    `|> put_section(page.key)` to `|> put_section(page.uri)`

* `avoid_slug_collision/2` is now `avoid_field_collision/3`. It can now check multiple fields with a
  required second argument

    `avoid_field_collision(changeset, [:slug, :key])`

* Fragment querying has been streamlined. Instead of `Pages.get_fragments(parent_key)` etc, use a map
  of query args:

    `Pages.get_fragments(%{filter: %{parent_key: "parent_key"}, cache: {:ttl, :infinite}})`

* To upgrade to a Vite frontend, start by backing up your old frontend:

    `$ mv assets/frontend assets/frontend_old`

  Then copy in the new frontend files:

    `$ mix brando.gen.frontend`

  Finally, copy your changed files from `frontend_old` into `frontend`. You must rename `.pcss` files to `.css`, and
  correct all imports. You will not need your old `polyfill*.js` files.

* Copy in the new `ReleaseTasks` template to `lib/my_app/release_tasks.ex`: (switch out `MyApp` and `:my_app`!)

```
defmodule MyApp.ReleaseTasks do
  @app :my_app

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

* Rename all `Brando.Villain.Template` occurences to `Brando.Villain.Module`.

* Some props for Villain have changed:

    ```
    gsed -i "s=templateMode=moduleMode=" assets/backend/src/**/*.vue && \
    gsed -i "s=templateNamespace=moduleNamespace=" assets/backend/src/**/*.vue && \
    gsed -i "s=namespacedTemplates=namespacedModules=" assets/backend/src/**/*.vue && \
    gsed -i "s=:template-mode=:module-mode=" assets/backend/src/**/*.vue && \
    gsed -i "s=:template-mode=:module-mode=" assets/backend/src/config.js && \
    gsed -i "s=:templateMode=:moduleMode=" assets/backend/src/config.js && \
    gsed -i "s=:templates=:modules=" assets/backend/src/**/*.vue && \
    gsed -i "s=templates\=\"=modules\=\"=" assets/backend/src/**/*.vue && \
    gsed -i "s=:templates=:modules=" assets/backend/src/config.js && \
    gsed -i "s=templates\=\"=modules\=\"=" assets/backend/src/config.js
    ```

* Villain keeps its data as an object in the Vue backend, so all graphql schemas using it
  must call `this.$utils.serializeParams(postParams, ['data'])` where `data` is the name
  of your Villain field. This is called in your `MySchemaCreateView.vue` and `MySchemaEditView.vue`
  in their `save` methods.

  If you have MultiSelects -- they must be mapped out (in EDIT views):

      `this.$utils.mapMultiSelects(postParams, ['fieldName'])`

  If you have input tables that are sending objects -- the type names must be stripped (in EDIT views):

      `this.$utils.stripTypenames(postParams, ['fieldName'])`

* Added `admin_routes/0` macro to `Brando.Router`. Import `Brando.Router` in your `router.ex`,
then remove your entire `scope "/admin"` block and replace it with the `admin_routes()` macro.

* Added `page_routes/0` macro to `Brando.Router`. Import `Brando.Router` in your `router.ex`,
then remove your page routes and replace it with the `page_routes()` macro.

* Added mutations to `Brando.Query`. Add to your context: (if you want to use these)

```
mutation :create, MySchema
mutation :update, MySchema
mutation :delete, MySchema
```

then you can throw out your `create_<schema>` / `update_<schema>` / `delete_<schema>` functions.

* Villain: Removed markdown parsing from `Text` blocks. You can override this in your own `parser.ex`:

```
def text(%{"text" => text} = params, _) do
  text =
    case Map.get(params, "type") do
      nil -> text
      "paragraph" -> text
      type -> "<div class=\"#{type}\">#{text}</div>"
    end

  Earmark.as_html!(text, %Earmark.Options{breaks: true})
end
```


## 0.49.0

* Copy new rollup config with some `rollup-copy-plugin` fixes:

    `$ cp deps/brando/priv/templates/brando.install/assets/frontend/rollup.config.js assets/frontend/rollup.config.js`

* Set `sharp` and `sharp-cli` as standard image processing lib:

    `config :brando, Brando.Images, :processor_module, Brando.Images.Processor.Sharp`

  Unless you are running an ancient Brando version, this would already be your default.

* If using `fabfile.py`, be sure to update this to include the new `grant_db` function. You need this to prevent
  migration errors when running Oban migrations.

    `$ cp deps/brando/priv/templates/brando.install/fabfile.py .`

* If you have no custom logic in your `authorization.ex` you can rerun

    `$ mix brando.gen.authorization`

  to get new rules for new configuration menus.

* When `use`ing I18n helpers, you now do not need a `helpers` arg. Renamed
`localized` to `localized_path`.

* Added telemetry for Villain `parse_and_render`. Add to your `telemetry.ex`:

    `summary("brando.villain.parse_and_render.duration", unit: {:native, :millisecond}),`

* Changed `opts` parameter in Villain parser blocks from `Keyword` to `map`. If you have overridden any of the
  parser functions that uses `opts`, adjust accordingly: `Keyword.get(opts, :context)` -> `Map.get(opts, :context)`

* Live Preview: Changed syntax:

    ```
    preview_target Brando.Pages.Page do
      layout_module MyAppWeb.LayoutView
      view_module MyAppWeb.PageView
      view_template fn e -> e.template end
      template_section fn e -> e.key end
      template_prop :entry

      assign :navigation, fn _entry -> Brando.Navigation.get_menu("main", "en") |> elem(1) end
      assign :partials, fn _entry -> Brando.Pages.get_fragments("partials") |> elem(1) end
    end
    ```

  Also note that `assign/2` now requires the passed anonymous function to have `/1` arity. This
  means you change

      `assign :navigation, fn -> Brando.Navigation.get_menu("main", "en") |> elem(1) end`

  to

      `assign :navigation, fn _entry -> Brando.Navigation.get_menu("main", "en") |> elem(1) end`

* Dynamic redirects. Switch out your fallback controller in `page_controller.ex`:

    `action_fallback Brando.FallbackController`

  so when a page is not found, look through the redirects and redirect if neccessary.

* Remove `robots.txt` from Plug.Static in your endpoint. It is now handled through the `robots` field in `sites_seo`
  which you can configure from `Configure -> SEO`


## 0.48.0

* Move to liquex parsing. This means a bunch of updates:

  - All `${variables:key}` are changed to `{{ variables.key }}`
  - `${content}` -> `{{ content }}`
  - `{% for entry <- entries %}` -> `{% for entry in entries %}`
  - `${global:category_key.global_key}` -> `{{ globals.category_key.global_key }}`
  - `${link:instagram}` -> `{{ links.instagram.url }}`
  - `${config:key}` -> `{{ configs.key }}`
  - `${menu:main.en}` -> `{{ navigation.main.en }}`
  - `${fragment:parent_key/key/language}` -> `{% fragment parent_key key language %}`

  Brando checks this on startup, but it is a very simple check (doesn't understand
  the new globals syntax etc). You can invoke this check from iex when developing:

      `iex> Brando.System.check_entry_syntax()`
      `iex> Brando.System.check_template_syntax()`

* Brando.Datasource - rename `many` to `list`


## 0.47.0

* Moved Villain `DatasourceBlock` code from template to it's own code prop.
  This means you must copy the code from the template the Datasource is using into the datasource's config.
  The datasource code has an `${entries}` variable that you can iterate on instead of using a wrapper.

* Start Brando from your application
  In `application.ex`, add `Brando` to your supervision tree as the last child:

  ```
      children = [
        # Start the Ecto repository
        MyApp.Repo,
        # Start the Telemetry supervisor
        MyAppWeb.Telemetry,
        # Start the PubSub system
        {Phoenix.PubSub, name: MyApp.PubSub},
        # Start the Endpoint (http/https)
        MyAppWeb.Endpoint,
        # Start the Presence system
        MyApp.Presence,
        # Start Brando
        Brando
      ]
  ```

* Removed and unified most of the `Brando.Pages.get_page/*` functions. Now uses `matches`

      `Brando.Pages.get_page(%{matches: %{key: "index", status: :published}})`


## 0.46.0

* CDN uploads
  Add your CDN config to `config/dev.exs` and `config/prod.exs`. It is recommended
  to use separate buckets for development and production to prevent accidental
  overwrite.

  ```
  config :brando, Brando.CDN,
    enabled: true,
    bucket: "my_app_prod",
    media_url: "https://myspace.ams3.digitaloceanspaces.com/my_app_prod"
  ```

* Add `timezone` to `config/brando.exs`. This is used by date template filters.
  ```
  config :brando,
    timezone: "Europe/Oslo"
  ```

* Added an `imageType` fragment to GQL. Use this instead of your own picked field, so replace
  ```
  post {
    cover {
      focal
      thumb: url(thumb)
      # ..etc
    }
  }
  ```
  to
  ```
  #import "brandojs/src/gql/images/IMAGE_TYPE_FRAGMENT.graphql"
  post {
    cover {
      ...imageType
    }
  }
  ```
  This means you should fix KInputImage fields that use any of your custom sizes. You can set which
  key to use as preview by passing the `preview-key` prop to KInputImage.

  This change is neccessary to bring in more default fields for the image so that live preview
  has the neccessary information.

* Renamed `User.full_name` to `User.name`. Requires BrandoJS to be updated.
  Check through your JS code for `fullName` and replace with `name

* Deprecated `Pages.list_page_fragments_translations`. Use `Pages.list_fragments_translations` instead.
  You now must explicitly pass language to exclude as `exclude_language: "en"`, otherwise all languages
  are returned!

* Switch frontend bundler to Rollup. Commit your code, then:

  ```
  mv assets/frontend/fonts assets/frontend/static
  cp deps/brando/priv/templates/brando.install/assets/frontend/rollup.config.js assets/frontend
  cp deps/brando/priv/templates/brando.install/assets/frontend/package.json assets/frontend
  ```
  Then look through the `package.json` diff and add back your own configurations.
  ```
  cd assets/frontend && yarn add --dev rollup rollup-plugin-copy @rollup/plugin-commonjs \
     @rollup/plugin-replace rollup-plugin-delete rollup-plugin-postcss rollup-plugin-terser \
     @rollup/plugin-babel @rollup/plugin-node-resolve
  ```
  - Remove all webpack packages from `assets/frontend/package.json`
  - `rm assets/frontend/webpack.*`
  - You must `import './index'` at the end of the polyfill files `polyfill.legacy.js`
    and `polyfill.modern.js`
  - Add `~r"priv/static/css/.*(css)$",` to live_preload patterns in `config/dev.exs` to ensure
    automatic loading of compiled CSS.


## 0.45.0

* Switch your `mix.exs` `:brando` github dep to `brandocms/brando`

* Upgrade BrandoJS to latest. Needed for rewritten upload handling and new
  language defaults.

* Switch to consistent casing in GQL files. This means that you have to go through
  your js graphql fragments and switch to camelCase (inserted_at -> insertedAt). Form
  views, List views and locale files must be updated as well.

  A lazy way to do it is to first commit your code, then
  ```
  gsed -i -r 's/([a-z])_([a-z])/\1\U\2/g' assets/backend/src/**/*.*
  ```
  And then search through your backend js and fix all `adminChannel.channel.push` calls,
  since the above code will break topic strings.

* BrandoJS Datasource: Moved `wrapper` to template instead.

* `${CONTENT}` should be refered to as `${content}` in your template `wrapper`

* Switch out all "nb" language keys to "no". Both in elixir configs and in
  Vue files (menus/locales)

* In your `app.html.eex`, replace
  `<%= render @view_module, @view_template, @assigns %>`
  with
  `<%= @inner_content %>`

* If you implement your own `parser.ex`, all functions must be changed to /2.
  `def text(data) do` -> `def text(data, _) do`

* In `config/brando.exs` add:
  ```
  config :brando,
    app_module: MyApp,
    web_module: MyAppWeb,
  ```
  You can remove `endpoint`, `factory`, `repo`, `router` and `helpers` keys.

* Switch out
  `plug :put_layout, {YourAppWeb.LayoutView, "admin.html"}` with
  `plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}` in your app's router

* Authorization. First run `mix brando.gen.authorization` to create a generic
  authorization module in your application

  Then in your `router.ex`, remove the `scope "/auth"` block
  and add a `forward` instead:

        forward "/auth", Brando.Plug.Authentication,
          guardian_module: MyAppWeb.Guardian,
          authorization_module: MyApp.Authorization

* Phoenix has replaced `Plug.Logger` with `Plug.Telemetry` etc in default
  generated `endpoint.ex`. Replace `plug Plug.Logger` with
  `plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]`

* KInputTable: Rename `newRows` -> `addRows`

* Copy `DashboardView.vue` from Brando Install >


## 0.44.0

### Vue backend rewrite part 1/? (sorry)

* Switch out in your `assets/backend/package.json`
  - remove `@univers-agency/kurtz`
  - add `"brandojs": "file:../../deps/brando/assets/brandojs",`
    - (if developing on brandojs, yalc it.)
* Switch out `kurtz` with `brandojs`:
  ```
  gsed -i "s=@univers-agency\/kurtz=brandojs=" assets/backend/src/**/*.js && \
  gsed -i "s=@univers-agency\/kurtz=brandojs=" assets/backend/src/**/*.vue && \
  gsed -i "s=~@univers-agency\/kurtz=~brandojs=" assets/backend/src/**/*.scss
  ```
* Part 1 of the big backend Vue rewrite has been updating it to use the new Vee-Validate syntax.
  All `<KInput(...)>` components with validation now needs to be wrapped in a `<ValidationObserver>` HOC:

  ```html
  <ValidationObserver
    ref="observer">
    <!-- fields here -->
  </ValidationObserver>
  ```

  All `<KInput(...)>` components needs to:

  - Add:
    - A `rules` prop i.e -> `rules="required"`
  - Remove:
    - `v-validate`
    - `:has-error`
    - `:error-text`

  Switch out the `validate` function with:

  ```es6
  async validate () {
    const isValid = await this.$refs.observer.validate()
    if (!isValid) {
      alertError('Feil i skjema', 'Vennligst se over og rett feil i rødt')
      this.loading = 0
      return
    }
    this.save()
  },
  ```

* Change `assets/backend/src/main.js` by removing the `Vue` import from `kurtz` then change
  ```es6
  // Install Kurtz
  let Vue = installKurtz()
  ```

### A working staging setup!

* Add staging conf for logrotate
  ```
    cp etc/logrotate/prod.conf etc/logrotate/staging.conf && \
      gsed -i "s/prod/staging/g" etc/logrotate/staging.conf
  ```
* Ensure you have config/staging.conf & config/staging.secret.conf, and that the `endpoint` config
  looks OK (http/url/etc)
  ```
  config :my_app, <<<<<<MyAppWeb>>>>>>.Endpoint,
    http: [:inet6, port: {:system, "PORT"}],
    url: [scheme: "http", host: "my_app.staging.yourhost.name", port: 80],
    # force_ssl: [rewrite_on: [:x_forwarded_proto]],
    check_origin: ["//*.yourhost.name", "//localhost:4000"],
    server: true,
    cache_static_manifest: "priv/static/cache_manifest.json"
  ```
* Ensure you have rel/vm.args.prod & rel/vm.args.staging
  ```
    cp rel/vm.args rel/vm.args.prod && cp rel/vm.args rel/vm.args.staging && \
      gsed -i "s/<%= release_name %>@127.0.0.1/<%= release_name %>_staging@127.0.0.1/" rel/vm.args.staging && \
      rm rel/vm.args
  ```
* Ensure you have Dockerfile.prod & Dockerfile.staging
  ```
    cp Dockerfile Dockerfile.prod && cp Dockerfile Dockerfile.staging && \
      gsed -i "s=prod=staging=" Dockerfile.staging && \
      rm Dockerfile
  ```
* Ensure you have fabfile.py version 3.0.0
  --> copy from https://github.com/univers-agency/brando/blob/develop/priv/templates/brando.install/fabfile.py
* Ensure `rel/config.exs` has:
    ```
    environment :staging do
      set include_erts: true
      set include_src: false
      set cookie: :"<secret>"
      set vm_args: "rel/vm.args.staging"
    end

    environment :prod do
      set include_erts: true
      set include_src: false
      set cookie: :"<secret>"
      set vm_args: "rel/vm.args.prod"
    end
    ```

* Add dataloaders to your contexts:
  ```elixir
  @doc """
  Dataloader initializer
  """
  def data(_) do
    Dataloader.Ecto.new(
      Repo,
      query: &query/2
    )
  end

  @doc """
  Dataloader queries
  """
  def query(queryable, _), do: queryable
  ```

* Add to your `lib/my_app/graphql/schema.ex`
  ```elixir
  def context(ctx) do
    # ++dataloaders
    loader =
      Dataloader.new()
      |> import_brando_dataloaders(ctx)
      |> Dataloader.add_source(Exhibitions, Exhibitions.data())
      |> Dataloader.add_source(Artists, Artists.data())
    # __dataloaders

    Map.put(ctx, :loader, loader)
  end

  def plugins do
    [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
  end
  ```
* Remove `Absinthe.Ecto` stuff from `my_app_web.ex`
* Add `import Absinthe.Resolution.Helpers` to `:absinthe` in `my_app_web.ex`
* Remove `absinthe_ecto` from your deps in `mix.exs`
* Add `{:dataloader, "~> 1.0"}` instead

* `gsed -i "s=use Brando.Field.ImageField=use Brando.Field.Image.Schema=" */**/*.ex`
* `gsed -i "s=use Brando.Field.FileField=use Brando.Field.File.Schema=" */**/*.ex`

* Add `config :brando, :media_path, Path.join([Mix.Project.app_path(), "tmp", "media"])` to
  `config/e2e.exs`

* Add
  ```
  # ++aliases
  # __aliases

  # ++functions
  # __functions
  ```
  to `lib/my_app/factory.ex`


## 0.43.0

### General

* Run `mix brando.upgrade && mix ecto.migrate`
* Add `Brando.HTML.init_js()` at the top of your `app.html.eex`, before `render_meta`


## 0.42.0 and older

- See 0.43 tag on github.

