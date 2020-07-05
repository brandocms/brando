## 0.46.0

* Switch frontend bundler to Rollup. Commit your code, then:

  ```
  mv assets/frontend/fonts assets/frontend/static`
  cp deps/brando/priv/templates/brando.install/assets/frontend/rollup.config.js assets/frontend`
  cp deps/brando/priv/templates/brando.install/assets/frontend/package.json assets/frontend`
  ```
  Then look through the `package.json` diff and add back your own configurations.
  ```
  cd assets/frontend && yarn install --dev rollup rollup-plugin-copy @rollup/plugin-commonjs \
     @rollup/plugin-replace rollup-plugin-delete rollup-plugin-postcss rollup-plugin-terser \
     @rollup/plugin-babel @rollup/plugin-node-resolve
  ```
  - Remove all webpack packages from `assets/frontend/package.json`
  - `rm assets/frontend/webpack.*`
  - Add `~r"priv/static/css/.*(css)$",` to live_preload patterns in `config/dev.exs` to ensure
    automatic loading of compiled CSS.


## 0.45.0

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

* Upgrade BrandoJS to latest. Needed for rewritten upload handling and new
  language defaults.

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
  gsed -i "s=~@univers-agency\/kurtz=~brandojs=" assets/backend/src/**/*.scss &&
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

