defmodule Brando.Tenant.SetupTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Schema
  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup
  alias Brando.Tenant.Storage

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(site, environment) do
      send(self(), {:migrated, site.key, environment.key})
      {:ok, [20_260_816_000_001]}
    end
  end

  defmodule SchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(source_prefix, target_prefix) do
      send(self(), {:cloned, source_prefix, target_prefix})
      Schema.create(target_prefix)
    end
  end

  defmodule StructureCloner do
    @behaviour Brando.Environments.StructureCloner

    @impl true
    def clone_structure(source_prefix, target_prefix) do
      send(self(), {:structure_cloned, source_prefix, target_prefix})
      :ok
    end
  end

  defmodule Seeder do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(site, environment, creator) do
      send(self(), {:seeded, site.key, environment.key, creator.id})
      :ok
    end
  end

  defmodule FailingSeeder do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(_site, _environment, _creator), do: {:error, :seed_failed}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-tenant-setup-#{System.unique_integer([:positive])}")
    media_path = Path.join(root, "media")
    sites_path = Path.join(root, "sites")

    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, StructureCloner)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    put_test_env(:tenant_seeder, Seeder)
    put_test_env(:media_path, media_path)
    put_test_env(:sites_path, sites_path)

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()
    end)

    creator = Brando.Factory.insert(:random_user, role: :admin)
    %{creator: creator, root: root}
  end

  test "creates, seeds, copies, and assigns a complete site", %{creator: creator} do
    assert {:ok, site} = Setup.create_site(site_attrs("provisioned-site"), creator)

    assert Enum.map(site.environments, &{&1.key, &1.live}) |> Enum.sort() ==
             [{"production", true}, {"staging", false}]

    assert_received {:migrated, "provisioned-site", "production"}
    assert_received {:migrated, "provisioned-site", "staging"}
    assert_received {:seeded, "provisioned-site", "production", creator_id}
    assert creator_id == creator.id
    assert_received {:cloned, "tenant_provisioned-site_production", "tenant_provisioned-site_staging"}

    assert Schema.exists?("tenant_provisioned-site_production")
    assert Schema.exists?("tenant_provisioned-site_staging")
    assert File.dir?(Storage.media_root(site))
    assert File.dir?(Storage.assets_root(site))
    assert Access.role_for(creator, site) == :admin
  end

  test "compensates all persisted resources when provisioning fails", %{creator: creator} do
    put_test_env(:tenant_seeder, FailingSeeder)

    assert {:error, {:site_setup_failed, :seed_failed, _compensation}} =
             Setup.create_site(site_attrs("broken-site"), creator)

    refute Registry.get_site_by_key("broken-site")
    refute Schema.exists?("tenant_broken-site_production")
    refute File.exists?(Path.join(Brando.config(:media_path), "broken-site"))
    refute File.exists?(Path.join(Brando.config(:sites_path), "broken-site"))
  end

  test "an installation provisioner receives access to the new site before environment setup", %{creator: creator} do
    put_test_env(:authorization_mode, :groups)
    owner = Brando.Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Brando.Authorization.Migration.run()
    scope = Brando.Authorization.Scope.installation(owner)

    {:ok, group} =
      Brando.Authorization.Groups.create(scope, %{name: "Site provisioners"}, [
        "brando.admin.access",
        "brando.sites.create"
      ])

    {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, creator.id)
    assert {:ok, site} = Setup.create_site(site_attrs("group-provisioned-site"), creator)
    assert length(site.environments) == 2
    refute Brando.Authorization.Engine.superuser?(Brando.Authorization.Scope.installation(creator))
    assert Brando.Authorization.can?(Brando.Authorization.Scope.site(creator, site), :create, :environments)

    assert Repo.exists?(
             from(e in Brando.Authorization.AuditEvent,
               where: e.site_id == ^site.id and e.action == "membership.provisioned"
             )
           )
  end

  test "never deletes storage that existed before provisioning", %{creator: creator} do
    existing_root = Path.join(Brando.config(:media_path), "existing-site")
    existing_file = Path.join(existing_root, "keep.txt")
    File.mkdir_p!(existing_root)
    File.write!(existing_file, "legacy")

    assert {:error, {:site_setup_failed, {:site_storage_already_exists, ^existing_root}, _compensation}} =
             Setup.create_site(site_attrs("existing-site"), creator)

    refute Registry.get_site_by_key("existing-site")
    assert File.read!(existing_file) == "legacy"
  end

  test "suspends, archives, and only permanently deletes after retention", %{creator: creator} do
    assert {:ok, site} = Setup.create_site(site_attrs("retained-site"), creator)
    assert {:ok, suspended} = Setup.suspend_site(site)
    assert suspended.status == :suspended
    refute Brando.Tenant.Cache.get_live_env(site.key)

    archived_at = DateTime.utc_now()
    assert {:ok, archived} = Setup.archive_site(suspended, now: archived_at)
    assert archived.status == :archived
    assert archived.archived_at == archived_at

    assert {:error, {:retention_period, 30}} =
             Setup.delete_site(archived, now: DateTime.add(archived_at, 29, :day))

    assert Registry.get_site(archived.id)
    assert Schema.exists?("tenant_retained-site_production")

    assert {:ok, deleted} =
             Setup.delete_site(archived, now: DateTime.add(archived_at, 30, :day))

    assert deleted.id == archived.id
    refute Registry.get_site(archived.id)
    refute Schema.exists?("tenant_retained-site_production")
    refute Schema.exists?("tenant_retained-site_staging")
    refute File.exists?(Storage.media_root(archived))
    refute File.exists?(Storage.site_root(archived))
  end

  # Audit F46: the rows named a site by its key, and outlived it
  describe "rows in shared tables that name an environment" do
    alias Brando.Forms.Submission
    alias Brando.Tenant.ScopedRows
    alias Brando.Worker.OrphanedRowsPurge

    defp row(scope),
      do: Brando.Repo.insert!(%Submission{scope: scope, form_id: 1, form_key: "contact", language: "en", data: %{}})

    defp rows(scope), do: Brando.Repo.aggregate(from(s in Submission, where: s.scope == ^scope), :count)

    defp draft(scope, owner) do
      Ecto.Adapters.SQL.query!(
        Brando.Repo.repo(),
        """
        INSERT INTO public.entry_drafts (id, scope, owner_id, entry_type, form_name, generation, base_fingerprint,
          format_version, schema_version, payload, checksum, expires_at, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, 'x', 'default', 1, 'x', 1, 1, '{}', 'x', now(), now(), now())
        """,
        [scope, owner.id]
      )
    end

    test "deleting a site deletes them, and a site with the same keys starts empty", %{creator: creator} do
      assert {:ok, site} = Setup.create_site(site_attrs("reused-site"), creator)
      row("tenant_reused-site_production")
      row("tenant_reused-site_staging")
      kept = row("tenant_other-site_production")
      public = row("public")

      assert {:ok, suspended} = Setup.suspend_site(site)
      assert {:ok, archived} = Setup.archive_site(suspended, now: DateTime.utc_now())
      assert {:ok, _} = Setup.delete_site(archived, force: true)

      assert rows("tenant_reused-site_production") == 0
      assert rows("tenant_reused-site_staging") == 0
      assert Brando.Repo.get(Submission, kept.id)
      assert Brando.Repo.get(Submission, public.id)

      assert {:ok, _} = Setup.create_site(site_attrs("reused-site"), creator)
      assert rows("tenant_reused-site_production") == 0
    end

    test "deleting an environment deletes its rows and no other's", %{creator: creator} do
      assert {:ok, site} = Setup.create_site(site_attrs("env-rows"), creator)
      staging = Enum.find(Registry.list_environments(site), &(&1.key == "staging"))
      row("tenant_env-rows_staging")
      live = row("tenant_env-rows_production")

      assert {:ok, _} = Brando.Environments.delete_environment(staging)

      assert rows("tenant_env-rows_staging") == 0
      assert Brando.Repo.get(Submission, live.id)
    end

    test "a refused deletion keeps them", %{creator: creator} do
      assert {:ok, site} = Setup.create_site(site_attrs("refused-site"), creator)
      live = row("tenant_refused-site_production")
      production = Enum.find(Registry.list_environments(site), &(&1.key == "production"))

      assert {:error, :live_environment} = Brando.Environments.delete_environment(production)
      assert {:error, :site_must_be_archived} = Setup.delete_site(site)
      assert Brando.Repo.get(Submission, live.id)
    end

    test "the purge takes only scopes no environment or schema answers to", %{creator: creator} do
      assert {:ok, _site} = Setup.create_site(site_attrs("live-site"), creator)
      live = row("tenant_live-site_production")
      public = row("public")
      orphan = row("tenant_gone-site_production")
      draft("tenant_gone-site_production", creator)
      not_a_prefix = row("not a prefix")

      # A registry row lost, its schema still there: not orphaned
      Schema.create("tenant_unregistered_production")
      with_schema = row("tenant_unregistered_production")

      assert ScopedRows.orphaned() == %{"tenant_gone-site_production" => %{"forms_submissions" => 1, "entry_drafts" => 1}}
      assert Brando.Repo.get(Submission, orphan.id)

      assert :ok = OrphanedRowsPurge.perform(%Oban.Job{args: %{"environments" => true}})

      refute Brando.Repo.get(Submission, orphan.id)
      assert ScopedRows.orphaned() == %{}

      for kept <- [live, public, not_a_prefix, with_schema], do: assert(Brando.Repo.get(Submission, kept.id))
    end

    test "without tenancy, or with no environment registered, the purge finds nothing" do
      orphan = row("tenant_gone-site_production")
      assert ScopedRows.orphaned() == %{}

      put_test_env(:tenancy_mode, :none)
      assert ScopedRows.orphaned() == %{}
      assert ScopedRows.delete_orphaned() == []
      assert Brando.Repo.get(Submission, orphan.id)
    end

    test "the purge of a form's submissions looks at that environment's forms", %{creator: creator} do
      assert {:ok, _site} = Setup.create_site(site_attrs("form-site"), creator)
      prefix = "tenant_form-site_production"
      Schema.create(prefix)

      Ecto.Adapters.SQL.query!(
        Brando.Repo.repo(),
        "CREATE TABLE \"#{prefix}\".forms (LIKE public.forms INCLUDING DEFAULTS)"
      )

      Ecto.Adapters.SQL.query!(Brando.Repo.repo(), """
      INSERT INTO "#{prefix}".forms (id, key, language, title, status, recipients, confirmation, inserted_at, updated_at)
      VALUES (1, 'live', 'en', 'Live', 1, '[]', false, now(), now())
      """)

      live_row = Brando.Repo.insert!(%Submission{scope: prefix, form_id: 1, form_key: "live", language: "en", data: %{}})
      orphan = Brando.Repo.insert!(%Submission{scope: prefix, form_id: 1, form_key: "orphan", language: "en", data: %{}})

      public_row =
        Brando.Repo.insert!(%Submission{scope: "public", form_id: 1, form_key: "orphan", language: "en", data: %{}})

      args = %{"form_keys" => ["live", "orphan"], "tenant_prefix" => prefix}
      assert :ok = OrphanedRowsPurge.perform(%Oban.Job{args: args})

      assert Brando.Repo.get(Submission, live_row.id)
      refute Brando.Repo.get(Submission, orphan.id)
      assert Brando.Repo.get(Submission, public_row.id)
    end

    test "a purge naming an environment with no schema deletes nothing" do
      orphan = row("tenant_gone-site_production")
      args = %{"form_keys" => ["contact"], "tenant_prefix" => "tenant_gone-site_production"}

      assert_raise Postgrex.Error, fn -> OrphanedRowsPurge.perform(%Oban.Job{args: args}) end
      assert Brando.Repo.get(Submission, orphan.id)
    end
  end

  defp site_attrs(key) do
    %{
      name: "Tenant #{key}",
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    }
  end
end
