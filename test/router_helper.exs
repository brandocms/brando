defmodule RouterHelper do
  @moduledoc """
  Conveniences for testing routers and controllers.
  Must not be used to test endpoints as it does some
  pre-processing (like fetching params) which could
  skew endpoint tests.
  """

  import Plug.Test
  import ExUnit.CaptureIO

  @session Plug.Session.init(
    store: :cookie,
    key: "_app",
    encryption_salt: "yadayada",
    signing_salt: "yadayada"
  )

  @current_user %{__struct__: Brando.Users.Model.User,
      avatar: nil, email: "test@test.com",
      full_name: "Iggy Pop", id: 1,
      inserted_at: %Ecto.DateTime{day: 7, hour: 4, min: 36, month: 12, sec: 26, year: 2014},
      last_login: %Ecto.DateTime{day: 9, hour: 5, min: 2, month: 12, sec: 36, year: 2014},
      role: [:superuser, :staff, :admin],
      updated_at: %Ecto.DateTime{day: 14, hour: 21, min: 36, month: 1, sec: 53, year: 2015},
      username: "iggypop"}

  defmacro __using__(_) do
    quote do
      use Plug.Test
      import RouterHelper
    end
  end

  def with_session(conn) do
    conn
    |> Map.put(:secret_key_base, String.duplicate("abcdefgh", 8))
    |> Plug.Session.call(@session)
    |> Plug.Conn.fetch_session()
  end

  def with_user(conn, user \\ nil) do
    conn
    |> Plug.Conn.put_private(:model, Brando.Users.Model.User)
    |> Map.put(:secret_key_base, String.duplicate("abcdefgh", 8))
    |> Plug.Session.call(@session)
    |> Plug.Conn.fetch_session()
    |> Plug.Conn.put_session(:current_user, user || @current_user)
  end

  def call(router, verb, path, params \\ nil, headers \\ []) do
    conn = conn(verb, path, params, headers) |> Plug.Conn.fetch_params
    router.call(conn, router.init([]))
  end

  def call_with_session(router, verb, path, params \\ nil, headers \\ []) do
    conn = conn(verb, path, params, headers) |> with_session |> Plug.Conn.fetch_params
    router.call(conn, router.init([]))
  end

  def call_with_user(router, verb, path, params \\ nil, headers \\ []) do
    conn = conn(verb, path, params, headers)
    |> with_user
    |> Plug.Conn.fetch_params
    router.call(conn, router.init([]))
  end

  def json_with_custom_user(router, verb, path, params \\ nil, user: user) do
    conn = conn(verb, path, params)
    |> with_user(user)
    |> put_req_header("accept", "application/json")
    |> put_req_header("X-Requested-With", "XMLHttpRequest")
    |> Plug.Conn.fetch_params
    router.call(conn, router.init([]))
  end

  def call_with_custom_user(router, verb, path, params \\ nil, headers \\ [], user: user) do
    conn = conn(verb, path, params, headers)
    |> with_user(user)
    |> Plug.Conn.fetch_params
    router.call(conn, router.init([]))
  end

  def action(controller, verb, action, params \\ nil, headers \\ []) do
    conn = conn(verb, "/", params, headers) |> Plug.Conn.fetch_params
    controller.call(conn, controller.init(action))
  end

  def capture_log(fun) do
    capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end)
  end

  defmodule TestRouter do
    use Phoenix.Router
    alias Brando.Plug.Authenticate
    import Brando.Users.Admin.Routes
    import Brando.News.Admin.Routes
    import Brando.Images.Admin.Routes

    pipeline :admin do
      plug :accepts, ~w(html json)
      plug :fetch_session
      plug :fetch_flash
      plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
      plug Authenticate, login_url: "/login"
    end

    pipeline :browser do
      plug :accepts, ~w(html)
      plug :fetch_session
      plug :fetch_flash
    end

    pipeline :api do
      plug :accepts, ~w(json)
    end

    scope "/admin", as: :admin do
      pipe_through :admin
      user_resources "/brukere", Brando.Users.Admin.UserController, private: %{model: Brando.Users.Model.User}
      user_resources "/brukere2", private: %{model: Brando.Users.Model.User}
      user_resources "/brukere3"
      post_resources "/nyheter"
      image_resources "/bilder"
      get "/", Brando.Dashboard.Admin.DashboardController, :dashboard
    end

    scope "/" do
      pipe_through :browser
      get "/login", Brando.Auth.AuthController, :login,
        private: %{model: Brando.Users.Model.User,
                   layout: {Brando.Auth.LayoutView, "auth.html"}}
      post "/login", Brando.Auth.AuthController, :login,
        private: %{model: Brando.Users.Model.User,
                   layout: {Brando.Auth.LayoutView, "auth.html"}}
      get "/logout", Brando.Auth.AuthController, :logout,
        private: %{model: Brando.Users.Model.User,
                   layout: {Brando.Auth.LayoutView, "auth.html"}}
    end
  end
end