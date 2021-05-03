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

defmodule BrandoIntegration.TestSchema do
  use Absinthe.Schema
  use BrandoGraphQL.Schema

  import_types Absinthe.Plug.Types
  import_types BrandoGraphQL.Schema.Types

  def context(ctx) do
    loader =
      Dataloader.new()
      |> import_brando_dataloaders(ctx)

    Map.put(ctx, :loader, loader)
  end

  def plugins do
    [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
  end

  query do
    import_brando_queries()
  end

  mutation do
    import_brando_mutations()
  end

  enum :sort_order do
    value :asc
    value :desc
  end

  def middleware(middleware, _field, %{identifier: :mutation}),
    do: middleware ++ [BrandoGraphQL.Schema.Middleware.ChangesetErrors]

  def middleware(middleware, _field, _object),
    do: middleware ++ [BrandoGraphQL.Schema.Middleware.QueryErrors]
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
end

defmodule BrandoIntegrationWeb.Guardian.TokenPipeline do
  @moduledoc """
  Guardian token pipeline
  """
  use Guardian.Plug.Pipeline,
    otp_app: :brando,
    module: BrandoIntegration.Guardian,
    error_handler: Brando.Guardian.GQLErrorHandler

  plug Guardian.Plug.VerifyHeader, realm: "Bearer"
  plug Guardian.Plug.LoadResource, allow_blank: true
end

defmodule BrandoIntegrationWeb.Guardian.GQLPipeline do
  @moduledoc """
  Guardian pipeline
  """
  use Guardian.Plug.Pipeline,
    otp_app: :brando,
    module: BrandoIntegration.Guardian,
    error_handler: Brando.Guardian.GQLErrorHandler

  plug Guardian.Plug.VerifyHeader, realm: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource, ensure: true
end

defmodule BrandoIntegrationWeb.Router do
  @moduledoc false
  use Phoenix.Router
  import Brando.Router
  import Brando.Plug.I18n

  pipeline :browser do
    plug :accepts, ~w(html)
    plug :fetch_session
    plug :fetch_flash
  end

  admin_routes()

  scope "/coming-soon" do
    get "/", BrandoIntegration.LockdownController, :index
  end

  scope "/" do
    pipe_through :browser
    get "/projects", BrandoIntegration.ProjectController, :index
    get "/project/:uri", BrandoIntegration.ProjectController, :show
    get "/project/:uri/:id", BrandoIntegration.ProjectController, :show
    page_routes()
  end
end
