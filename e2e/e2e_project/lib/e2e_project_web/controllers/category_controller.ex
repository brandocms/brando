defmodule E2eProjectWeb.CategoryController do
  use BrandoWeb, :controller
  alias E2eProject.Projects
  alias E2eProjectWeb.FallbackController

  @type conn :: Plug.Conn.t()

  action_fallback FallbackController

  @doc false
  @spec list(conn, map) :: conn
  def list(conn, _params) do
    list_opts = %{}

    with {:ok, categories} <- Projects.list_categories(list_opts) do
      conn
      |> assign(:categories, categories)
      |> put_section("projects")
      |> render(:list)
    end
  end

  @doc false
  @spec detail(conn, map) :: {:error, {:category, :not_found}} | conn
  def detail(conn, %{"slug" => slug}) do
    opts = %{matches: %{slug: slug}, preload: [:alternate_entries], status: :published}

    with {:ok, category} <- Projects.get_category(opts) do
      conn
      |> assign(:entry, category)
      |> put_hreflang(category)
      |> put_section("category")
      |> render(:detail)
    end
  end
end
