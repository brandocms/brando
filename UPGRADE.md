## 0.44.0

* Part 1 of the big backend Vue rewrite has been updating it to use the new Vee-Validate syntax.
  All `<KInput(...)>` components with validation now needs to be wrapped in a `<ValidationObserver>` HOC:

  ```html
  <ValidationObserver
    ref="observer"
    v-slot="{ invalid }">
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
      this.loading = false
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


## 0.42.0

### General

* Moved js deps to `@univers-agency` package scope.
  - replace `kurtz` with `@univers-agency/kurtz` in `assets/backend/package.json`
  - yarn install
  - ```
     gsed -i "s=from 'kurtz=from '@univers-agency\/kurtz=" assets/backend/src/**/*.js && \
     gsed -i "s=from 'kurtz=from '@univers-agency\/kurtz=" assets/backend/src/**/*.vue && \
     gsed -i "s=~kurtz=~@univers-agency\/kurtz=" assets/backend/src/**/*.scss && \
     gsed -i "s=~villain-editor=~@univers-agency\/villain-editor=" assets/backend/src/**/*.scss
  ```

* `Brando.User` is now `Brando.Users.User` for consistency.
* In `session_controller.ex`, ensure user has not been soft deleted in `create/3`

  ```elixir
  def create(conn, %{"email" => email, "password" => password}) do
    case Users.get_user_by_email(email) do
      {:error, {:user, :not_found}} ->
        Bcrypt.no_user_verify()

        conn
        |> put_status(:unauthorized)
        |> render("error.json")

      {:ok, user} ->
        if Bcrypt.verify_pass(password, user.password) do
          {:ok, jwt, _full_claims} = <%= application_module %>Web.Guardian.encode_and_sign(user)

          conn
          |> put_status(:created)
          |> render("show.json", jwt: jwt, user: user)
        else
          conn
          |> put_status(:unauthorized)
          |> render("error.json")
        end
    end
  end
  ```

### Soft deletion

* Soft deletion fields have been added. Run `mix brando.upgrade`
* Add to your `repo.ex`:

    use Brando.SoftDelete.Repo

### Application layout template

* Switch out the `:hmr` logic for `css` and `js` with

    <%= Brando.HTML.include_css() %>
    <%= Brando.HTML.include_js() %>

  right before `</head>`

### Startup checks

* Add to your `application.ex`
    result = Supervisor.start_link(children, opts)
    # Run Brando system checks
    Brando.System.initialize()

    result

### Meta rewrite

* Remove `import Brando.Meta.Controller` from `my_app_web.ex`.
  Both from `controller/0` and `router/0`.
* Remove any `put_meta` in `router.ex´
* Add

    use Brando.JSONLD.Schema
    use Brando.Meta.Schema

  to `my_app_web.ex` under `schema/0`.

### Image processing

* Added SHARP image processing. Choose this for the fastest/highest quality
    ```elixir
    config :brando, Brando.Images,
      processor_module: Brando.Images.Processor.Sharp # or Mogrify
    ```
* Remove all `import Brando.Images.Optimize` and `optimize/2` in changeset functions.
  If you need optimizing, use SHARP.


## 0.41.0

* Tables have been renamed. Run `mix brando.upgrade`
* Fragments now belong to pages. Run `mix brando.upgrade`


## 0.40.0

* Copy the brando.upgrade mix task from brando src.
* Switch all your image fields to `:jsonb` types in migrations from `:text`. Run `mix brando.upgrade`


## 0.39.0

