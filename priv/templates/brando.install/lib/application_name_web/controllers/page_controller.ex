defmodule <%= application_module %>Web.PageController do
  use <%= application_module %>Web, :controller
  alias Brando.Pages

  @doc false
  def index(conn, _params) do
    f = Pages.get_page_fragments("index")

    conn
    |> put_section("index")
    |> assign(:section, "index")
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