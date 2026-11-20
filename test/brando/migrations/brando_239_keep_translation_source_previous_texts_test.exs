defmodule Brando.Migrations.Brando239KeepTranslationSourcePreviousTextsTest do
  # Runs the upgrade template inside the sandbox transaction, with the columns
  # dropped first, over groups, members and open work items from before it;
  # Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_239_keep_translation_source_previous_texts.exs"
  @tenant "tenant_acme_staging"
  @bare "tenant_acme_preview"
  @tables ~w(translation_groups translation_group_members translation_pending_versions translation_work_items)

  defp drop_columns(prefix) do
    query!(~s(ALTER TABLE "#{prefix}".translation_group_members DROP COLUMN baseline_texts))
    query!(~s(ALTER TABLE "#{prefix}".translation_work_items DROP COLUMN source_previous))
  end

  # A group with a source and a target whose pending version has an open review
  defp group_with_work!(prefix) do
    [[group]] =
      rows(
        ~s{INSERT INTO "#{prefix}".translation_groups (entry_type, inserted_at, updated_at) VALUES ('x', now(), now()) RETURNING id}
      )

    [[member]] =
      rows(
        ~s{INSERT INTO "#{prefix}".translation_group_members (group_id, entry_type, entry_id, language, role, baseline, inserted_at, updated_at)
           VALUES ($1, 'x', 2, 'en', 'target', $2, now(), now()) RETURNING id},
        [group, %{"title" => "abc"}]
      )

    [[version]] =
      rows(
        ~s{INSERT INTO "#{prefix}".translation_pending_versions
             (member_id, source_generation, source_fingerprint, base_fingerprint, payload, status, inserted_at, updated_at)
           VALUES ($1, 1, 's', 'b', '\\x00'::bytea, 'pending', now(), now()) RETURNING id},
        [member]
      )

    [[item]] =
      rows(
        ~s{INSERT INTO "#{prefix}".translation_work_items (pending_version_id, path, kind, source_digest, inserted_at, updated_at)
           VALUES ($1, 'title', 'review', 'def', now(), now()) RETURNING id},
        [version]
      )

    %{member: member, item: item}
  end

  test "adds the texts and the previous text in public and every environment with the tables, empty" do
    create_environment(@tenant, @tables)
    create_environment(@bare)

    for prefix <- ["public", @tenant], do: drop_columns(prefix)
    existing = Map.new(["public", @tenant], &{&1, group_with_work!(&1)})

    version = up(@template)

    for prefix <- ["public", @tenant] do
      %{member: member, item: item} = existing[prefix]

      assert rows(~s(SELECT baseline, baseline_texts FROM "#{prefix}".translation_group_members WHERE id = $1), [member]) ==
               [[%{"title" => "abc"}, %{}]]

      assert rows(~s(SELECT kind, source_previous FROM "#{prefix}".translation_work_items WHERE id = $1), [item]) ==
               [["review", nil]]
    end

    refute table?(@bare, "translation_work_items")

    # Running it again changes nothing
    up(@template)

    down(@template, version)

    for prefix <- ["public", @tenant] do
      refute "baseline_texts" in columns(prefix, "translation_group_members")
      refute "source_previous" in columns(prefix, "translation_work_items")
    end
  end
end