* Backwards incompatible changes
  - add to `config/dev.exs`
  ```
  config :my_app, hmr: true
  ```
  - add to your `parser.ex`
  ```
  @doc """
  Convert template to html.
  """
  def template(%{"id" => id, "refs" => refs}) do
    {:ok, template} = Brando.Villain.get_template(id)

    Regex.replace(~r/%{(\w+)}/, template.code, fn _, match ->
      ref = Enum.find(refs, &(&1["name"] == match))

      if ref do
        block = Map.get(ref, "data")
        apply(__MODULE__, String.to_atom(block["type"]), [block["data"]])
      else
        "<!-- REF #{match} missing // template: #{id}. -->"
      end
    end)
  end
  ```
  - Replace all `backend/*.`
    ```
    $ gsed -i "s/import Vuex from 'vuex'/import { Vuex } from 'kurtz'/" assets/backend/src/**/*.js && \
      gsed -i "s/import Router from 'vue-router'/import { Router } from 'kurtz'/" assets/backend/src/**/*.js && \
      gsed -i "s/import Vue from 'vue'/import { Vue } from 'kurtz'/" assets/backend/src/**/*.js && \
      gsed -i "s/import Vue from 'vue'/import { Vue } from 'kurtz'/" assets/backend/src/**/*.vue && \
      gsed -i "s|from 'vuex'|from 'kurtz/lib/vuex'|" assets/backend/src/**/*.js && \
      gsed -i "s|from 'vuex'|from 'kurtz/lib/vuex'|" assets/backend/src/**/*.vue && \
      gsed -i "s|from 'vue'|from 'kurtz/lib/vue'|" assets/backend/src/**/*.js && \
      gsed -i "s|from 'vue'|from 'kurtz/lib/vue'|" assets/backend/src/**/*.vue && \
      gsed -i "s|import nprogress from 'nprogress'|import { nprogress } from 'kurtz'|" assets/backend/src/**/*.vue
    ```

  - Add to your graphql `schema.ex`
    ```elixir
    def middleware(middleware, _field, %{identifier: :mutation}),
      do: middleware ++ [Brando.Schema.Middleware.ChangesetErrors]

    def middleware(middleware, _field, _object), do: middleware
    ```
  - All Villain fields in graphql `input_object` must be type `:json` instead of `:string`
  - Change to new use Villain format:
    `$ gsed -i "s/use Brando.Villain, :schema/use Brando.Villain.Schema/" lib/**/*.ex`
    `$ gsed -i "s/use Brando.Villain, :migration/use Brando.Villain.Migration/" priv/**/*.exs`
  - Moved `rerender_html` from being a schema macro to `Brando.Villain.rerender_html`
  - Updated `<Villain>` JS inputs for validation:
  ```vue
  <Villain
    v-validate="'required'"
    v-model="location.data"
    :value="location.data"
    :has-error="errors.has('location[data]')"
    :error-text="errors.first('location[data]')"
    name="location[data]"
    label="Innhold"/>
  ```
  - All Apollo calls with 'network-only' must be 'no-cache'
  - Switch out the `backend/package.json` and `yarn.lock` with fresh ones from source.
  - `yarn upgrade kurtz`
  - Replace `Dockerfile`, `.dockerignore`, `fabfile.py` from source.
  - Remove `YourApp.PostgresTypes` — this is not needed.
  - Add insertion points to important files. These markers will be used with `brando.gen.html`
    `__` denotes end of block, `++` denotes start. Start of block is not mandatory.
    - `admin_channel.ex`
      - `# __imports`
      - `# __macros`
      - `# __functions`
    - `graphql/schema/types.ex`
      - `# __types`
    - `graphql/schema.ex`
      - `# __queries`
      - `# __mutations`
    - `assets/backend/src/store/index.js`
      - `// __imports
      - `// __content
    - `assets/backend/src/routes/index.js`
      - `// __imports
      - `// __content
    - `assets/backend/src/menus/index.js`
      - `// __imports
      - `// __content

  - `Comeonin.Bcrypt.checkpw` -> `Bcrypt.verify_pass`
    `$ gsed -i 's/Comeonin.Bcrypt.checkpw/Bcrypt.verify_pass/' lib/**/*.ex`
  - `Comeonin.Bcrypt.hashpwsalt` -> `Bcrypt.hash_pwd_salt`
    `$ gsed -i 's/Comeonin.Bcrypt.hashpwsalt/Bcrypt.hash_pwd_salt/' lib/**/*.ex`
  - `Comeonin.Bcrypt.dummy_checkpw`-> `Bcrypt.no_user_verify`
    `$ gsed -i 's/Comeonin.Bcrypt.dummy_checkpw/Bcrypt.no_user_verify/' lib/**/*.ex`


## 0.38.0


## 0.37.0

