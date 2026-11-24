defmodule Brando.Repo.Migrations.Brando235IndexTranslationPendingVersionsByMember do
  use Ecto.Migration

  @moduledoc """
  In every site environment, an index on `translation_pending_versions.member_id`.

  A synchronized translation keeps every pending version it was given, so its
  history grows with each source save. When the source edits a text nobody
  has translated yet, Brando reads that translation's `:translate` work items
  across its whole history (`Brando.Translations`); without the index that
  read scans every translation's versions. The only index on the column so far
  covers the one pending version.

  An environment without the translation tables is left alone.
  """

  def up do
    for prefix <- prefixes(), translations?(prefix) do
      create_if_not_exists index(:translation_pending_versions, [:member_id], prefix: prefix)
    end
  end

  def down do
    for prefix <- prefixes() do
      drop_if_exists index(:translation_pending_versions, [:member_id], prefix: prefix)
    end
  end

  defp translations?(prefix) do
    %{rows: [[name]]} =
      repo().query!("SELECT to_regclass($1)::text", [~s("#{prefix}".translation_pending_versions)])

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
