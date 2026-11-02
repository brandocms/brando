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
    alias Brando.AI.Agent.Conversation
    alias Brando.AI.Agent.Guidance.Version
    alias Brando.AI.Agent.Run
    alias Brando.Content.Definition.References
    alias Brando.Forms.Submission
    alias Brando.Tenant.ScopedRows
    alias Brando.Worker.OrphanedRowsPurge

    # No form has id 0.
    defp row(scope),
      do: Brando.Repo.insert!(%Submission{scope: scope, form_id: 0, form_key: "contact", language: "en", data: %{}})

    defp rows(scope), do: Brando.Repo.aggregate(from(s in Submission, where: s.scope == ^scope), :count)

    defp digest(prefix), do: Tenant.with_prefix(prefix, &References.scope/0)

    defp guidance(scope, prefix), do: Brando.Repo.insert!(%Version{scope: scope, prefix: prefix, text: "x"})

    defp conversation(scope, actor), do: Brando.Repo.insert!(%Conversation{scope: scope, actor_id: actor.id})

    defp run(%Conversation{} = conversation),
      do: Brando.Repo.insert!(%Run{conversation_id: conversation.id, scope: conversation.scope, status: "running"})

    # What the environment's digest holds in the digest tables
    defp digest_rows(prefix, actor) do
      conversation = conversation(digest(prefix), actor)
      [guidance(digest(prefix), prefix), conversation, run(conversation)]
    end

    defp reloaded(rows), do: Enum.map(rows, fn row -> Brando.Repo.repo().reload(row) end)

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

      gone_digest_rows =
        digest_rows("tenant_reused-site_production", creator) ++ digest_rows("tenant_reused-site_staging", creator)

      kept_digest_rows = digest_rows("tenant_other-site_production", creator)

      assert {:ok, suspended} = Setup.suspend_site(site)
      assert {:ok, archived} = Setup.archive_site(suspended, now: DateTime.utc_now())
      assert {:ok, _} = Setup.delete_site(archived, force: true)

      assert rows("tenant_reused-site_production") == 0
      assert rows("tenant_reused-site_staging") == 0
      assert Brando.Repo.get(Submission, kept.id)
      assert Brando.Repo.get(Submission, public.id)
      assert Enum.all?(reloaded(gone_digest_rows), &is_nil/1)
      refute Enum.any?(reloaded(kept_digest_rows), &is_nil/1)

      assert {:ok, _} = Setup.create_site(site_attrs("reused-site"), creator)
      assert rows("tenant_reused-site_production") == 0
    end

    test "deleting an environment deletes its rows and no other's", %{creator: creator} do
      assert {:ok, site} = Setup.create_site(site_attrs("env-rows"), creator)
      staging = Enum.find(Registry.list_environments(site), &(&1.key == "staging"))
      row("tenant_env-rows_staging")
      live = row("tenant_env-rows_production")
      staging_rows = digest_rows("tenant_env-rows_staging", creator)
      live_rows = digest_rows("tenant_env-rows_production", creator)

      assert {:ok, _} = Brando.Environments.delete_environment(staging)

      assert rows("tenant_env-rows_staging") == 0
      assert Brando.Repo.get(Submission, live.id)
      assert Enum.all?(reloaded(staging_rows), &is_nil/1)
      refute Enum.any?(reloaded(live_rows), &is_nil/1)
    end

    # Without tenancy every prefix digests as `public`, whose rows are live
    test "without tenancy, deleting by prefix leaves the digest tables alone", %{creator: creator} do
      put_test_env(:tenancy_mode, :none)
      live = conversation(References.scope(), creator)

      assert :ok = ScopedRows.delete(["tenant_gone-site_production"])
      assert Brando.Repo.repo().reload(live)
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

      orphan_digest_rows = digest_rows("tenant_gone-site_production", creator)
      live_digest_rows = digest_rows("tenant_live-site_production", creator)

      assert ScopedRows.orphaned() == %{
               "tenant_gone-site_production" => %{
                 "forms_submissions" => 1,
                 "entry_drafts" => 1,
                 "ai_guidance_versions" => 1,
                 "ai_conversations" => 1,
                 "ai_runs" => 1
               }
             }

      assert Brando.Repo.get(Submission, orphan.id)

      assert :ok = OrphanedRowsPurge.perform(%Oban.Job{args: %{"environments" => true}})

      refute Brando.Repo.get(Submission, orphan.id)
      assert Enum.all?(reloaded(orphan_digest_rows), &is_nil/1)
      refute Enum.any?(reloaded(live_digest_rows), &is_nil/1)
      assert ScopedRows.orphaned() == %{}

      for kept <- [live, public, not_a_prefix, with_schema], do: assert(Brando.Repo.get(Submission, kept.id))
    end

    test "guidance names its environment, so its digest rows are found with no other trace", %{creator: creator} do
      assert {:ok, _site} = Setup.create_site(site_attrs("live-site"), creator)
      guidance(digest("tenant_gone-site_production"), "tenant_gone-site_production")

      assert ScopedRows.orphaned() == %{"tenant_gone-site_production" => %{"ai_guidance_versions" => 1}}
      assert ScopedRows.delete_orphaned() == ["tenant_gone-site_production"]
      assert ScopedRows.orphaned() == %{}
    end

    # A digest depends on the database's host and port: a moved database's
    # rows match nothing known, and can be a live environment's.
    test "a digest matching nothing known is neither reported nor deleted", %{creator: creator} do
      assert {:ok, _site} = Setup.create_site(site_attrs("live-site"), creator)
      unknown = conversation("digest-of-another-host", creator)
      unknown_run = run(unknown)
      unknown_guidance = guidance("digest-of-another-host", nil)
      stale_guidance = guidance("digest-of-another-host", "tenant_live-site_production")
      stale_gone_guidance = guidance("digest-of-another-host", "tenant_gone-site_production")

      assert ScopedRows.orphaned() == %{}
      assert ScopedRows.delete_orphaned() == []
      assert ScopedRows.delete_orphaned(["tenant_gone-site_production"]) == []

      refute [unknown, unknown_run, unknown_guidance, stale_guidance, stale_gone_guidance]
             |> reloaded()
             |> Enum.any?(&is_nil/1)
    end

    test "a scope that came to be after the report is kept", %{creator: creator} do
      assert {:ok, _site} = Setup.create_site(site_attrs("live-site"), creator)
      registered_later = row("tenant_late-site_production")
      registered_later_digest = conversation(digest("tenant_late-site_production"), creator)
      schema_later = row("tenant_schema-later_production")
      environment_later = row("tenant_live-site_preview")
      orphan = row("tenant_gone-site_production")

      scopes = Map.keys(ScopedRows.orphaned())
      assert length(scopes) == 4

      assert {:ok, _site} = Setup.create_site(site_attrs("late-site"), creator)
      Schema.create("tenant_schema-later_production")
      site = Registry.get_site_by_key("live-site")

      assert {:ok, _environment} =
               Brando.Environments.create_environment(site, %{key: "preview", name: "Preview"}, creator: creator)

      assert ScopedRows.delete_orphaned(scopes) == ["tenant_gone-site_production"]

      refute Brando.Repo.get(Submission, orphan.id)

      for kept <- [registered_later, registered_later_digest, schema_later, environment_later],
          do: assert(Brando.Repo.repo().reload(kept))
    end

    test "the purge holds the site's locks while it looks and deletes", %{creator: creator} do
      assert {:ok, site} = Setup.create_site(site_attrs("live-site"), creator)
      row("tenant_live-site_gone")
      row("tenant_gone-site_production")

      calls = queries_of(fn -> ScopedRows.delete_orphaned() end)
      lock_keys = for {"SELECT pg_advisory_lock" <> _, [key]} <- calls, do: key

      assert "brando:site-lifecycle:live-site" in lock_keys
      assert "brando:environment-operation:#{site.id}" in lock_keys
      assert "brando:site-lifecycle:gone-site" in lock_keys

      # Creating an environment takes neither: its foreign key waits on the site's row
      queries = Enum.map(calls, &elem(&1, 0))
      row_lock = Enum.find_index(queries, &(&1 =~ ~s("sites") and &1 =~ "FOR UPDATE"))
      assert queries |> Enum.drop(row_lock) |> Enum.any?(&(&1 =~ ~s(DELETE FROM "public"."forms_submissions")))

      assert rows("tenant_live-site_gone") == 0
      assert rows("tenant_gone-site_production") == 0
    end

    test "a scope with no site key in it is not deleted" do
      kept = row("public")
      not_a_prefix = row("not a prefix")

      assert ScopedRows.delete_orphaned(["public", "not a prefix", "tenant_nokey"]) == []
      assert Brando.Repo.get(Submission, kept.id)
      assert Brando.Repo.get(Submission, not_a_prefix.id)
    end

    test "without tenancy, or with no environment registered, the purge finds nothing" do
      orphan = row("tenant_gone-site_production")
      assert ScopedRows.orphaned() == %{}

      put_test_env(:tenancy_mode, :none)
      assert ScopedRows.orphaned() == %{}
      assert ScopedRows.delete_orphaned() == []
      assert ScopedRows.delete_orphaned(["tenant_gone-site_production"]) == []
      assert Brando.Repo.get(Submission, orphan.id)
    end

    test "the purge of a form's submissions looks at that environment's forms", %{creator: creator} do
      assert {:ok, site} = Setup.create_site(site_attrs("form-site"), creator)
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
      orphan = Brando.Repo.insert!(%Submission{scope: prefix, form_id: 0, form_key: "orphan", language: "en", data: %{}})

      # A key no form has, on a row of the form with id 1: renamed, so live
      renamed = Brando.Repo.insert!(%Submission{scope: prefix, form_id: 1, form_key: "old", language: "en", data: %{}})

      public_row =
        Brando.Repo.insert!(%Submission{scope: "public", form_id: 0, form_key: "orphan", language: "en", data: %{}})

      args = %{"form_keys" => ["live", "orphan", "old"], "tenant_prefix" => prefix}
      calls = queries_of(fn -> assert :ok = OrphanedRowsPurge.perform(%Oban.Job{args: args}) end)

      # Copying an environment empties its forms for a moment
      lock = Enum.find_index(calls, &match?({"SELECT pg_advisory_lock" <> _, ["brando:environment-operation:" <> _]}, &1))
      table_lock = Enum.find_index(calls, fn {query, _} -> query =~ ~s(LOCK TABLE "#{prefix}".forms IN SHARE MODE) end)
      assert elem(Enum.at(calls, lock), 1) == ["brando:environment-operation:#{site.id}"]
      assert lock < table_lock

      assert Brando.Repo.get(Submission, renamed.id)

      assert Brando.Repo.get(Submission, live_row.id)
      refute Brando.Repo.get(Submission, orphan.id)
      assert Brando.Repo.get(Submission, public_row.id)
    end

    test "a purge of a form's rows that cannot say which environment it means is cancelled", %{creator: creator} do
      assert {:ok, _site} = Setup.create_site(site_attrs("form-site"), creator)
      orphan = row("tenant_gone-site_production")
      public_row = row("public")
      keys = ["contact"]

      # Tenancy on: no environment named, or one nobody has registered
      for prefix <- [nil, "tenant_gone-site_production", "tenant_form-site_gone", "public", "tenant_nokey", 5] do
        args = %{"form_keys" => keys, "tenant_prefix" => prefix}
        assert {:cancel, _reason} = OrphanedRowsPurge.perform(%Oban.Job{args: args})
      end

      assert {:cancel, _reason} = OrphanedRowsPurge.perform(%Oban.Job{args: %{"form_keys" => keys}})

      # Tenancy off: an environment named all the same
      put_test_env(:tenancy_mode, :none)
      args = %{"form_keys" => keys, "tenant_prefix" => "tenant_form-site_production"}
      assert {:cancel, _reason} = OrphanedRowsPurge.perform(%Oban.Job{args: args})

      assert Brando.Repo.get(Submission, orphan.id)
      assert Brando.Repo.get(Submission, public_row.id)
    end
  end

  def send_query(_event, _measurements, metadata, test_pid) do
    if self() == test_pid, do: send(test_pid, {:query, metadata.query, metadata.params})
  end

  defp queries_of(fun) do
    handler = "scoped-rows-#{System.unique_integer([:positive])}"
    event = Brando.Repo.repo().config()[:telemetry_prefix] ++ [:query]
    :ok = :telemetry.attach(handler, event, &__MODULE__.send_query/4, self())

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect_queries([])
  end

  defp collect_queries(queries) do
    receive do
      {:query, query, params} -> collect_queries([{query, params} | queries])
    after
      0 -> Enum.reverse(queries)
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
