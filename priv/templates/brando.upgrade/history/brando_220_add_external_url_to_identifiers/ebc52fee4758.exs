defmodule Brando.Repo.Migrations.Brando220AddExternalURLToIdentifiers do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `content_identifiers.external_url` holds where
  links to an entry go when it has no page on the site, as its blueprint
  declares with `absolute_url ..., link_others_to: field`. It stays empty
  until the entry's identifier is next saved, or Sync identifiers runs in
  Utilities.
  """

  def up do
    for prefix <- prefixes() do
      alter table(:content_identifiers, prefix: prefix) do
        add :external_url, :text
      end
    end
  end

  def down do
    for prefix <- prefixes() do
      alter table(:content_identifiers, prefix: prefix) do
        remove :external_url
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