* Backwards incompatible changes
  - Guardian was updated.
    The installer generates a Guardian interface, along with (...).

    First install guardian in your project's `mix.exs`:

    `{:guardian, "~> 1.0"}`

    You need a `session_controller.ex`

    ```elixir
    defmodule MyAppWeb.SessionController do
      @moduledoc """
      Generated session controller
      """
      use MyAppWeb, :controller
      alias Brando.User
      alias MyApp.Repo

      @doc """
      Create new token
      """
      def create(conn, %{"email" => email, "password" => password}) do
        case Repo.get_by(User, email: email) do
          nil ->
            Comeonin.Bcrypt.dummy_checkpw()

            conn
            |> put_status(:unauthorized)
            |> render("error.json")

          user ->
            require Logger
            if Comeonin.Bcrypt.checkpw(password, user.password) do
              {:ok, jwt, _full_claims} = MyAppWeb.Guardian.encode_and_sign(user)

              conn
              |> put_status(:created)
              |> render("show.json", jwt: jwt, user: user)
            else
              conn
              |> put_status(:unauthorized)
              |> render("error.json")
            end
        end
      end

      @doc """
      Delete token
      """
      def delete(conn, %{"jwt" => jwt}) do
        MyAppWeb.Guardian.revoke(jwt)

        render(conn, "delete.json")
      end

      @doc """
      Verify token
      """
      def verify(conn, %{"jwt" => jwt}) do
        case MyAppWeb.Guardian.decode_and_verify(jwt) do
          {:error, :token_expired} ->
            conn
            |> put_status(:unauthorized)
            |> render("expired.json")
          _ ->
            conn
            |> put_status(:ok)
            |> render("ok.json")
        end
      end
    end
    ```

    You also need a `session_view.ex`

    ```elixir
    defmodule MyAppWeb.SessionView do
      use MyAppWeb, :view

      def render("show.json", %{jwt: jwt, user: user}) do
        %{jwt: jwt, user: user}
      end

      def render("error.json", _) do
        %{error: "Feil ved innlogging"}
      end

      def render("delete.json", _) do
        %{ok: true}
      end

      def render("forbidden.json", %{error: error}) do
        %{error: error}
      end

      def render("expired.json", _) do
        %{error: "expired"}
      end

      def render("ok.json", _) do
        %{ok: true}
      end
    end
    ```

    also `lib/my_app_web/guardian.ex`

    ```elixir
    defmodule MyAppWeb.Guardian do
      use Guardian, otp_app: :my_app
      alias Brando.User

      def subject_for_token(user = %User{}, _claims) do
        {:ok, "User:#{user.id}"}
      end

      def subject_for_token(_, _) do
        {:error, "Unknown resource type"}
      end

      def resource_from_claims(%{"sub" => "User:" <> id} = _claims), do: {:ok, Brando.repo.get(User, id)}

      def resource_from_claims(_claims) do
        {:error, "Unknown resource type"}
      end
    end
    ```

    In your `lib/my_app_web/channels/admin_socket.ex`, change out the `connect/2` function

    ```elixir
    def connect(%{"guardian_token" => jwt}, socket) do
      case Guardian.Phoenix.Socket.authenticate(socket, MyAppWeb.Guardian, jwt) do
        {:ok, authed_socket} ->
          {:ok, authed_socket}

        {:error, err} ->
          :error
      end
    end
    ```

    In `config/brando.exs`, change the guardian config as so:

    ```elixir
    config :film_farms, MyAppWeb.Guardian,
      issuer: "MyApp",
      ttl: {30, :days},
      secret_key: "4bK7w0vuz8lAuhsckr0McyH0Efy2mfedySXfppI/4XjRWp274bUxBkNfgXMgH1lP"
    ```

    And finally, in your `router.ex`:

    ```diff
      pipeline :graphql do
        # plug RemoteIp
    -   plug Guardian.Plug.VerifyHeader, realm: "Bearer"
    -   plug Guardian.Plug.EnsureAuthenticated, handler: Brando.AuthHandler.GQLAuthHandler
    -   plug Guardian.Plug.LoadResource
    +   plug MyAppWeb.Guardian.GQLPipeline
        plug Brando.Plug.APIContext
        plug Brando.Plug.SentryUserContext
      end

    - pipeline :browser_session do
    -   plug Guardian.Plug.VerifySession
    -   plug Guardian.Plug.LoadResource
    - end
    -
    - pipeline :auth do
    -   plug :accepts, ["html"]
    -   plug :fetch_session
    -   plug :fetch_flash
    -   plug Guardian.Plug.VerifySession
    -   plug Guardian.Plug.LoadResource
    -   plug :protect_from_forgery
    -   plug :put_secure_browser_headers
    - end

      pipeline :token do
    -   plug Guardian.Plug.VerifyHeader, realm: "Bearer"
    -   plug Guardian.Plug.LoadResource
    +   plug MyAppWeb.Guardian.TokenPipeline
        plug Brando.Plug.SentryUserContext
      end

      scope "/admin", as: :admin do
        pipe_through :admin

        scope "/auth" do
    -     post "/login", Brando.SessionController, :create
    -     post "/logout", Brando.SessionController, :delete
    -     post "/verify", Brando.SessionController, :verify
    +     post "/login", MyAppWeb.SessionController, :create
    +     post "/logout", MyAppWeb.SessionController, :delete
    +     post "/verify", MyAppWeb.SessionController, :verify
        end

        # ...

    -   scope "/auth" do
    -     pipe_through :auth
    -     get  "/login", Brando.SessionController, :login, private: %{model: Brando.User}
    -     post "/login", Brando.SessionController, :login, private: %{model: Brando.User}
    -     get  "/logout", Brando.SessionController, :logout, private: %{model: Brando.User}
    -   end
    ```

  - `render_fragment` has been renamed to `fetch_fragment`.
    It is recommended to use `get_page_fragments/1` by `parent_key` to fetch all relevant fragments and display them
    with `render_fragment/2`

  - `brando_pages` has been incorporated into `brando` core. Remove `brando_pages` from your deps and application list

## pre 0.37.0
