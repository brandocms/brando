## 0.50.0

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
    gsed -i "s=:template-mode=:module-mode=" assets/backend/src/**/*.vue && \
    gsed -i "s=:template-mode=:module-mode=" assets/backend/src/config.js && \
    gsed -i "s=:templates=:modules=" assets/backend/src/**/*.vue && \
    gsed -i "s=:templates=:modules=" assets/backend/src/config.js
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

* In your `router.ex`, add

    `get "/robots.txt", Brando.SEOController, :robots`

  under your "/" scope.


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

