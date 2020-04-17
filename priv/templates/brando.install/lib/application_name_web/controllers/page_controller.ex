defmodule <%= application_module %>Web.PageController do
  use <%= application_module %>Web, :controller
  alias Brando.Pages
  alias <%= application_module %>Web.FallbackController

  action_fallback FallbackController

  @doc false
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
  def cookies(conn, _) do
    conn
    |> put_section("cookies")
    |> render(:cookies)
  end
end
