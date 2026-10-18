defmodule BrandoWeb.FallbackControllerTest do
  # Not async: it sets :use_default_errors and :page_html_module.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Brando.Factory
  alias BrandoWeb.FallbackController

  defmodule PageHTML do
    @moduledoc false
    use Phoenix.Component

    def default(assigns), do: ~H|<main>{@page.title}{@partials["footer"]}</main>|
  end

  # The view of the controller that found no entry: a resource's, without the
  # CMS page templates.
  defmodule ResourceHTML do
    @moduledoc false
    use Phoenix.Component

    def show(assigns), do: ~H"<p>{@entry.title}</p>"
  end

  defmodule Layouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns), do: ~H|<body id="site">{@inner_content}</body>|
  end

  setup do
    put_test_env(:use_default_errors, false)
    put_test_env(:page_html_module, PageHTML)
    # Error pages and partials are read through the query cache.
    Cachex.clear(:query)
    on_exit(fn -> Cachex.clear(:query) end)
  end

  test "the site's 404 page renders with the CMS page templates, in the layout the page's controller chose" do
    Factory.insert(:page, uri: "404", has_url: false, title: "Not here")
    Factory.insert(:fragment, parent_key: "partials", key: "footer", rendered_blocks: "<footer>Footer</footer>")

    conn =
      build_conn(:get, "/articles/missing")
      |> Plug.Test.init_test_session(%{})
      |> assign(:language, "en")
      |> Phoenix.Controller.put_view(html: ResourceHTML)
      |> Phoenix.Controller.put_layout(false)
      |> Phoenix.Controller.put_root_layout(html: {Layouts, :root})
      |> FallbackController.call({:error, {:article, :not_found}})

    assert conn.status == 404
    assert conn.resp_body == ~s(<body id="site"><main>Not here<footer>Footer</footer></main></body>)
  end

  defmodule ErrorHTML do
    @moduledoc false
    use Phoenix.Component

    def render("404.html", _assigns), do: "Page not found"
  end

  defmodule ErrorEndpoint do
    @moduledoc false
    def config(:render_errors), do: [formats: [html: ErrorHTML]]
  end

  defmodule FooterLayouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns), do: ~H|<body id="site">{@inner_content}{@partials["footer"]}</body>|
  end

  defp built_in_404(root_layout, language \\ "en") do
    put_test_env(:use_default_errors, true)
    put_test_env(:endpoint_module, ErrorEndpoint)

    build_conn(:get, "/articles/missing")
    |> Plug.Test.init_test_session(%{})
    |> assign(:language, language)
    |> Phoenix.Controller.put_view(html: ResourceHTML)
    |> Phoenix.Controller.put_format("html")
    |> Phoenix.Controller.put_layout(false)
    |> Phoenix.Controller.put_root_layout(html: root_layout)
    |> FallbackController.call({:error, {:article, :not_found}})
  end

  test "the built-in 404 renders in the layout the page's controller chose, with the site's partials" do
    Factory.insert(:fragment, parent_key: "partials", key: "footer", rendered_blocks: "<footer>Footer</footer>")

    conn = built_in_404({FooterLayouts, :root})

    assert conn.status == 404
    assert conn.resp_body == ~s(<body id="site">Page not found<footer>Footer</footer></body>)
  end

  test "the built-in 404 stays a 404 in its layout when the partials cannot be read" do
    previous = Logger.level()
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: previous) end)

    # Not a language the fragments' column takes, so the query raises.
    log =
      capture_log(fn ->
        conn = built_in_404({FooterLayouts, :root}, "xx")

        assert conn.status == 404
        assert conn.resp_body == ~s(<body id="site">Page not found</body>)
      end)

    assert log =~ "The 404 page rendered without the partials"
  end

  test "the built-in 404 without a root layout reads no partials" do
    conn = built_in_404(false)

    assert conn.status == 404
    assert conn.resp_body == "Page not found"
    refute Map.has_key?(conn.assigns, :partials)
  end
end
