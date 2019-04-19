defmodule <%= application_module %>Web.PageController do
  use <%= application_module %>Web, :controller
  alias Brando.Images
  alias Brando.Pages
  alias <%= application_module %>Web.FallbackController

  action_fallback FallbackController

  @doc false
  def index(conn, _params) do
    f = Pages.get_page_fragments("index")
    # {:ok, s} =
    #   Images.get_series(
    #     "forside",
    #     "bildekarusell"
    #   )
    s = []

    conn
    |> put_section("index")
    |> assign(:section, "index")
    |> assign(:s, s)
    |> assign(:f, f)
    |> render(:index)
  end

  @doc false
  def cookies(conn, _) do
    conn
    |> put_section("cookies")
    |> assign(:section, "cookies")
    |> render(:cookies)
  end
end
