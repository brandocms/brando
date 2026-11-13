defmodule Brando.Test.SiteRouter do
  @moduledoc false
  # A frontend router in the plug order an installation generates:
  # `Brando.Plug.Tenant` in `:browser`, before `page_routes/1`
  use Phoenix.Router

  import Brando.Router
  import Phoenix.Controller, only: [accepts: 2, put_secure_browser_headers: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_secure_browser_headers
    plug :assign_language
    plug Brando.Plug.Tenant
  end

  scope "/" do
    pipe_through :browser
    page_routes(catch_all: false)
  end

  def assign_language(conn, _opts), do: Plug.Conn.assign(conn, :language, "en")
end
