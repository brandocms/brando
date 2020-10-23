defmodule <%= application_module %>Web.PageController do
  use <%= application_module %>Web, :controller
  alias Brando.I18n
  alias Brando.Pages
  alias <%= application_module %>Web.FallbackController

  @type conn :: Plug.Conn.t()
  @type page_not_found :: {:error, {:page, :not_found}}

  action_fallback FallbackController

  @doc false
  @spec index(conn, map) :: page_not_found | conn
  def index(conn, _params) do
    {language, parsed_path} = I18n.parse_path(conn.path_info)
    page_opts = %{matches: %{path: parsed_path, language: language}, status: :published}

    with {:ok, page} <- Pages.get_page(page_opts),
         {:ok, partials} <- Pages.get_fragments("partials") do
      conn
      |> put_section("index")
      |> put_meta(Pages.Page, page)
      |> assign(:partials, partials)
      |> assign(:page, page)
      |> render(page.template)
    end
  end

  @doc false
  @spec show(conn, map) :: page_not_found | conn
  def show(conn, %{"path" => path}) when is_list(path) do
    {language, parsed_path} = I18n.parse_path(conn.path)
    page_opts = %{matches: %{path: parsed_path, language: language}, status: :published}

    with {:ok, page} <- Pages.get_page(page_opts),
         {:ok, partials} <- Pages.get_fragments("partials") do
      conn
      |> put_section(page.key)
      |> put_meta(Pages.Page, page)
      |> put_title(page.title)
      |> assign(:partials, partials)
      |> assign(:page, page)
      |> render(page.template)
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
