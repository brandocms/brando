# What the generated `CMS.PageController` reads for `/`: the published
# homepage and the partials, from the environment the host resolves to
defmodule Brando.Tenant.SeederTest.PageController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    with {:ok, page} <- Brando.Pages.get_page(%{matches: %{uri: "index", language: "en"}, status: :published}),
         {:ok, %{"footer" => _footer}} <- Brando.Pages.get_fragments(%{filter: %{parent_key: "partials", language: "en"}}) do
      send_resp(conn, 200, page.rendered_blocks)
    else
      _not_found -> send_resp(conn, 404, "")
    end
  end
end

defmodule Brando.Tenant.SeederTest.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug Brando.Plug.Tenant
  end

  scope "/" do
    pipe_through :browser
    get "/", Brando.Tenant.SeederTest.PageController, :index
  end
end

defmodule Brando.Tenant.SeederTest do
  # Provisions sites with the default seeder, as `/admin/sites` does, and
  # requests their homepages on their hosts
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Authorization.Scope
  alias Brando.Content
  alias Brando.Environments.Schema
  alias Brando.Navigation
  alias Brando.Pages
  alias Brando.Sites.Identity
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup

  @seeded_modules ~w(hero steps cards tips terminal closing footer)

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  # A seeder that adds to the default one, and then fails
  defmodule FailingAfterDefault do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(site, environment, creator) do
      :ok = Brando.Tenant.Seeder.seed(site, environment, creator)
      {:error, :seed_failed}
    end
  end

  defmodule ScopeReporter do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(_site, _environment, _creator) do
      send(self(), {:seeded_in_scope, Brando.Authorization.Boundary.current_scope()})
      :ok
    end
  end

  # The default seeder, failing on a language it cannot seed
  defmodule FailingDefault do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(site, environment, creator),
      do: Brando.Tenant.Seeder.seed(%{site | languages: site.languages ++ ["unsupported"]}, environment, creator)
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-tenant-seeder-#{System.unique_integer([:positive])}")

    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    # The seeds fill the site caches from rows this test's sandbox rolls back
    cached = Map.new(~w(identity seo navigation)a, &{&1, Brando.Cache.get(&1)})

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()

      Enum.each(cached, fn
        {key, nil} -> Brando.Cache.del(key)
        {key, value} -> Brando.Cache.put(key, value, :infinite)
      end)
    end)

    %{creator: Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)}
  end

  for mode <- [:multi, :single] do
    describe "with tenancy_mode #{inspect(mode)}, a site provisioned with the default seeder" do
      setup do
        put_test_env(:tenancy_mode, unquote(mode))
        put_test_env(:site_key, "acme")
        :ok
      end

      test "answers on its production and staging hosts", %{creator: creator} do
        public_modules = public_count(Content.Module)

        assert {:ok, site} = Setup.create_site(site_attrs(["en", "no"]), creator, environments: environments())

        for environment <- ~w(production staging) do
          in_environment(environment, fn ->
            assert Brando.Repo.get_by(Navigation.Menu, key: "main", language: :en)
            assert Brando.Repo.get_by(Navigation.Menu, key: "main", language: :no)
            assert Brando.Repo.get_by(Pages.Page, uri: "index", language: :no, is_homepage: true)
            assert Brando.Repo.get_by(Pages.Fragment, parent_key: "partials", key: "footer", language: :en)

            for uid <- @seeded_modules, do: assert(Brando.Repo.get_by(Content.Module, uid: "brando-default-#{uid}"))

            # The identity is named after the site
            assert Brando.Repo.get_by!(Identity, language: :en).name == "Acme"

            assert Content.Blocks.count_stale_blocks_by_module() == []
          end)
        end

        assert public_count(Content.Module) == public_modules

        for host <- ["acme.test", "staging.acme.test"] do
          conn = request("/", host)
          assert conn.status == 200, host
          assert conn.resp_body =~ ~s(b-tpl="hero"), host
        end

        assert site.key == "acme"
      end
    end
  end

  describe "provisioning seeds as the system" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      on_exit(fn -> Boundary.put_scope(nil) end)
      :ok
    end

    # `/admin/sites` runs under the installation scope of the user creating the
    # site, which grants no content in a site
    test "a site created under the creator's installation scope", %{creator: creator} do
      Boundary.put_scope(Scope.installation(creator))

      assert {:ok, _site} = Setup.create_site(site_attrs(["en"]), creator, environments: environments())
      assert_seeded_by(creator)
    end

    # A suspended site admits no one, its creator included
    test "a site created suspended", %{creator: creator} do
      attrs = Map.put(site_attrs(["en"]), :status, :suspended)

      assert {:ok, site} = Setup.create_site(attrs, creator, environments: environments())
      assert site.status == :suspended
      assert_seeded_by(creator)
    end

    test "an application's own seeder runs with no process scope", %{creator: creator} do
      put_test_env(:tenant_seeder, ScopeReporter)
      Boundary.put_scope(Scope.installation(creator))

      assert {:ok, _site} = Setup.create_site(site_attrs(["en"]), creator, environments: environments())
      assert_received {:seeded_in_scope, nil}
      assert Boundary.current_scope() == Scope.installation(creator)
    end
  end

  describe "a seeder that fails" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      :ok
    end

    test "after the default content leaves no site, schema, folder or job behind", %{creator: creator} do
      put_test_env(:tenant_seeder, FailingAfterDefault)

      jobs =
        Oban.Testing.with_testing_mode(:manual, fn ->
          assert {:error, {:site_setup_failed, :seed_failed, :ok}} =
                   Setup.create_site(site_attrs(["en"]), creator, environments: environments())

          Brando.Repo.all(
            from(job in Oban.Job, where: fragment("?->>'tenant_prefix'", job.args) == "tenant_acme_production"),
            prefix: "public"
          )
        end)

      assert_left_nothing()

      # The seeded menu queued its render cascade, which is cancelled with the site
      assert jobs != []
      assert Enum.all?(jobs, &(&1.state == "cancelled"))
    end

    test "in the default content leaves no site, schema or folder behind", %{creator: creator} do
      put_test_env(:tenant_seeder, FailingDefault)

      assert {:error, {:site_setup_failed, %Ecto.ChangeError{}, :ok}} =
               Setup.create_site(site_attrs(["en"]), creator, environments: environments())

      assert_left_nothing()
    end
  end

  defp assert_seeded_by(creator) do
    in_environment("production", fn ->
      assert Brando.Repo.get_by!(Navigation.Menu, key: "main", language: :en).creator_id == creator.id
      assert Brando.Repo.get_by!(Pages.Page, uri: "index", language: :en).creator_id == creator.id
    end)
  end

  defp assert_left_nothing do
    refute Registry.get_site_by_key("acme")
    refute Schema.exists?("tenant_acme_production")
    refute Schema.exists?("tenant_acme_staging")
    refute File.exists?(Path.join(Brando.config(:media_path), "acme"))
    refute File.exists?(Path.join(Brando.config(:sites_path), "acme"))
  end

  defp in_environment(key, fun), do: Tenant.with_prefix(Tenant.prefix("acme", key), fun)

  defp public_count(schema), do: Tenant.with_public(fn -> Brando.Repo.aggregate(schema, :count) end)

  defp request(path, host) do
    Tenant.put_prefix(nil)

    :get
    |> Plug.Test.conn("https://#{host}#{path}")
    |> Map.put(:host, host)
    |> Brando.Tenant.SeederTest.Router.call(Brando.Tenant.SeederTest.Router.init([]))
  after
    Tenant.put_prefix(nil)
  end

  defp environments do
    [
      %{name: "Production", key: "production", live: true, domain: "acme.test"},
      %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"}
    ]
  end

  defp site_attrs(languages) do
    %{
      name: "Acme",
      key: "acme",
      languages: languages,
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    }
  end
end
