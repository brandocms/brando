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
    get "/robots.txt", BrandoWeb.SEOController, :robots
    get "/*path", Brando.Test.AdminHostSiteController, :show
  end

  def assign_language(conn, _opts), do: Plug.Conn.assign(conn, :language, "en")
end

defmodule Brando.Test.AdminHostPublicRoutesController do
  @moduledoc false
  # The application's own public routes under the admin's path
  use Phoenix.Controller, formats: [:html]

  def show(conn, _params), do: Plug.Conn.send_resp(conn, 200, "The application's own #{conn.request_path}")
end

defmodule Brando.Test.AdminHostScopedRouter do
  @moduledoc false
  # The admin and MCP inside an enclosing scope, the site's catch-all after.
  # The import admin_routes makes ends with the scope, so the router makes it
  # for the pipelines Phoenix compiles at the end of the module.
  use Phoenix.Router

  import BrandoAdmin.UserAuth, only: [redirect_if_user_is_authenticated: 2, require_authenticated_user: 2]
  import Brando.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :assign_language
    plug Brando.Plug.Tenant
  end

  scope "/cms" do
    admin_routes do
      live "/projects", BrandoIntegrationWeb.Projects.ProjectListLive
    end

    mcp_routes()
  end

  scope "/" do
    pipe_through :browser
    get "/*path", Brando.Test.AdminHostSiteController, :show
  end

  def assign_language(conn, _opts), do: Plug.Conn.assign(conn, :language, "en")
end

defmodule Brando.Test.AdminHostPublicRoutesRouter do
  @moduledoc false
  # Public routes of the application's own under the admin's path, before and
  # after admin_routes, and a catch-all after them
  use Phoenix.Router

  import Brando.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :assign_language
    plug Brando.Plug.Tenant
  end

  scope "/" do
    pipe_through :browser
    get "/admin", Brando.Test.AdminHostPublicRoutesController, :show
    get "/admin/about/:section", Brando.Test.AdminHostPublicRoutesController, :show
  end

  admin_routes do
    live "/projects", BrandoIntegrationWeb.Projects.ProjectListLive
  end

  mcp_routes()

  scope "/" do
    pipe_through :browser
    get "/admin/login", Brando.Test.AdminHostPublicRoutesController, :show
    get "/*path", Brando.Test.AdminHostSiteController, :show
  end

  def assign_language(conn, _opts), do: Plug.Conn.assign(conn, :language, "en")
end
