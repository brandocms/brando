defmodule <%= application_module %>Web.PageController do
  use <%= application_module %>Web, :controller
  alias Brando.Pages
  alias <%= application_module %>Web.FallbackController

  @type conn :: Plug.Conn.t()
  @type page_not_found :: {:error, {:page, :not_found}}

  action_fallback FallbackController

  @doc false
  @spec index(conn, map) :: page_not_found | conn
  def index(conn, _params) do
    with {:ok, page} <- Pages.get_page("index") do
      conn
      |> put_section("index")
      |> put_meta(Pages.Page, page)
      |> assign(:page, page)
      |> render(:index)
    end
  end

  @doc false
  @spec show(conn, map) :: page_not_found | conn
  def show(conn, %{"path" => path}) when is_list(path) do
    with {:ok, page} <- Brando.Pages.get_page(path) do
      #  {:ok, partials} <- Pages.get_fragments("partials") do
      conn
      |> put_section(page.key)
      |> put_meta(Pages.Page, page)
      |> put_title(page.title)
      # |> assign(:partials, partials)
      |> assign(:page, page)
      |> render(:show)
    end
  end

  @doc false
  @spec cookies(conn, map) :: conn
  def cookies(conn, _) do
    conn
    |> put_section("cookies")
    |> render(:cookies)
  end
end
