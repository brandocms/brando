defmodule RouterHelper do
  @moduledoc """
  Conveniences for testing routers and controllers.
  Must not be used to test endpoints as it does some
  pre-processing (like fetching params) which could
  skew endpoint tests.
  """

  import Plug.Conn, only: [fetch_query_params: 1, fetch_session: 1,
                           put_session: 3, put_private: 3]
  alias Plug.Session

  @session Plug.Session.init(store: :cookie, key: "_app",
                             encryption_salt: "yadayada",
                             signing_salt: "yadayada")

  @current_user %{
    __struct__: Brando.User,
    id: 1,
    avatar: nil,
    email: "test@test.com",
    full_name: "Iggy Pop",
    inserted_at: %Ecto.DateTime{
      day: 7,
      hour: 4,
      min: 36,
      month: 12,
      sec: 26,
      year: 2014
    },
    last_login: %Ecto.DateTime{
      day: 9,
      hour: 5,
      min: 2,
      month: 12,
      sec: 36,
      year: 2014
    },
    updated_at: %Ecto.DateTime{
      day: 14,
      hour: 21,
      min: 36,
      month: 1,
      sec: 53,
      year: 2015
    },
    role: [:superuser, :staff, :admin],
    username: "iggypop",
    language: "en"
  }

  defmacro __using__(_) do
    quote do
      import RouterHelper
    end
  end

  def with_session(conn) do
    conn
    |> with_secret_key_base
    |> Session.call(@session)
    |> fetch_session
  end

  defp with_secret_key_base(conn) do
    conn
    |> Map.put(:secret_key_base, String.duplicate("abcdefgh", 8))
  end

  def with_user(conn, user \\ nil) do
    conn
    |> put_private(:model, Brando.User)
    |> with_session
    |> put_session(:current_user, user || @current_user)
  end

  def as_json(conn) do
    conn
    |> Plug.Conn.put_req_header("accept", "application/json")
  end

  def call(verb, path, params \\ nil) do
    Plug.Test.conn(verb, path, params)
  end

  def send_request(conn) do
    conn
    |> put_private(:phoenix_endpoint, Brando.endpoint)
    |> put_private(:plug_skip_csrf_protection, true)
    |> fetch_query_params
    |> Brando.router.call(Brando.router.init([]))
  end

  defmodule TestRouter do
    @moduledoc false
    use Phoenix.Router
    alias Brando.Plug.Authenticate
    import Brando.Dashboard.Routes.Admin
    import Brando.Users.Routes.Admin
    import Brando.Images.Routes.Admin
    import Brando.Plug.I18n

    pipeline :admin do
      plug :accepts, ~w(html json)
      plug :fetch_session
      plug :fetch_flash
      plug :put_admin_locale
      plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
      plug Authenticate, login_url: "/login"
    end

    pipeline :browser do
      plug :accepts, ~w(html)
      plug :fetch_session
      plug :fetch_flash
    end

    scope "/admin", as: :admin do
      pipe_through :admin
      user_routes "/users", Brando.Admin.UserController,
                            private: %{model: Brando.User}
      user_routes "/users2", private: %{model: Brando.User}
      user_routes "/users3"
      image_routes "/images"
      dashboard_routes "/"
    end

    scope "/coming-soon" do
      get "/", Brando.Integration.LockdownController, :index
    end

    scope "/" do
      pipe_through :browser
      get "/test123/:id/:language", Brando.TestController, :test
      get "/login", Brando.SessionController, :login,
        private: %{model: Brando.User,
                   layout: {Brando.Session.LayoutView, "auth.html"}}
      post "/login", Brando.SessionController, :login,
        private: %{model: Brando.User,
                   layout: {Brando.Session.LayoutView, "auth.html"}}
      get "/logout", Brando.SessionController, :logout,
        private: %{model: Brando.User,
                   layout: {Brando.Session.LayoutView, "auth.html"}}
    end
  end
end
