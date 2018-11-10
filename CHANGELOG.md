## v1.1.0

* Update for Ecto 3, Phoenix 1.4
* More configuration choices in backend/config
* Add opts to body_tag
* Add config genserver
* More flexible cookie_law
* Add rerendering of page fragments
* Larger default image sizes


## v1.0.0

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
    +     post "/login", FilmFarmsWeb.SessionController, :create
    +     post "/logout", FilmFarmsWeb.SessionController, :delete
    +     post "/verify", FilmFarmsWeb.SessionController, :verify
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

## pre v1.0.0
