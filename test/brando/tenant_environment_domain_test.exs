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
    test "a host moves between environments by a superuser", %{site: site, environment: production} do
      {:ok, production} = put_domain(production, "www.acme.test")

      {:ok, staging} =
        Environments.create_environment(site, %{name: "Staging", key: "staging", domain: "staging.acme.test"},
          creator: :system
        )

      assert {:error, changeset} = put_domain(staging, "www.acme.test")
      assert changeset.errors[:domain]

      {:ok, _production} = put_domain(production, nil)
      {:ok, _staging} = put_domain(staging, "www.acme.test")
      assert {_site, %Environment{key: "staging"}} = Cache.get_env_by_domain("www.acme.test")
    end

    test "in a transaction, the routing cache takes a host once it commits", %{environment: environment} do
      {:ok, _} =
        Brando.Repo.transaction(fn ->
          {:ok, _environment} = put_domain(environment, "www.acme.test")
          refute Cache.get_env_by_domain("www.acme.test")
        end)

      assert {_site, %Environment{key: "production"}} = Cache.get_env_by_domain("www.acme.test")
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

  # Set-live carries the site's host: the outgoing live environment's domain
  # moves to the one going live, in exchange for its own.
  describe "the host follows the live environment" do
    setup %{site: site} do
      {:ok, staging} = Registry.create_environment(site, %{name: "Staging", key: "staging"})
      %{staging: staging}
    end

    defp domains(site), do: Map.new(Registry.list_environments(site), &{&1.key, &1.domain})

    defp answering(host) do
      case Cache.get_env_by_domain(host) do
        {_site, %Environment{key: key}} -> key
        nil -> nil
      end
    end

    defp site_admin(site) do
      admin = Factory.insert(:random_user, role: :editor)
      {:ok, _} = Brando.Tenant.Access.grant(admin, site, :admin)
      admin
    end

    defp group_admin(site, production) do
      owner = Factory.insert(:random_user, role: :superuser)
      {:ok, _} = Migration.run()
      admin = Factory.insert(:random_user, role: :editor)
      owner_scope = Brando.Authorization.Scope.site(owner, site, production)

      {:ok, group} =
        Brando.Authorization.Groups.create(owner_scope, %{name: "Site admins"}, [
          "brando.admin.access",
          "brando.environments.read",
          "brando.environments.create",
          "brando.environments.update",
          "brando.environments.promote"
        ])

      {:ok, :ok} = Brando.Authorization.Groups.add_member(owner_scope, group.id, admin.id)
      admin
    end

    test "the live host moves to the environment going live", %{site: site, environment: production, staging: staging} do
      {:ok, _production} = put_domain(production, "www.acme.test")

      assert {:ok, %Environment{live: true, domain: "www.acme.test"}} = Environments.set_live(staging, creator: :system)

      assert domains(site) == %{"production" => nil, "staging" => "www.acme.test"}
      # The next request on the host resolves to the new live environment
      assert answering("www.acme.test") == "staging"
      assert {_site, %Environment{key: "staging"}} = Brando.Tenant.Frontend.resolve("www.acme.test")
      assert [%{operation: :set_live}] = Enum.filter(Environments.list_operation_logs(site), &(&1.operation == :set_live))
    end

    test "an environment with its own host swaps it for the live one, and back", %{
      site: site,
      environment: production,
      staging: staging
    } do
      {:ok, production} = put_domain(production, "www.acme.test")
      {:ok, staging} = put_domain(staging, "staging.acme.test")

      assert {:ok, %Environment{domain: "www.acme.test"}} = Environments.set_live(staging, creator: :system)
      assert domains(site) == %{"production" => "staging.acme.test", "staging" => "www.acme.test"}
      assert answering("www.acme.test") == "staging"
      assert answering("staging.acme.test") == "production"

      assert {:ok, %Environment{domain: "www.acme.test"}} = Environments.set_live(production, creator: :system)
      assert domains(site) == %{"production" => "www.acme.test", "staging" => "staging.acme.test"}
      assert answering("www.acme.test") == "production"
      assert answering("staging.acme.test") == "staging"
      assert Cache.get_live_env(site.key).key == "production"
    end

    test "a restored archive set live takes the host the same way", %{
      site: site,
      environment: production,
      staging: staging
    } do
      {:ok, _production} = put_domain(production, "www.acme.test")
      {:ok, _staging} = Environments.set_live(staging, creator: :system)

      assert {:ok, %Environment{live: false, domain: nil} = restored} = Environments.rollback(site, creator: :system)
      assert answering("www.acme.test") == "staging"

      assert {:ok, %Environment{domain: "www.acme.test"}} = Environments.set_live(restored, creator: :system)
      assert answering("www.acme.test") == restored.key
      assert Registry.get_environment(staging.id).domain == nil
    end

    test "with no domain on either, none appears", %{site: site, staging: staging} do
      assert {:ok, %Environment{domain: nil}} = Environments.set_live(staging, creator: :system)
      assert domains(site) == %{"production" => nil, "staging" => nil}
      assert Cache.get_live_env(site.key).key == "staging"
    end

    test "the domains swap, a missing one too, so a round trip puts them back", %{
      site: site,
      environment: production,
      staging: staging
    } do
      {:ok, staging} = put_domain(staging, "staging.acme.test")

      assert {:ok, %Environment{domain: nil}} = Environments.set_live(staging, creator: :system)
      assert domains(site) == %{"production" => "staging.acme.test", "staging" => nil}
      assert answering("staging.acme.test") == "production"

      assert {:ok, %Environment{domain: nil}} = Environments.set_live(production, creator: :system)
      assert domains(site) == %{"production" => nil, "staging" => "staging.acme.test"}
      assert answering("staging.acme.test") == "staging"
    end

    # On static delivery the deployed build decides what a host serves, and its
    # forms post to the environment the build was made from
    test "on a statically delivered site, the hosts stay where they are", %{
      site: site,
      environment: production,
      staging: staging
    } do
      {:ok, _site} = Registry.update_site(site, %{delivery_mode: :static})
      {:ok, _production} = put_domain(production, "www.acme.test")
      {:ok, staging} = put_domain(staging, "staging.acme.test")

      assert {:ok, %Environment{live: true, domain: "staging.acme.test"}} =
               Environments.set_live(staging, creator: :system)

      assert domains(site) == %{"production" => "www.acme.test", "staging" => "staging.acme.test"}
      assert answering("www.acme.test") == "production"
      assert Cache.get_live_env(site.key).key == "staging"
    end

    test "another site's host stays where it is", %{site: site, environment: production, staging: staging} do
      {:ok, _production} = put_domain(production, "www.acme.test")

      {:ok, other_site} =
        Registry.create_site(%{
          name: "Other",
          key: "other-domain",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, other} =
        Registry.create_environment(
          other_site,
          %{name: "Production", key: "production", live: true, domain: "www.other.test"},
          actor: :system
        )

      {:ok, _staging} = Environments.set_live(staging, creator: :system)

      assert domains(site) == %{"production" => nil, "staging" => "www.acme.test"}
      assert Registry.get_environment(other.id).domain == "www.other.test"
      assert answering("www.other.test") == "production"
    end

    test "the host a superuser just moved is the one carried", %{site: site, environment: production, staging: staging} do
      {:ok, _production} = put_domain(production, "www.acme.test")
      # The caller's structs are stale: the registry's rows decide
      {:ok, _moved} = put_domain(Registry.get_environment(production.id), "moved.acme.test")

      assert {:ok, %Environment{domain: "moved.acme.test"}} =
               Environments.set_live(%{staging | domain: "forged.acme.test"}, creator: :system)

      assert domains(site) == %{"production" => nil, "staging" => "moved.acme.test"}
      refute answering("forged.acme.test")
    end

    test "a per-site admin carries the host in legacy mode", %{site: site, environment: production, staging: staging} do
      {:ok, _production} = put_domain(production, "www.acme.test")
      admin = site_admin(site)

      assert {:ok, %Environment{domain: "www.acme.test"}} = Environments.set_live(staging, creator: admin)
      assert answering("www.acme.test") == "staging"

      assert {:ok, %Environment{domain: "www.acme.test"}} = Environments.set_live(production, creator: admin)
      assert domains(site) == %{"production" => "www.acme.test", "staging" => nil}
    end

    test "a site admin carries the host in groups mode", %{site: site, environment: production, staging: staging} do
      put_test_env(:authorization_mode, :groups)
      {:ok, _production} = put_domain(production, "www.acme.test")
      {:ok, _staging} = put_domain(staging, "staging.acme.test")
      admin = group_admin(site, production)

      assert {:ok, %Environment{domain: "www.acme.test"}} = Environments.set_live(staging, creator: admin)
      assert domains(site) == %{"production" => "staging.acme.test", "staging" => "www.acme.test"}
      assert answering("www.acme.test") == "staging"
    end

    test "a scheduled live switch carries the host", %{site: site, environment: production, staging: staging} do
      {:ok, _production} = put_domain(production, "www.acme.test")
      admin = site_admin(site)

      assert :ok =
               perform_job(Brando.Worker.EnvironmentSetLive, %{
                 "site_id" => site.id,
                 "environment_id" => staging.id,
                 "creator_id" => admin.id
               })

      assert answering("www.acme.test") == "staging"
    end

    test "a site admin who may not promote moves no host", %{site: site, environment: production, staging: staging} do
      {:ok, _production} = put_domain(production, "www.acme.test")
      editor = Factory.insert(:random_user, role: :editor)
      {:ok, _} = Brando.Tenant.Access.grant(editor, site, :editor)

      assert {:error, :forbidden} = Environments.set_live(staging, creator: editor)
      assert domains(site) == %{"production" => "www.acme.test", "staging" => nil}
    end

    for mode <- [:legacy, :groups] do
      test "a per-site admin still binds no new host, on any path, #{mode} mode", %{
        site: site,
        environment: production,
        staging: staging
      } do
        put_test_env(:authorization_mode, unquote(mode))
        {:ok, _production} = put_domain(production, "www.acme.test")
        admin = if unquote(mode) == :groups, do: group_admin(site, production), else: site_admin(site)

        assert {:error, _} = Registry.update_environment(staging, %{domain: "new.acme.test"}, actor: admin)
        assert {:error, _} = Registry.update_environment(staging, %{domain: "www.other.test"}, actor: admin)

        assert {:error, _} =
                 Registry.create_environment(site, %{name: "New", key: "new", domain: "new.acme.test"}, actor: admin)

        assert {:error, %Ecto.Changeset{}} =
                 Environments.create_environment(site, %{name: "New", key: "new", domain: "new.acme.test"},
                   creator: admin
                 )

        # Set-live reads no host from its argument: only the site's own moves
        assert {:ok, _staging} = Environments.set_live(%{staging | domain: "new.acme.test"}, creator: admin)
        assert domains(site) == %{"production" => nil, "staging" => "www.acme.test"}

        # Nor can a host be pulled from another site by going live there
        {:ok, other_site} =
          Registry.create_site(%{
            name: "Other",
            key: "other-domain-#{unquote(mode)}",
            languages: ["en"],
            default_language: "en",
            status: :active,
            delivery_mode: :dynamic
          })

        {:ok, other} =
          Registry.create_environment(
            other_site,
            %{name: "Production", key: "production", live: true, domain: "www.other.test"},
            actor: :system
          )

        {:ok, other_staging} = Registry.create_environment(other_site, %{name: "Staging", key: "staging"})
        assert {:error, :forbidden} = Environments.set_live(other_staging, creator: admin)
        assert Registry.get_environment(other.id).domain == "www.other.test"

        for host <- ["new.acme.test", "www.other.test"] do
          refute match?({%{id: id}, _} when id == site.id, Cache.get_env_by_domain(host)), host
        end
      end
    end
  end

  # The call is authorized for the site the struct names; the registry's row
  # decides which site it acts on, so the two must agree.
  describe "an environment whose site_id names another site" do
    setup do
      {:ok, other_site} =
        Registry.create_site(%{
          name: "Other",
          key: "other-forged",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, other_production} =
        Environments.create_environment(
          other_site,
          %{name: "Production", key: "production", live: true, domain: "www.other.test"},
          creator: :system
        )

      {:ok, other_staging} =
        Environments.create_environment(
          other_site,
          %{name: "Staging", key: "staging", domain: "staging.other.test"},
          creator: :system
        )

      %{other_site: other_site, other_production: other_production, other_staging: other_staging}
    end

    defp other_state(other_site) do
      Map.new(Registry.list_environments(other_site), &{&1.key, {&1.live, &1.domain}})
    end

    defp other_untouched(other_site) do
      assert other_state(other_site) == %{
               "production" => {true, "www.other.test"},
               "staging" => {false, "staging.other.test"}
             }

      assert Environments.list_operation_logs(other_site) |> Enum.map(& &1.operation) |> Enum.sort() == [
               :create,
               :create
             ]
    end

    for mode <- [:legacy, :groups] do
      test "set_live refuses it, #{mode} mode", %{
        site: site,
        environment: production,
        other_site: other_site,
        other_staging: other_staging
      } do
        put_test_env(:authorization_mode, unquote(mode))
        admin = if unquote(mode) == :groups, do: group_admin(site, production), else: site_admin(site)

        assert {:error, :environment_not_found} =
                 Environments.set_live(%{other_staging | site_id: site.id}, creator: admin)

        other_untouched(other_site)
        assert answering("www.other.test") == "production"
      end
    end

    test "copy refuses it", %{
      site: site,
      other_site: other_site,
      other_production: other_production,
      other_staging: other_staging
    } do
      admin = site_admin(site)

      assert {:error, :site_or_environment_not_found} =
               Environments.copy_environment(
                 %{other_production | site_id: site.id},
                 %{other_staging | site_id: site.id},
                 creator: admin
               )

      other_untouched(other_site)
    end

    test "delete refuses it", %{site: site, other_site: other_site, other_staging: other_staging} do
      admin = site_admin(site)

      assert {:error, :site_or_environment_not_found} =
               Environments.delete_environment(%{other_staging | site_id: site.id}, creator: admin)

      other_untouched(other_site)
      assert Brando.Environments.Schema.exists?(Brando.Tenant.prefix(other_site, other_staging))
    end
  end
end
