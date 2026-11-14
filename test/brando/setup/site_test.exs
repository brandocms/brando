# What the generated `CMS.PageController` reads for `/`: the published
# homepage, from the environment the host resolves to
defmodule Brando.Setup.SiteTest.PageController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    case Brando.Pages.get_page(%{matches: %{uri: "index", language: "en"}, status: :published}) do
      {:ok, page} -> send_resp(conn, 200, page.rendered_blocks)
      _not_found -> send_resp(conn, 404, "")
    end
  end
end

defmodule Brando.Setup.SiteTest.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug Brando.Plug.Tenant
  end

  scope "/" do
    pipe_through :browser
    get "/", Brando.Setup.SiteTest.PageController, :index
  end
end

defmodule Brando.Setup.SiteTest do
  # `mix brando.setup` provisions the one site of a `:single` installation
  use Brando.ConnCase, async: false

  alias Brando.Pages
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  import Brando.Test.Support, only: [put_test_env: 2]

  @prefixes ~w(tenant_acme_production tenant_acme_staging)

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-setup-site-#{System.unique_integer([:positive])}")

    put_test_env(:site_key, "acme")
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    cached = Map.new(~w(identity seo navigation)a, &{&1, Brando.Cache.get(&1)})

    on_exit(fn ->
      Mix.shell(shell)
      Mix.Task.reenable("brando.gen.seeds")
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
      Brando.TenantCaches.clear(@prefixes)

      Enum.each(cached, fn
        {key, nil} -> Brando.Cache.del(key)
        {key, value} -> Brando.Cache.put(key, value, :infinite)
      end)
    end)

    %{creator: Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)}
  end

  describe "with tenancy_mode :single, setup" do
    setup do
      put_test_env(:tenancy_mode, :single)
      :ok
    end

    test "provisions the configured site, whose homepage answers on the developer's host", %{creator: creator} do
      setup!()

      site = Registry.get_site_by_key("acme")
      assert site.name == "MyApp"
      assert site.status == :active
      assert site.languages == Enum.map(Brando.config(:languages), &to_string(&1[:value]))
      assert site.default_language == "en"

      assert Enum.map(site.environments, &{&1.key, &1.live, &1.domain}) |> Enum.sort() ==
               [{"production", true, nil}, {"staging", false, nil}]

      in_environment("production", fn ->
        assert Brando.Repo.get_by!(Pages.Page, uri: "index", language: :en).creator_id == creator.id
      end)

      output = shell_output()
      assert output =~ ~s(Created the site "acme")

      conn = request("/", "localhost")
      assert conn.status == 200
      assert conn.resp_body =~ ~s(b-tpl="hero")
    end

    test "is what brando.gen.seeds points to" do
      Mix.Task.reenable("brando.gen.seeds")
      Mix.Task.run("brando.gen.seeds", [])

      assert shell_output() =~ ~s(mix brando.setup creates the site\n"acme")
      assert Registry.list_sites() == []
    end

    test "leaves a site that exists alone, and says so" do
      setup!()
      _first = shell_output()
      before = snapshot()

      setup!()

      assert snapshot() == before
      assert shell_output() =~ ~s(The site "acme" exists)
    end

    test "fails with the reason when provisioning fails, and leaves no site" do
      put_test_env(:languages, [[value: "en", text: "English"]])
      put_test_env(:default_language, "fr")

      error = assert_raise Mix.Error, fn -> setup!() end
      assert error.message =~ "default_language"
      refute Registry.get_site_by_key("acme")
    end
  end

  test "with tenancy_mode :multi, setup provisions no site, and says where sites are created" do
    put_test_env(:tenancy_mode, :multi)

    setup!()

    assert Registry.list_sites() == []
    assert shell_output() =~ "/admin/sites"
  end

  test "outside :single, provisioning does nothing", %{creator: creator} do
    for mode <- [:none, :multi] do
      put_test_env(:tenancy_mode, mode)
      assert Brando.Setup.Site.provision(creator) == :not_single
    end

    assert Registry.list_sites() == []
  end

  defp setup!, do: Mix.Tasks.Brando.Setup.run(~w(--no-assets --no-db --no-account))

  defp snapshot do
    site = Registry.get_site_by_key("acme")

    counts =
      in_environment("production", fn ->
        Enum.map(
          [Pages.Page, Pages.Fragment, Brando.Navigation.Menu, Brando.Content.Module],
          &Brando.Repo.aggregate(&1, :count)
        )
      end)

    {site, counts}
  end

  defp shell_output(output \\ "") do
    receive do
      {:mix_shell, kind, [message]} when kind in [:info, :error] -> shell_output(output <> message)
    after
      0 -> output
    end
  end

  defp in_environment(key, fun), do: Tenant.with_prefix(Tenant.prefix("acme", key), fun)

  defp request(path, host) do
    Tenant.put_prefix(nil)

    :get
    |> Plug.Test.conn("http://#{host}#{path}")
    |> Map.put(:host, host)
    |> Brando.Setup.SiteTest.Router.call(Brando.Setup.SiteTest.Router.init([]))
  after
    Tenant.put_prefix(nil)
  end
end
