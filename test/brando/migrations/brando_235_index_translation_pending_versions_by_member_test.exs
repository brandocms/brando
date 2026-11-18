defmodule Brando.Migrations.Brando235IndexTranslationPendingVersionsByMemberTest do
  # Runs the upgrade template inside the sandbox transaction, with the index
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates
  import Ecto.Query, only: [from: 2]

  alias Brando.Translations.PendingVersion
  alias Brando.Translations.WorkItem
  alias BrandoIntegration.Repo

  @template "brando_235_index_translation_pending_versions_by_member.exs"
  @index "translation_pending_versions_member_id_index"
  @tenant "tenant_acme_staging"
  @bare "tenant_acme_preview"
  @tables ~w(translation_groups translation_group_members translation_pending_versions translation_work_items)

  defp index?(schema), do: rows("SELECT 1 FROM pg_indexes WHERE schemaname = $1 AND indexname = $2", [schema, @index]) != []

  test "indexes the pending versions by member in public and every environment that has them" do
    query!("DROP INDEX public.#{@index}")
    create_environment(@tenant, @tables)
    # An environment from before synchronized translations has no such table
    create_environment(@bare)

    version = up(@template)

    assert index?("public")
    assert index?(@tenant)
    refute table?(@bare, "translation_pending_versions")

    # Running it again changes nothing
    up(@template)

    down(@template, version)

    refute index?("public")
    refute index?(@tenant)
  end

  # `Brando.Translations`' read of a translation's `:translate` items across
  # its history (`seeded_digests/2`), which runs when the source edits a text
  # still to translate
  defp history_query(member_id, paths) do
    from(w in WorkItem,
      join: v in PendingVersion,
      on: v.id == w.pending_version_id,
      where: v.member_id == ^member_id and w.kind == :translate and w.path in ^paths,
      distinct: true,
      select: {w.path, w.source_digest}
    )
  end

  test "the read of a translation's history uses the index, not a scan of every translation's versions" do
    # 200 translations with 30 versions of 10 items each
    query!("""
    WITH groups AS (
      INSERT INTO translation_groups (entry_type, inserted_at, updated_at)
      SELECT 'Elixir.History', now(), now() FROM generate_series(1, 200)
      RETURNING id
    )
    INSERT INTO translation_group_members (group_id, entry_type, entry_id, language, role, inserted_at, updated_at)
    SELECT id, 'Elixir.History', id, 'en', 'target', now(), now() FROM groups
    """)

    query!("""
    INSERT INTO translation_pending_versions
      (member_id, source_generation, source_fingerprint, base_fingerprint, payload, status, inserted_at, updated_at)
    SELECT m.id, n, 'source', 'base', '\\x00'::bytea, CASE n WHEN 30 THEN 'pending' ELSE 'superseded' END, now(), now()
    FROM translation_group_members m, generate_series(1, 30) n
    WHERE m.entry_type = 'Elixir.History'
    """)

    query!("""
    INSERT INTO translation_work_items (pending_version_id, path, kind, source_digest, inserted_at, updated_at)
    SELECT v.id, 'title' || i, 'translate', md5(v.id::text || i), now(), now()
    FROM translation_pending_versions v
    JOIN translation_group_members m ON m.id = v.member_id, generate_series(1, 10) i
    WHERE m.entry_type = 'Elixir.History'
    """)

    for table <- @tables, do: query!("ANALYZE #{table}")

    [[member_id]] = rows("SELECT min(id) FROM translation_group_members WHERE entry_type = 'Elixir.History'", [])
    query = history_query(member_id, ["title1", "title2"])

    plan = Ecto.Adapters.SQL.explain(Repo, :all, query)

    assert plan =~ @index
    refute plan =~ "Seq Scan on translation_pending_versions"
    assert length(Repo.all(query)) == 60
  end
end
