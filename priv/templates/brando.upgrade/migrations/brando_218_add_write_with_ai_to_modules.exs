defmodule Brando.Repo.Migrations.Brando218AddWriteWithAIToModules do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `content_modules.write_with_ai` turns on Write
  with AI in a module's text blocks, under Overview in the module editor.
  Every request is a paid call to the AI service, so it is off in every
  existing module until turned on.
  """

  def up do
    for prefix <- prefixes() do
      alter table(:content_modules, prefix: prefix) do
        add :write_with_ai, :boolean, default: false
      end
    end
  end

  def down do
    for prefix <- prefixes() do
      alter table(:content_modules, prefix: prefix) do
        remove :write_with_ai
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
