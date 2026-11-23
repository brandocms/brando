defmodule Brando.Repo.Migrations.Brando246AddMediaDropToModules do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `content_modules.media_drop_child` and
  `media_drop_ref` let a multi module take dropped images and videos: each
  file creates one block of the child module with that UID, with the file in
  the named ref. Empty in every existing module, which keeps working as
  before.
  """

  def up do
    for prefix <- prefixes() do
      alter table(:content_modules, prefix: prefix) do
        add_if_not_exists :media_drop_child, :text
        add_if_not_exists :media_drop_ref, :text
      end
    end
  end

  def down do
    for prefix <- prefixes() do
      alter table(:content_modules, prefix: prefix) do
        remove_if_exists :media_drop_ref, :text
        remove_if_exists :media_drop_child, :text
      end
    end
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
