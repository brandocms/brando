defmodule BrandoIntegrationWeb.Projects.ProjectListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.BlueprintTest.Project

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title="Projects" subtitle="Overview" />

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end

defmodule BrandoIntegration.LockdownController do
  use Phoenix.Controller,
    namespace: Brando
end

defmodule BrandoIntegration.ProjectController do
  use Phoenix.Controller,
    namespace: Brando

  def index(conn, _), do: send_resp(conn, 200, "index")
  def show(conn, _), do: send_resp(conn, 200, "show")
end

defmodule BrandoIntegrationWeb.PageController do
  use Phoenix.Controller,
    namespace: Brando

  def index(conn, _), do: send_resp(conn, 200, "index")
  def show(conn, _), do: send_resp(conn, 200, "show")
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
      put_private: 3
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
end

defmodule BrandoIntegrationWeb.Router do
  @moduledoc false
  use Phoenix.Router
  import Brando.Router
  import Brando.Plug.I18n
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ~w(html)
    plug :fetch_session
    plug :fetch_flash
  end

  admin_routes do
    live "/projects", BrandoIntegrationWeb.Projects.ProjectListLive
  end

  scope "/coming-soon" do
    get "/", BrandoIntegration.LockdownController, :index
  end

  scope "/", assigns: %{language: "en"} do
    pipe_through :browser
    get "/projects", BrandoIntegration.ProjectController, :index
    get "/project/:uri", BrandoIntegration.ProjectController, :show
    get "/project/:uri/:id", BrandoIntegration.ProjectController, :show

    scope "/no", as: :no, assigns: %{language: "no"} do
      get "/prosjekter", BrandoIntegration.ProjectController, :index
      get "/prosjekt/:uri", BrandoIntegration.ProjectController, :show
      get "/prosjekt/:uri/:id", BrandoIntegration.ProjectController, :show
    end

    scope "/en", as: :en, assigns: %{language: "en"} do
      get "/projects", BrandoIntegration.ProjectController, :scoped_index
      get "/project/:uri", BrandoIntegration.ProjectController, :scoped_show
      get "/project/:uri/:id", BrandoIntegration.ProjectController, :scoped_show
    end

    page_routes()
  end
end
