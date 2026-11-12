defmodule Brando.Site.FrontendTest do
  # Not async: it sets :site_frontends and :default_site_frontend.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Exception.ConfigError
  alias Brando.Site.Frontend
  alias Brando.Tenant

  defmodule AcmeLayouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns), do: ~H|<html data-site="acme">{@inner_content}</html>|
  end

  defmodule AcmePageHTML do
    @moduledoc false
    use Phoenix.Component

    def default(assigns), do: ~H"<main>acme</main>"
    def home(assigns), do: ~H"<main>acme home</main>"
  end

  defmodule NextPageHTML do
    @moduledoc false
    use Phoenix.Component

    def landing(assigns), do: ~H"<main>next</main>"
  end

  defmodule Acme do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {AcmeLayouts, :root}, page_html: AcmePageHTML

    def page_assigns(page, assigns), do: %{footer_color: "#{page.title}:#{assigns.language}"}
  end

  defmodule AcmeNext do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {AcmeLayouts, :root}, page_html: NextPageHTML
  end

  defmodule Default do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {AcmeLayouts, :root}, page_html: AcmePageHTML
  end

  defmodule NoCallbacks do
    @moduledoc false
    def layout_assigns(_language), do: %{}
  end

  setup do
    Tenant.put_prefix(nil)
    on_exit(fn -> Tenant.put_prefix(nil) end)
    put_test_env(:site_frontends, nil)
    put_test_env(:default_site_frontend, nil)
    :ok
  end

  defp current(mode, prefix) do
    put_test_env(:tenancy_mode, mode)
    Tenant.put_prefix(prefix)
    Frontend.current()
  end

  describe "current/0" do
    test "an environment entry wins over the site's" do
      put_test_env(:site_frontends, %{"acme" => Acme, {"acme", "staging"} => AcmeNext})

      for mode <- [:single, :multi] do
        assert current(mode, "tenant_acme_staging") == AcmeNext
        assert current(mode, "tenant_acme_production") == Acme
      end
    end

    test "a site entry applies to each of its environments" do
      put_test_env(:site_frontends, %{"acme" => Acme})
      put_test_env(:default_site_frontend, Default)

      for mode <- [:single, :multi], environment <- ["production", "staging"] do
        assert current(mode, "tenant_acme_#{environment}") == Acme
      end

      assert current(:single, "tenant_acme-corp_production") == Default
    end

    test "in :multi a site without an entry has no frontend once the registry has one" do
      put_test_env(:site_frontends, %{"acme" => Acme})
      put_test_env(:default_site_frontend, Default)

      assert current(:multi, "tenant_globex_production") == nil
      assert current(:multi, nil) == nil
      assert current(:single, "tenant_globex_production") == Default
      assert current(:none, nil) == Default
    end

    test "with an empty registry every site gets the default" do
      put_test_env(:site_frontends, %{})
      put_test_env(:default_site_frontend, Default)

      assert current(:multi, "tenant_globex_production") == Default
      assert current(:single, "tenant_globex_production") == Default
      assert current(:none, nil) == Default
    end

    test "with nothing configured it is :legacy in every mode" do
      assert current(:multi, "tenant_acme_production") == :legacy
      assert current(:single, "tenant_acme_production") == :legacy
      assert current(:none, nil) == :legacy
    end

    test "in :none the registry is never read: no prefix names a site" do
      put_test_env(:site_frontends, %{"acme" => Acme})

      assert current(:none, "tenant_acme_production") == :legacy
    end
  end

  describe "page_html/0" do
    test "is the frontend's PageHTML, nil for a site without one, and the legacy chain with nothing configured" do
      put_test_env(:site_frontends, %{"acme" => Acme})

      current(:multi, "tenant_acme_production")
      assert Frontend.page_html() == AcmePageHTML

      current(:multi, "tenant_globex_production")
      assert Frontend.page_html() == nil

      put_test_env(:site_frontends, nil)
      put_test_env(:page_html_module, NextPageHTML)
      assert Frontend.page_html() == NextPageHTML

      put_test_env(:page_html_module, nil)
      assert Frontend.page_html() == BrandoIntegrationWeb.PageHTML
    end
  end

  describe "root_layout/1" do
    test "is the frontend's root layout, nil for a site without one, and the default with nothing configured" do
      default = {BrandoIntegrationWeb.Layouts, :app}
      put_test_env(:site_frontends, %{"acme" => Acme})

      current(:multi, "tenant_acme_production")
      assert Frontend.root_layout(default) == {AcmeLayouts, :root}

      current(:multi, "tenant_globex_production")
      assert Frontend.root_layout(default) == nil

      put_test_env(:site_frontends, nil)
      assert Frontend.root_layout(default) == default
    end
  end

  describe "Brando.Pages.list_templates/0" do
    test "lists the templates of the site whose prefix the process holds" do
      put_test_env(:site_frontends, %{"acme" => Acme, {"acme", "staging"} => AcmeNext})

      current(:multi, "tenant_acme_production")
      assert {:ok, templates} = Brando.Pages.list_templates()
      assert Enum.sort(templates) == ["default.html", "home.html"]

      current(:multi, "tenant_acme_staging")
      assert Brando.Pages.list_templates() == {:ok, ["landing.html"]}

      current(:multi, "tenant_globex_production")
      assert Brando.Pages.list_templates() == {:ok, []}
    end
  end

  describe "put_page_assigns/2" do
    test "merges the frontend's page assigns, and leaves the conn alone with nothing configured" do
      conn = Plug.Conn.assign(Plug.Test.conn(:get, "/"), :language, "en")
      page = %Brando.Pages.Page{title: "About"}

      assert Frontend.put_page_assigns(conn, page) == conn

      put_test_env(:site_frontends, %{"acme" => Acme})
      current(:multi, "tenant_acme_production")
      assert Frontend.put_page_assigns(conn, page).assigns.footer_color == "About:en"
    end
  end

  describe "Brando.Tenant.validate_config!/0" do
    test "accepts site keys, {site_key, environment_key} tuples and loadable frontend modules" do
      put_test_env(:site_frontends, %{"acme" => Acme, {"acme", "staging"} => AcmeNext})
      put_test_env(:default_site_frontend, Default)

      assert Tenant.validate_config!() == :ok
    end

    test "fails for a registry that is not a map" do
      put_test_env(:site_frontends, [{"acme", Acme}])

      assert_raise ConfigError, ~r/Invalid :site_frontends configuration/, &Tenant.validate_config!/0
    end

    test "fails for each key that is neither a site key nor a {site_key, environment_key} tuple" do
      for key <- ["Acme", "acme_corp", :acme, {"acme"}, {"acme", "Staging"}, {"acme", "staging", "x"}, {:acme, "staging"}] do
        put_test_env(:site_frontends, %{key => Acme})

        assert_raise ConfigError, ~r/Invalid :site_frontends key/, &Tenant.validate_config!/0
      end
    end

    test "fails for a registered module that does not load or lacks the callbacks" do
      put_test_env(:site_frontends, %{"acme" => MyAppWeb.Sites.Missing})
      assert_raise ConfigError, ~r/is not a module that loads/, &Tenant.validate_config!/0

      put_test_env(:site_frontends, %{"acme" => "MyAppWeb.Sites.Acme"})
      assert_raise ConfigError, ~r/is not a module that loads/, &Tenant.validate_config!/0

      put_test_env(:site_frontends, %{"acme" => NoCallbacks})
      assert_raise ConfigError, ~r/must define root_layout\/0 and page_html\/0/, &Tenant.validate_config!/0
    end

    test "fails for a default frontend that does not load or lacks the callbacks" do
      put_test_env(:default_site_frontend, MyAppWeb.CMS.Missing)
      assert_raise ConfigError, ~r/:default_site_frontend: .* is not a module that loads/, &Tenant.validate_config!/0

      put_test_env(:default_site_frontend, NoCallbacks)
      assert_raise ConfigError, ~r/:default_site_frontend: .* must define/, &Tenant.validate_config!/0
    end
  end

  test "environment_key_of/1 is the counterpart of site_key_of/1" do
    assert Tenant.environment_key_of("tenant_acme-corp_spring-redesign") == "spring-redesign"
    assert Tenant.site_key_of("tenant_acme-corp_spring-redesign") == "acme-corp"
    assert Tenant.environment_key_of("tenant_acme") == nil
    assert Tenant.environment_key_of(nil) == nil
  end
end
