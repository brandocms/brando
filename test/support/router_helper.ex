defmodule Brando.Integration.LockdownController do
  use Phoenix.Controller,
        namespace: Brando
end

defmodule RouterHelper do
  @moduledoc """
  Conveniences for testing routers and controllers.
  Must not be used to test endpoints as it does some
  pre-processing (like fetching params) which could
  skew endpoint tests.
  """

  import Plug.Conn,
    only: [
      fetch_query_params: 1,
      fetch_session: 1,
      put_session: 3,
      put_private: 3,
      put_req_header: 3
    ]

  alias Plug.Session

  @session Plug.Session.init(
             store: :cookie,
             key: "_app",
             encryption_salt: "yadayada",
             signing_salt: "yadayada"
           )

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

  def as_json(conn) do
    conn
    |> Plug.Conn.put_req_header("accept", "application/json")
  end

  def call(verb, path, params \\ nil) do
    Plug.Test.conn(verb, path, params)
  end

  def send_request(conn) do
    conn
    |> put_private(:phoenix_endpoint, Brando.endpoint())
    |> put_private(:plug_skip_csrf_protection, true)
    |> fetch_query_params
    |> Brando.router().call(Brando.router().init([]))
  end

  defmodule TestRouter do
    @moduledoc false
    use Phoenix.Router
    import Brando.Images.Routes.Admin.API
    import Brando.Plug.I18n

    pipeline :admin do
      plug :accepts, ~w(html json)
      plug :fetch_session
      plug :fetch_flash
      plug :put_admin_locale
      plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
    end

    pipeline :browser do
      plug :accepts, ~w(html)
      plug :fetch_session
      plug :fetch_flash
    end

    scope "/admin", as: :admin do
      pipe_through :admin
      api_image_routes("/images")
    end

    scope "/coming-soon" do
      get "/", Brando.Integration.LockdownController, :index
    end

    scope "/" do
      pipe_through :browser
    end
  end
end
