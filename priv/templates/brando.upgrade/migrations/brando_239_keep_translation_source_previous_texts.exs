defmodule Brando.Repo.Migrations.Brando239KeepTranslationSourcePreviousTexts do
  use Ecto.Migration

  @moduledoc """
  In every site environment, room for the source's previous text of a
  synchronized translation's review.

  `translation_group_members.baseline_texts` keeps the source's texts of a
  translation's last sync beside their digests, and
  `translation_work_items.source_previous` the source's text before the
  change that raised a review. Both start empty: a member gains its texts at
  its next sync, and only reviews raised after that carry a previous text.

  An environment without the translation tables is left alone.
  """

  def up do
    for prefix <- prefixes(), translations?(prefix) do
      alter table(:translation_group_members, prefix: prefix) do
        add_if_not_exists :baseline_texts, :map, null: false, default: %{}
      end

      alter table(:translation_work_items, prefix: prefix) do
        add_if_not_exists :source_previous, :text
      end
    end
  end

  def down do
    for prefix <- prefixes(), translations?(prefix) do
      alter table(:translation_work_items, prefix: prefix) do
        remove_if_exists :source_previous, :text
      end

      alter table(:translation_group_members, prefix: prefix) do
        remove_if_exists :baseline_texts, :map
      end
    end
  end

  defp translations?(prefix) do
    %{rows: [[name]]} =
      repo().query!("SELECT to_regclass($1)::text", [~s("#{prefix}".translation_work_items)])

    not is_nil(name)
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end
