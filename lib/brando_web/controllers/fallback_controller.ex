defmodule BrandoWeb.FallbackController do
  use Phoenix.Controller, formats: [:html, :json]

  import Brando.Plug.HTML
  import Plug.Conn

  require Logger

  alias Brando.I18n
  alias Brando.Pages
  alias Brando.Site.Frontend
  alias Brando.Sites.FourOhFour
  alias Brando.Sites.Redirects
  alias Brando.SSG.LocalDelivery

  @doc """
  Handle errors. A missing page on a host serving a published build is that
  build's 404 (`Brando.SSG.LocalDelivery.answer_not_found/1`).
  """
  def call(conn, {:error, {_, :not_found}}) do
    case LocalDelivery.answer_not_found(conn) do
      %Plug.Conn{halted: true} = answered -> answered
      conn -> not_found(conn)
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

  defp not_found(%{assigns: %{language: language}} = conn) do
    case test_redirect(conn, language) do
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
          render_built_in_error_page(conn, 410)
        end

      {:ok, {:redirect, {url, code}}} ->
        # Redirect
        conn
        |> put_resp_header("location", url)
        |> resp(code, "You are being redirected.")
        |> halt()
    end
  end

  # A static build requests the site's error page on a path no page has
  # (`Brando.SSG.not_found_path/0`), which a rule matching as a prefix would
  # otherwise redirect
  defp test_redirect(conn, language) do
    if Brando.SSG.Context.build_request?(conn) and not_found_probe?(conn.path_info),
      do: {:error, {:redirects, :no_match}},
      else: Redirects.test_redirect(conn.path_info, language)
  end

  # With or without the language prefix `put_locale` adds
  defp not_found_probe?(path_info) do
    probe = String.split(Brando.SSG.not_found_path(), "/", trim: true)
    path_info == probe or match?([_language | ^probe], path_info)
  end

  # A pipeline plug may answer itself, a 404 for a site without a frontend
  defp render_error_page(conn, code) do
    case browser_pipeline(conn) do
      %{halted: true} = conn -> conn
      conn -> render_cms_error_page(conn, code, Frontend.page_html())
    end
  end

  # A site with no frontend has no templates to render its error page with
  defp render_cms_error_page(conn, code, nil), do: render_built_in_error_page(conn, code)

  defp render_cms_error_page(conn, 404, page_html) do
    path = conn.path_info
    {language, parsed_path} = I18n.parse_path(path)

    page_opts = %{
      matches: %{path: "404", language: language, has_url: false},
      status: :published,
      preload: [:alternate_entries, :vars],
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
      |> Frontend.put_page_assigns(page)
      |> put_view(html: page_html)
      |> render(page.template)
    end
  end

  defp render_cms_error_page(conn, 410, page_html) do
    path = conn.path_info
    {language, parsed_path} = I18n.parse_path(path)

    page_opts = %{
      matches: %{path: "410", language: language, has_url: false},
      status: :published,
      preload: [:alternate_entries, :vars],
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
      |> Frontend.put_page_assigns(page)
      |> put_view(html: page_html)
      |> render(page.template)
    end
  end

  # The page's controller chose the site's root layout; the :browser pipeline
  # may put phx.new's over it.
  defp browser_pipeline(conn) do
    root_layout = root_layout(conn, "html")
    conn = Brando.router().browser(conn, [])

    # A plug that answered has sent the response: its conn takes no layout
    if root_layout && !conn.halted, do: put_root_layout(conn, html: root_layout), else: conn
  end

  defp render_built_in_error_page(conn, 404) do
    conn
    |> put_status(:not_found)
    |> put_layout(false)
    |> put_view(Brando.endpoint().config(:render_errors)[:formats])
    |> FourOhFour.add_404()
    |> assign_partials()
    |> render(:"404")
  end

  defp render_built_in_error_page(conn, 410) do
    conn
    |> resp(410, "Gone.")
    |> halt()
  end

  # The error renders in the root layout the failing controller chose, and the
  # site's layout renders its footer from the partials, which that controller
  # had not assigned yet.
  defp assign_partials(%{assigns: %{partials: _}} = conn), do: conn

  defp assign_partials(conn) do
    if root_layout(conn, "html"),
      do: assign(conn, :partials, partials(conn.assigns.language)),
      else: conn
  end

  # A footer is not worth turning the 404 into a 500: when the fragments cannot
  # be read (the database is down and the cache is cold), the page renders
  # without them.
  defp partials(language) do
    {:ok, partials} =
      Pages.get_fragments(%{filter: %{parent_key: "partials", language: language}, cache: {:ttl, :infinite}})

    partials
  rescue
    exception ->
      Logger.warning("The 404 page rendered without the partials, which raised:\n" <> Exception.message(exception))
      %{}
  end
end
