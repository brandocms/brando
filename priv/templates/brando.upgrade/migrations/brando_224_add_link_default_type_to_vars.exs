defmodule Brando.Repo.Migrations.Brando224AddLinkDefaultTypeToVars do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `content_vars.link_default_type` holds the tab a
  link var's dialog opens on while the link is empty: `url`, the default, or
  `identifier` for content. Set in the var's Link settings; a module's blocks
  take it from the module when it is saved.
  """

  def up do
    for prefix <- prefixes() do
      alter table(:content_vars, prefix: prefix) do
        add_if_not_exists :link_default_type, :string, default: "url"
      end
    end
  end

  def down do
    for prefix <- prefixes() do
      alter table(:content_vars, prefix: prefix) do
        remove_if_exists :link_default_type, :string
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
