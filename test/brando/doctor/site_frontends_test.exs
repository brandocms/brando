defmodule Brando.Doctor.SiteFrontendsTest do
  # Not async: it sets the tenancy configuration and :site_frontends.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Doctor.Checks
  alias Brando.Doctor.Context
  alias Brando.Doctor.Result
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  defmodule Layouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns), do: ~H"{@inner_content}"
  end

  defmodule AcmePageHTML do
    @moduledoc false
    use Phoenix.Component

    def index(assigns), do: ~H"<main>index</main>"
    def default(assigns), do: ~H"<main>default</main>"
  end

  defmodule GlobexPageHTML do
    @moduledoc false
    use Phoenix.Component

    def index(assigns), do: ~H"<main>index</main>"
  end

  defmodule Acme do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {Layouts, :root}, page_html: AcmePageHTML
  end

  defmodule Globex do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {Layouts, :root}, page_html: GlobexPageHTML
  end

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:site_frontends, nil)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)

    user = Brando.Factory.insert(:random_user)

    for {key, environments} <- [{"acme", ["production", "staging"]}, {"globex", ["production"]}] do
      {:ok, site} =
        Registry.create_site(%{
          name: key,
          key: key,
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      for environment <- environments do
        {:ok, _} = Registry.create_environment(site, %{name: environment, key: environment}, actor: :system)
        prefix = "tenant_#{key}_#{environment}"
        Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)
        Repo.query!(~s|CREATE TABLE "#{prefix}".pages (LIKE public.pages INCLUDING ALL)|)
      end
    end

    %{user: user}
  end

  defp context, do: Context.new(locale: "en")

  defp page(prefix, template, user) do
    page = Brando.Factory.build(:page, template: template, creator: nil, creator_id: user.id)
    Tenant.with_prefix(prefix, fn -> Brando.Repo.insert!(page) end)
  end

  describe "Sites without a frontend" do
    test "is skipped outside :multi or with an empty registry" do
      assert %Result{status: :skipped} = Checks.SiteFrontends.run(context())

      put_test_env(:site_frontends, %{"acme" => Acme})
      put_test_env(:tenancy_mode, :single)
      assert %Result{status: :skipped} = Checks.SiteFrontends.run(context())
    end

    test "passes when every active site has an entry, its own or one per environment" do
      put_test_env(:site_frontends, %{"acme" => Acme, "globex" => Globex})
      assert %Result{status: :ok} = Checks.SiteFrontends.run(context())

      put_test_env(:site_frontends, %{{"acme", "production"} => Acme, {"acme", "staging"} => Acme, "globex" => Globex})
      assert %Result{status: :ok} = Checks.SiteFrontends.run(context())
    end

    test "warns for each active site or environment without an entry" do
      put_test_env(:site_frontends, %{{"acme", "production"} => Acme})
      result = Checks.SiteFrontends.run(context())
      assert result.status == :warning
      assert result.summary == "2 sites without a frontend: their pages answer 404 and cannot be previewed"
      assert result.items == ["acme/staging: no frontend", "globex: no frontend"]
      assert result.fix =~ "mix brando.gen.site --site KEY"
    end

    test "leaves out a site that is not active" do
      put_test_env(:site_frontends, %{"acme" => Acme})
      globex = Enum.find(Registry.list_sites(), &(&1.key == "globex"))
      {:ok, _} = Registry.update_site(globex, %{status: :suspended})
      Tenant.Cache.clear()

      assert %Result{status: :ok} = Checks.SiteFrontends.run(context())
    end

    test "warns for each entry that names no site or environment" do
      put_test_env(:site_frontends, %{
        "acme" => Acme,
        "globex" => Globex,
        "initech" => Acme,
        {"globex", "staging"} => Globex
      })

      result = Checks.SiteFrontends.run(context())
      assert result.status == :warning
      assert result.summary == "2 site_frontends entries name no site"
      assert Enum.sort(result.items) == ["globex/staging: names no site", "initech: names no site"]
    end

    test "in the admin, checks the site it runs in" do
      put_test_env(:site_frontends, %{"acme" => Acme})
      admin = Context.new(locale: "en", mode: :admin, prefix: "tenant_acme_production")
      assert %Result{status: :ok} = Checks.SiteFrontends.run(admin)

      admin = Context.new(locale: "en", mode: :admin, prefix: "tenant_globex_production")
      assert %Result{status: :warning, items: ["globex: no frontend"]} = Checks.SiteFrontends.run(admin)
    end
  end

  describe "Pages without their template" do
    test "is skipped outside :multi or with an empty registry" do
      assert %Result{status: :skipped} = Checks.PageTemplates.run(context())
    end

    test "passes when every page's template is in its site's PageHTML", %{user: user} do
      put_test_env(:site_frontends, %{"acme" => Acme, "globex" => Globex})
      page("tenant_acme_production", "default.html", user)
      page("tenant_globex_production", "index.html", user)

      assert %Result{status: :ok} = Checks.PageTemplates.run(context())
    end

    test "counts, per site and environment, the pages whose template the site's PageHTML lacks", %{user: user} do
      put_test_env(:site_frontends, %{"acme" => Acme, "globex" => Globex})
      page("tenant_acme_production", "default.html", user)
      page("tenant_acme_staging", "landing.html", user)
      # Globex's PageHTML has no default/1.
      for _ <- 1..2, do: page("tenant_globex_production", "default.html", user)
      page("tenant_globex_production", "landing.html", user)

      result = Checks.PageTemplates.run(context())
      assert result.status == :warning
      assert result.summary == "4 pages whose template their site's PageHTML lacks"

      assert result.items == [
               "[acme/staging] 1 page (landing.html)",
               "[globex/production] 3 pages (default.html, landing.html)"
             ]
    end

    test "leaves a site without a frontend to the other check", %{user: user} do
      put_test_env(:site_frontends, %{"acme" => Acme})
      page("tenant_globex_production", "landing.html", user)

      assert %Result{status: :ok} = Checks.PageTemplates.run(context())
    end
  end
end
