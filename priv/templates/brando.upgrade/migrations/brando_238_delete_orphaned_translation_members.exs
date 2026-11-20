defmodule Brando.Repo.Migrations.Brando238DeleteOrphanedTranslationMembers do
  use Ecto.Migration

  @moduledoc """
  In every site environment, takes synchronized translations deleted for good
  out of their groups.

  Until now an entry deleted for good, from the trash or in a schema without
  one, kept its row in `translation_group_members`, and with it its language:
  creating that language again was refused as if the version were still
  there. Brando now removes the member when its entry goes
  (`Brando.Translations.entries_deleted/2`); this removes those left behind,
  with their pending versions and work items. A group whose source is gone
  goes too, as it does when a source is deleted now; the independent versions
  left in it stay as they are, outside any group.

  A member whose entry is in the trash is kept: it still holds its language
  until the entry is restored or purged. A member of an entry type no
  blueprint of the application defines any longer is left alone, as are
  environments without the translation tables.
  """

  def up do
    for prefix <- prefixes(), table?(prefix, "translation_group_members") do
      for {type, table} <- entry_tables(prefix), do: delete_orphans(prefix, type, table)

      repo().query!("""
      DELETE FROM "#{prefix}".translation_groups g
      WHERE NOT EXISTS (
        SELECT 1 FROM "#{prefix}".translation_group_members m WHERE m.group_id = g.id AND m.role = 'source'
      )
      """)
    end
  end

  # The rows are gone for good
  def down, do: :ok

  defp delete_orphans(prefix, type, table) do
    repo().query!(
      """
      DELETE FROM "#{prefix}".translation_group_members m
      WHERE m.entry_type = $1 AND NOT EXISTS (SELECT 1 FROM #{table} e WHERE e.id = m.entry_id)
      """,
      [type]
    )
  end

  # `{entry type, quoted table}` for each entry type the members name whose
  # schema is still defined, in the environment's schema unless the
  # blueprint names its own
  defp entry_tables(prefix) do
    %{rows: rows} = repo().query!(~s(SELECT DISTINCT entry_type FROM "#{prefix}".translation_group_members))

    for [type] <- rows,
        module = schema_module(type),
        module != nil,
        table_prefix = module.__schema__(:prefix) || prefix,
        table = module.__schema__(:source),
        table?(table_prefix, table) do
      {type, ~s("#{table_prefix}"."#{table}")}
    end
  end

  defp schema_module(type) do
    module = String.to_existing_atom(type)
    if Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1), do: module
  rescue
    ArgumentError -> nil
  end

  defp table?(prefix, table) do
    %{rows: [[name]]} = repo().query!("SELECT to_regclass($1)::text", [~s("#{prefix}"."#{table}")])
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
