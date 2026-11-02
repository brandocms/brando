defmodule Brando.TenantEnvironmentDomainTest do
  # Audit F02: binding a host to an environment is the installation's decision,
  # in every path that writes one, and the installation's own hosts are refused.
  use Brando.ConnCase, async: false

  alias Brando.Authorization.Migration
  alias Brando.Environments
  alias Brando.Environments.Environment
  alias Brando.Factory
  alias Brando.Tenant.Cache
  alias Brando.Tenant.InstallationHosts
  alias Brando.Tenant.Registry

  defmodule NotStartedEndpoint do
    def url, do: raise(ArgumentError, "not started")
  end

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  defmodule SchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix), do: Brando.Environments.Schema.create(target_prefix)
  end

  defmodule StructureCloner do
    @behaviour Brando.Environments.StructureCloner

    @impl true
    def clone_structure(_source_prefix, _target_prefix), do: :ok
  end

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, StructureCloner)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    Cache.clear()
    on_exit(&Cache.clear/0)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme-domain",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, environment} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
    %{site: site, environment: environment}
  end

  defp put_domain(environment, domain), do: Registry.update_environment(environment, %{domain: domain}, actor: :system)

  describe "who may bind" do
    test "no actor is refused, on update and on create", %{site: site, environment: environment} do
      assert {:error, changeset} = Registry.update_environment(environment, %{domain: "www.acme.test"})
      assert changeset.errors[:domain]

      assert {:error, changeset} =
               Registry.create_environment(site, %{name: "Staging", key: "staging", domain: "staging.acme.test"})

      assert changeset.errors[:domain]
      refute Cache.get_env_by_domain("www.acme.test")
      refute Cache.get_env_by_domain("staging.acme.test")
    end

    test "Environments.create_environment takes the creator as the actor", %{site: site} do
      admin = Factory.insert(:random_user, role: :editor)
      {:ok, _} = Brando.Tenant.Access.grant(admin, site, :admin)
      attrs = %{name: "Staging", key: "staging", domain: "staging.acme.test"}

      assert {:error, %Ecto.Changeset{}} = Environments.create_environment(site, attrs, creator: admin)
      refute Registry.get_environment_by_key(site, "staging")

      superuser = Factory.insert(:random_user, role: :superuser)
      assert {:ok, %{domain: "staging.acme.test"}} = Environments.create_environment(site, attrs, creator: superuser)
    end

    test "in legacy mode, the role as stored decides", %{environment: environment} do
      stale = Factory.insert(:random_user, role: :editor)

      assert {:error, _changeset} =
               Registry.update_environment(environment, %{domain: "www.acme.test"}, actor: %{stale | role: :superuser})

      for role <- [:user, :editor, :admin] do
        assert {:error, _changeset} =
                 Registry.update_environment(environment, %{domain: "www.acme.test"},
                   actor: Factory.insert(:random_user, role: role)
                 )
      end

      assert {:ok, %{domain: "www.acme.test"}} =
               Registry.update_environment(environment, %{domain: "www.acme.test"},
                 actor: Factory.insert(:random_user, role: :superuser)
               )
    end

    test "in groups mode, the Superuser group decides", %{environment: environment} do
      put_test_env(:authorization_mode, :groups)
      owner = Factory.insert(:random_user, role: :superuser)
      {:ok, _} = Migration.run()

      assert {:error, _changeset} =
               Registry.update_environment(environment, %{domain: "www.acme.test"},
                 actor: Factory.insert(:random_user, role: :editor)
               )

      assert {:ok, %{domain: "www.acme.test"}} =
               Registry.update_environment(environment, %{domain: "www.acme.test"}, actor: owner)
    end

    test "what does not change the host needs no authority", %{environment: environment} do
      {:ok, environment} = put_domain(environment, "www.acme.test")

      assert {:ok, %{name: "Renamed"}} = Registry.update_environment(environment, %{name: "Renamed"})
      assert {:ok, %{domain: "www.acme.test"}} = Registry.update_environment(environment, %{domain: "WWW.Acme.test "})
    end
  end

  describe "the installation's own hosts" do
    test "the endpoint's host is refused, however it is written", %{environment: environment} do
      host = URI.parse(Brando.endpoint().url()).host

      for spelling <- [host, String.upcase(host), " #{host} "] do
        assert {:error, changeset} = put_domain(environment, spelling)
        assert changeset.errors[:domain], inspect(spelling)
      end

      assert {:ok, _environment} = put_domain(environment, "sub.#{host}")
    end

    test "the media host and the CDN hosts are refused", %{environment: environment} do
      original = Application.get_env(:brando, :media_url)
      Application.put_env(:brando, :media_url, "https://Media.Example.com/media")
      on_exit(fn -> Application.put_env(:brando, :media_url, original) end)

      original_files = Application.get_env(:brando, Brando.Files)

      Application.put_env(:brando, Brando.Files,
        cdn: %Brando.CDN.Config{enabled: true, media_url: "https://cdn.example.com", s3: :default}
      )

      on_exit(fn ->
        if original_files,
          do: Application.put_env(:brando, Brando.Files, original_files),
          else: Application.delete_env(:brando, Brando.Files)
      end)

      assert "media.example.com" in InstallationHosts.list()

      for host <- ["media.example.com", "cdn.example.com"] do
        assert {:error, changeset} = put_domain(environment, host)
        assert changeset.errors[:domain], host
      end
    end

    test "a media host written without a scheme is refused", %{environment: environment} do
      original = Application.get_env(:brando, :media_url)
      Application.put_env(:brando, :media_url, "media.example.com")
      on_exit(fn -> Application.put_env(:brando, :media_url, original) end)

      assert {:error, changeset} = put_domain(environment, "media.example.com")
      assert changeset.errors[:domain]
    end

    test "an endpoint that has not started still reserves its configured host", %{environment: environment} do
      otp_app = Brando.config(:otp_app)
      put_test_env(:endpoint_module, NotStartedEndpoint)
      Application.put_env(otp_app, NotStartedEndpoint, url: [host: "cms.configured.test"])
      on_exit(fn -> Application.delete_env(otp_app, NotStartedEndpoint) end)

      assert {:error, changeset} = put_domain(environment, "cms.configured.test")
      assert changeset.errors[:domain]
    end

    test "a host bound before that was refused keeps working", %{environment: environment} do
      host = URI.parse(Brando.endpoint().url()).host

      Brando.Repo.update_all(
        from(e in Environment, where: e.id == ^environment.id),
        [set: [domain: host]],
        prefix: "public"
      )

      environment = Registry.get_environment(environment.id)
      Cache.invalidate()

      assert {:ok, %{name: "Renamed", domain: ^host}} = Registry.update_environment(environment, %{name: "Renamed"})
      assert {_site, %Environment{}} = Cache.get_env_by_domain(host)
    end
  end

  describe "a site's own domain flow" do
    test "a host moves between environments, and survives going live", %{site: site, environment: production} do
      {:ok, production} = put_domain(production, "www.acme.test")

      {:ok, staging} =
        Environments.create_environment(site, %{name: "Staging", key: "staging", domain: "staging.acme.test"},
          creator: :system
        )

      assert {:error, changeset} = put_domain(staging, "www.acme.test")
      assert changeset.errors[:domain]

      assert {:ok, staging} = Environments.set_live(staging, creator: :system)
      assert staging.domain == "staging.acme.test"
      # The binding stays on its environment when the live pointer moves
      assert {_site, %Environment{key: "production"}} = Cache.get_env_by_domain("www.acme.test")
      assert {_site, %Environment{key: "staging"}} = Cache.get_env_by_domain("staging.acme.test")

      {:ok, _production} = put_domain(production, nil)
      {:ok, _staging} = put_domain(staging, "www.acme.test")
      assert {_site, %Environment{key: "staging"}} = Cache.get_env_by_domain("www.acme.test")
    end

    test "a host one site released can be taken only by the installation", %{site: site, environment: environment} do
      {:ok, environment} = put_domain(environment, "www.acme.test")
      {:ok, _released} = put_domain(environment, nil)

      assert {:error, _changeset} =
               Registry.create_environment(site, %{name: "Other", key: "other", domain: "www.acme.test"},
                 actor: Factory.insert(:random_user, role: :editor)
               )

      refute Cache.get_env_by_domain("www.acme.test")
    end
  end
end
