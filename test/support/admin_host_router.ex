defmodule Brando.Test.AdminHostSiteController do
  @moduledoc false
  # A site's catch-all: a page of its own at `/admin`, and its 404 page
  # (`BrandoWeb.FallbackController`) for every other path
  use Phoenix.Controller, formats: [:html]

  action_fallback BrandoWeb.FallbackController

  def show(conn, %{"path" => ["admin"]}), do: Plug.Conn.send_resp(conn, 200, "The site's own page at /admin")
  def show(_conn, _params), do: {:error, {:page, :not_found}}
end

defmodule Brando.Test.AdminHostRouter do
  @moduledoc false
  # The admin, MCP and a site's catch-all in the order an installation
  # generates them, with `Brando.Plug.Tenant` in the site's pipeline
  use Phoenix.Router

  import Brando.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :assign_language
    plug Brando.Plug.Tenant
  end

  admin_routes do
    live "/projects", BrandoIntegrationWeb.Projects.ProjectListLive
  end

  mcp_routes()

  scope "/" do
    pipe_through :browser
    get "/*path", Brando.Test.AdminHostSiteController, :show
  end

  def assign_language(conn, _opts), do: Plug.Conn.assign(conn, :language, "en")
end
