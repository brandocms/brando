defmodule BrandoWeb.FallbackController do
  use Phoenix.Controller,
    namespace: Brando.config(:web_module),
    formats: [:html, :json]

  import Brando.Plug.HTML
  import Plug.Conn

  alias Brando.I18n
  alias Brando.Pages
  alias Brando.Sites.FourOhFour
  alias Brando.Sites.Redirects

  @doc """
  Handle errors
  """
  def call(%{assigns: %{language: language}} = conn, {:error, {_, :not_found}}) do
    case Redirects.test_redirect(conn.path_info, language) do
      {:error, {:redirects, :no_match}} ->
        # 404
        if Brando.config(:use_default_errors) == false do
          render_error_page(conn, 404)
        else
          render_built_in_error_page(conn, 404)
        end

      {:ok, {:redirect, {_url, 410}}} ->
        # 410 GONE
        if Brando.config(:use_default_errors) == false do
          render_error_page(conn, 410)
        else
          conn
          |> resp(410, "Gone.")
          |> halt()
        end

      {:ok, {:redirect, {url, code}}} ->
        # Redirect
        conn
        |> put_resp_header("location", url)
        |> resp(code, "You are being redirected.")
        |> halt()
    end
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_layout(false)
    |> put_view(Brando.endpoint().config(:render_errors)[:formats])
    |> render(:"401")
  end

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> put_layout(false)
    |> put_view(Brando.endpoint().config(:render_errors)[:formats])
    |> render(:"400")
  end

  defp render_error_page(conn, 404) do
    # run conn through :browser pipeline
    conn = Brando.router().browser(conn, [])
    path = conn.path_info
    {language, parsed_path} = I18n.parse_path(path)

    page_opts = %{
      matches: %{path: "404", language: language, has_url: false},
      status: :published,
      preload: [:alternate_entries],
      cache: {:ttl, :infinite}
    }

    fragment_opts = %{
      filter: %{parent_key: "partials", language: language},
      cache: {:ttl, :infinite}
    }

    with {:ok, page} <- Pages.get_page(page_opts),
         {:ok, partials} <- Pages.get_fragments(fragment_opts) do
      conn
      |> put_status(:not_found)
      |> put_section(page.uri)
      |> put_meta(Pages.Page, page)
      |> put_hreflang(page)
      |> put_title(page.title)
      |> FourOhFour.add_404()
      |> assign(:partials, partials)
      |> assign(:page, page)
      |> assign(:parsed_path, parsed_path)
      |> render(page.template)
    end
  end

  defp render_error_page(conn, 410) do
    # run conn through :browser pipeline
    conn = Brando.router().browser(conn, [])
    path = conn.path_info
    {language, parsed_path} = I18n.parse_path(path)

    page_opts = %{
      matches: %{path: "410", language: language, has_url: false},
      status: :published,
      preload: [:alternate_entries],
      cache: {:ttl, :infinite}
    }

    fragment_opts = %{
      filter: %{parent_key: "partials", language: language},
      cache: {:ttl, :infinite}
    }

    with {:ok, page} <- Pages.get_page(page_opts),
         {:ok, partials} <- Pages.get_fragments(fragment_opts) do
      conn
      |> put_status(:gone)
      |> put_section(page.uri)
      |> put_meta(Pages.Page, page)
      |> put_hreflang(page)
      |> put_title(page.title)
      |> assign(:partials, partials)
      |> assign(:page, page)
      |> assign(:parsed_path, parsed_path)
      |> render(page.template)
    end
  end

  defp render_built_in_error_page(conn, 404) do
    conn
    |> put_status(:not_found)
    |> put_layout(false)
    |> put_view(Brando.endpoint().config(:render_errors)[:formats])
    |> FourOhFour.add_404()
    |> render(:"404")
  end
end
