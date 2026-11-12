defmodule Brando.Plug.SiteFrontendTest do
  # Not async: it sets :site_frontends and :default_site_frontend, and the
  # tenant cache is shared.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  defmodule AcmeLayouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns), do: ~H|<html data-site="acme">
  {@inner_content}
  <footer>{@footer}</footer>
</html>|
  end

  defmodule AcmePageHTML do
    @moduledoc false
    use Phoenix.Component

    def home(assigns), do: ~H"<main>acme home</main>"
  end

  defmodule NextLayouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns), do: ~H|<html data-site="acme-next">{@inner_content}</html>|
  end

  defmodule NextPageHTML do
    @moduledoc false
    use Phoenix.Component

    def home(assigns), do: ~H"<main>acme next home</main>"
  end

  defmodule GlobexLayouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns), do: ~H|<html data-site="globex">{@inner_content}</html>|
  end

  defmodule GlobexPageHTML do
    @moduledoc false
    use Phoenix.Component

    def home(assigns), do: ~H"<main>globex home</main>"
  end

  defmodule Acme do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {AcmeLayouts, :root}, page_html: AcmePageHTML

    def layout_assigns(language), do: %{footer: "acme footer:#{language}"}
    def page_assigns(page, _assigns), do: %{footer_color: "acme:#{page.title}"}
  end

  defmodule AcmeNext do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {NextLayouts, :root}, page_html: NextPageHTML
  end

  defmodule Globex do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {GlobexLayouts, :root}, page_html: GlobexPageHTML
  end

  # The application's own page templates and layouts, for when nothing is configured
  defmodule CMSLayouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns), do: ~H|<html data-site="cms">{@inner_content}</html>|
  end

  defmodule CMSPageHTML do
    @moduledoc false
    use Phoenix.Component

    def home(assigns), do: ~H"<main>cms home</main>"
  end

  # Renders the page as `put_page_assigns/2` leaves the assigns
  defmodule PageAction do
    @moduledoc false
    def show(conn) do
      page = %Brando.Pages.Page{title: "About"}

      conn
      |> Plug.Conn.assign(:page, page)
      |> Brando.Site.Frontend.put_page_assigns(page)
      |> then(&Plug.Conn.assign(&1, :seen, Map.take(&1.assigns, [:footer, :footer_color])))
      |> Phoenix.Controller.render(:home)
    end
  end

  # The one page controller every site shares, as `mix brando.gen.site` writes it
  defmodule PageController do
    @moduledoc false
    use BrandoWeb, :controller

    plug :put_view, html: Brando.Plug.SiteFrontendTest.CMSPageHTML
    plug :put_layout, false
    plug :put_root_layout, html: {Brando.Plug.SiteFrontendTest.CMSLayouts, :root}
    plug Brando.Plug.SiteFrontend

    def show(conn, _params), do: PageAction.show(conn)
  end

  # A page controller with the defaults of `use BrandoWeb, :controller`: the
  # application's `Layouts.app` as its layout and `LegacyPageHTML` as its view
  defmodule LegacyPageController do
    @moduledoc false
    use BrandoWeb, :controller

    plug Brando.Plug.SiteFrontend

    def show(conn, _params), do: PageAction.show(conn)
  end

  defmodule LegacyPageHTML do
    @moduledoc false
    use Phoenix.Component

    def home(assigns), do: ~H"<main>legacy home</main>"
  end

  # Another controller, with its own templates, in the site's layout
  defmodule ProjectController do
    @moduledoc false
    use BrandoWeb, :controller

    plug :put_view, html: Brando.Plug.SiteFrontendTest.CMSPageHTML
    plug Brando.Plug.SiteFrontend, view: false

    def show(conn, _params), do: render(conn, :home)
  end

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:site_frontends, nil)
    put_test_env(:default_site_frontend, nil)
    Tenant.put_prefix(nil)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    for {key, environments} <- [
          {"acme", [{"production", true, "www.acme.test"}, {"staging", false, "staging.acme.test"}]},
          {"globex", [{"production", true, "www.globex.test"}]}
        ] do
      {:ok, site} =
        Registry.create_site(%{
          name: key,
          key: key,
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      for {environment_key, live, domain} <- environments do
        {:ok, _environment} =
          Registry.create_environment(site, %{name: environment_key, key: environment_key, live: live, domain: domain},
            actor: :system
          )
      end
    end

    :ok
  end

  defp request(host, controller \\ PageController) do
    :get
    |> Plug.Test.conn("https://#{host}/about")
    |> Map.put(:host, host)
    |> Plug.Conn.assign(:language, "en")
    |> Brando.Plug.Tenant.call([])
    |> Phoenix.Controller.put_format("html")
    |> controller.call(controller.init(:show))
  end

  # The templates as written, without the formatter's line breaks
  defp html(conn), do: String.replace(conn.resp_body, ~r/>\s+</, "><")

  test "the same path renders each site's layout, layout assigns and template" do
    put_test_env(:site_frontends, %{"acme" => Acme, "globex" => Globex})

    acme = request("www.acme.test")
    assert acme.status == 200
    assert html(acme) == ~s(<html data-site="acme"><main>acme home</main><footer>acme footer:en</footer></html>)

    globex = request("www.globex.test")
    assert globex.status == 200
    assert html(globex) == ~s(<html data-site="globex"><main>globex home</main></html>)
  end

  test "an environment entry renders its module on that environment only" do
    put_test_env(:site_frontends, %{"acme" => Acme, {"acme", "staging"} => AcmeNext})

    assert html(request("staging.acme.test")) ==
             ~s(<html data-site="acme-next"><main>acme next home</main></html>)

    assert html(request("www.acme.test")) =~ ~s(<html data-site="acme"><main>acme home</main>)
  end

  test "a site without an entry answers 404 once the registry has one" do
    put_test_env(:site_frontends, %{"acme" => Acme})
    put_test_env(:default_site_frontend, Globex)

    conn = request("www.globex.test")
    assert conn.halted
    assert conn.status == 404
  end

  test "with an empty registry a site renders the default frontend" do
    put_test_env(:site_frontends, %{})
    put_test_env(:default_site_frontend, Globex)

    conn = request("www.acme.test")
    assert conn.status == 200
    assert html(conn) == ~s(<html data-site="globex"><main>globex home</main></html>)
  end

  test "the site's view, root layout and assigns replace the page controller's, with no inner layout" do
    put_test_env(:site_frontends, %{"acme" => Acme})

    for controller <- [PageController, LegacyPageController] do
      conn = request("www.acme.test", controller)
      assert conn.status == 200
      assert html(conn) == ~s(<html data-site="acme"><main>acme home</main><footer>acme footer:en</footer></html>)
      assert conn.assigns.seen == %{footer: "acme footer:en", footer_color: "acme:About"}
    end
  end

  test "with nothing configured the page controller renders its own view and layouts" do
    conn = request("www.acme.test")
    assert conn.status == 200
    assert html(conn) == ~s(<html data-site="cms"><main>cms home</main></html>)
    assert conn.assigns.seen == %{}

    conn = request("www.acme.test", LegacyPageController)
    assert conn.status == 200
    assert html(conn) == "<html><head></head><body><main>legacy home</main></body></html>"
  end

  test "view: false gives the site's layout and keeps the controller's view" do
    put_test_env(:site_frontends, %{"acme" => Acme})

    conn = request("www.acme.test", ProjectController)
    assert conn.status == 200
    assert html(conn) == ~s(<html data-site="acme"><main>cms home</main><footer>acme footer:en</footer></html>)
  end

  test "with nothing configured the conn passes through unchanged" do
    conn =
      :get
      |> Plug.Test.conn("https://www.acme.test/about")
      |> Map.put(:host, "www.acme.test")
      |> Plug.Conn.assign(:language, "en")
      |> Brando.Plug.Tenant.call([])

    assert Brando.Plug.SiteFrontend.call(conn, []) == conn
  end
end
