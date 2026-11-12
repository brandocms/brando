defmodule BrandoWeb.FallbackControllerTest do
  # Not async: it sets :use_default_errors and :page_html_module.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Brando.Factory
  alias BrandoWeb.FallbackController
  alias Phoenix.Controller

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
      |> Controller.put_view(html: ResourceHTML)
      |> Controller.put_layout(false)
      |> Controller.put_root_layout(html: {Layouts, :root})
      |> FallbackController.call({:error, {:article, :not_found}})

    assert conn.status == 404
    assert conn.resp_body == ~s(<body id="site"><main>Not here<footer>Footer</footer></main></body>)
  end

  defmodule AcmePageHTML do
    @moduledoc false
    use Phoenix.Component

    def default(assigns), do: ~H|<main class="acme">{@page.title}{@footer_color}</main>|
  end

  defmodule Acme do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {Layouts, :root}, page_html: AcmePageHTML

    def page_assigns(page, _assigns), do: %{footer_color: ":#{page.uri}"}
  end

  test "a registered site's 404 page renders with its frontend's templates and page assigns" do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:site_frontends, %{"fallback-acme" => Acme})
    prefix = "tenant_fallback-acme_production"
    BrandoIntegration.Repo.query!(~s(CREATE SCHEMA "#{prefix}"))

    for table <- ~w(pages pages_alternates content_vars pages_fragments sites_seos sites_identities) do
      BrandoIntegration.Repo.query!(~s{CREATE TABLE "#{prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)})
    end

    # The site's error page caches its SEO and identity under its prefix
    cached = for key <- [:seo, :identity], into: %{}, do: {key, Cachex.get!(:cache, {:tenant, prefix, key})}

    on_exit(fn ->
      for {key, value} <- cached do
        if value,
          do: Cachex.put(:cache, {:tenant, prefix, key}, value),
          else: Cachex.del(:cache, {:tenant, prefix, key})
      end
    end)

    Brando.Tenant.put_prefix(prefix)

    page = Factory.insert(:page, uri: "404", has_url: false, title: "Not here")
    BrandoIntegration.Repo.query!(~s{INSERT INTO "#{prefix}".pages SELECT * FROM public.pages WHERE id = $1}, [page.id])
    BrandoIntegration.Repo.query!("DELETE FROM public.pages WHERE id = $1", [page.id])

    conn =
      build_conn(:get, "/articles/missing")
      |> Plug.Test.init_test_session(%{})
      |> assign(:language, "en")
      |> Controller.put_view(html: ResourceHTML)
      |> Controller.put_layout(false)
      |> Controller.put_root_layout(html: {Layouts, :root})
      |> FallbackController.call({:error, {:article, :not_found}})

    assert conn.status == 404
    assert conn.resp_body == ~s(<body id="site"><main class="acme">Not here:404</main></body>)
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
    |> Controller.put_view(html: ResourceHTML)
    |> Controller.put_format("html")
    |> Controller.put_layout(false)
    |> Controller.put_root_layout(html: root_layout)
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

  test "a site without a frontend gets the built-in 404 and 410 pages" do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:site_frontends, %{"fallback-acme" => Acme})
    put_test_env(:endpoint_module, ErrorEndpoint)
    prefix = "tenant_fallback-globex_production"
    Brando.Tenant.put_prefix(prefix)

    # The site's redirects, as its SEO cache holds them: the site has no schema
    seo = %Brando.Sites.SEO{redirects: [%Brando.Sites.Redirect{from: "/articles/gone", to: "/", code: 410}]}
    cached = Cachex.get!(:cache, {:tenant, prefix, :seo})
    Cachex.put(:cache, {:tenant, prefix, :seo}, %{"en" => seo})

    on_exit(fn ->
      if cached,
        do: Cachex.put(:cache, {:tenant, prefix, :seo}, cached),
        else: Cachex.del(:cache, {:tenant, prefix, :seo})

      Brando.Tenant.put_prefix(nil)
    end)

    conn =
      build_conn(:get, "/articles/missing")
      |> Plug.Test.init_test_session(%{})
      |> assign(:language, "en")
      |> Controller.put_view(html: ResourceHTML)
      |> Controller.put_layout(false)
      |> FallbackController.call({:error, {:article, :not_found}})

    assert conn.status == 404
    assert conn.resp_body == "Page not found"

    conn =
      build_conn(:get, "/articles/gone")
      |> Plug.Test.init_test_session(%{})
      |> assign(:language, "en")
      |> FallbackController.call({:error, {:article, :not_found}})

    assert conn.status == 410
    assert conn.resp_body == "Gone."
  end

  defmodule HaltingRouter do
    @moduledoc false
    def browser(conn, _opts), do: conn |> Plug.Conn.send_resp(403, "Halted") |> Plug.Conn.halt()
  end

  test "an error page leaves a conn the browser pipeline halted alone" do
    put_test_env(:router_module, HaltingRouter)

    conn =
      build_conn(:get, "/articles/missing")
      |> assign(:language, "en")
      |> FallbackController.call({:error, {:article, :not_found}})

    assert conn.halted
    assert conn.status == 403
    assert conn.resp_body == "Halted"
  end

  test "the built-in 404 without a root layout reads no partials" do
    conn = built_in_404(false)

    assert conn.status == 404
    assert conn.resp_body == "Page not found"
    refute Map.has_key?(conn.assigns, :partials)
  end
end
