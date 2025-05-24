defmodule E2eProjectWeb.ClientController do
  use BrandoWeb, :controller
  alias E2eProject.Projects
  alias E2eProjectWeb.FallbackController

  @type conn :: Plug.Conn.t()

  action_fallback FallbackController

  @doc false
  @spec list(conn, map) :: conn
  def list(conn, _params) do
    list_opts = %{}

    with {:ok, clients} <- Projects.list_clients(list_opts) do
      conn
      |> assign(:clients, clients)
      |> put_section("projects")
      |> render(:list)
    end
  end

  @doc false
  @spec detail(conn, map) :: {:error, {:client, :not_found}} | conn
  def detail(conn, %{"slug" => slug}) do
    opts = %{matches: %{slug: slug}, preload: [:alternate_entries], status: :published}

    with {:ok, client} <- Projects.get_client(opts) do
      conn
      |> assign(:entry, client)
      |> put_hreflang(client)
      |> put_section("client")
      |> render(:detail)
    end
  end
end
