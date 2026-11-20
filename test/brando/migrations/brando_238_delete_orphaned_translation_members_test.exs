defmodule Brando.Migrations.Brando238DeleteOrphanedTranslationMembersTest do
  # Runs the upgrade template inside the sandbox transaction, over members
  # left behind by entries deleted before Brando removed them (#3752).
  use Brando.ConnCase

  import Brando.MigrationTemplates
  import ExUnit.CaptureLog

  alias Brando.Factory
  alias Brando.SyncTest.Article

  @template "brando_238_delete_orphaned_translation_members.exs"
  @tenant "tenant_acme_staging"
  @bare "tenant_acme_preview"
  @tables ~w(translation_groups translation_group_members translation_pending_versions translation_work_items)
  @article to_string(Article)
  @page to_string(Brando.Pages.Page)

  defp group!(prefix \\ "public") do
    [[id]] =
      rows(
        ~s{INSERT INTO "#{prefix}".translation_groups (entry_type, inserted_at, updated_at) VALUES ('x', now(), now()) RETURNING id},
        []
      )

    id
  end

  defp member!(group_id, type, entry_id, language, role, prefix \\ "public") do
    [[id]] =
      rows(
        ~s{INSERT INTO "#{prefix}".translation_group_members (group_id, entry_type, entry_id, language, role, inserted_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, now(), now()) RETURNING id},
        [group_id, type, entry_id, language, role]
      )

    id
  end

  defp pending!(member_id) do
    [[id]] =
      rows(
        """
        INSERT INTO translation_pending_versions
          (member_id, source_generation, source_fingerprint, base_fingerprint, payload, status, inserted_at, updated_at)
        VALUES ($1, 1, 's', 'b', '\\x00'::bytea, 'pending', now(), now()) RETURNING id
        """,
        [member_id]
      )

    query!(
      "INSERT INTO translation_work_items (pending_version_id, path, kind, inserted_at, updated_at) VALUES ($1, 'title', 'translate', now(), now())",
      [id]
    )

    id
  end

  defp exists?(table, id, prefix \\ "public"),
    do: rows(~s(SELECT 1 FROM "#{prefix}".#{table} WHERE id = $1), [id]) != []

  defp article!(user, language) do
    n = System.unique_integer([:positive])

    {:ok, article} =
      Brando.SyncTest.create_article(%{title: "A", slug: "a-#{n}", language: language, status: "draft"}, user)

    article
  end

  test "removes members whose entries are gone, and groups with no member left whose entry exists" do
    user = Factory.insert(:random_user)
    source = article!(user, "no")
    lone = article!(user, "en")
    trashed = Factory.insert(:page, uri: "trashed", language: :en, creator: user, deleted_at: DateTime.utc_now())
    page = Factory.insert(:page, uri: "kept", language: :no, creator: user)
    gone = 2_000_000_000

    # A source whose translation was deleted for good
    kept_group = group!()
    source_member = member!(kept_group, @article, source.id, "no", "source")
    orphan = member!(kept_group, @article, gone, "en", "target")
    version = pending!(orphan)

    # A source deleted without the guard, with a synchronized translation
    # left in its group: the group stays as it was, for `transfer_source/3`
    gone_group = group!()
    gone_source = member!(gone_group, @article, gone - 1, "no", "source")
    translation = member!(gone_group, @article, lone.id, "en", "target")
    work = pending!(translation)

    # A group with no member whose entry exists
    empty_group = group!()
    member!(empty_group, @article, gone - 2, "no", "source")
    empty_target = member!(empty_group, @article, gone - 3, "en", "target")
    empty_work = pending!(empty_target)

    # A translation in the trash, and an entry type no blueprint defines
    page_group = group!()
    member!(page_group, @page, page.id, "no", "source")
    in_trash = member!(page_group, @page, trashed.id, "en", "target")
    unknown_group = group!()
    unknown = member!(unknown_group, "Elixir.Gone.Schema", gone, "no", "source")

    create_environment(@tenant, @tables ++ [Article.__schema__(:source)])
    tenant_group = group!(@tenant)
    member!(tenant_group, @article, gone, "no", "source", @tenant)
    # An environment from before synchronized translations
    create_environment(@bare)

    # The test config logs errors only
    migration = Brando.Repo.Migrations.Brando238DeleteOrphanedTranslationMembers
    Logger.put_module_level(migration, :warning)
    on_exit(fn -> Logger.delete_module_level(migration) end)
    log = capture_log([level: :warning], fn -> up(@template) end)

    assert exists?("translation_group_members", source_member)
    refute exists?("translation_group_members", orphan)
    refute exists?("translation_pending_versions", version)
    assert exists?("translation_groups", kept_group)

    assert exists?("translation_groups", gone_group)
    assert exists?("translation_group_members", gone_source)
    assert exists?("translation_group_members", translation)
    assert exists?("translation_pending_versions", work)
    assert log =~ "translation group #{gone_group},"
    refute log =~ "translation group #{empty_group},"

    refute exists?("translation_groups", empty_group)
    refute exists?("translation_group_members", empty_target)
    refute exists?("translation_pending_versions", empty_work)

    assert exists?("translation_group_members", in_trash)
    assert exists?("translation_group_members", unknown)

    refute exists?("translation_groups", tenant_group, @tenant)
    refute table?(@bare, "translation_group_members")
  end
end
