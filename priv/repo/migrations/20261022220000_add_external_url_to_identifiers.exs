defmodule BrandoIntegration.Repo.Migrations.AddExternalURLToIdentifiers do
  use Ecto.Migration

  # Mirrors the brando_220 upgrade migration for the test schema.
  @moduledoc """
  `content_identifiers.external_url`: where links to an entry without a page
  on the site go (`absolute_url ..., link_others_to:`).
  """

  def change do
    alter table(:content_identifiers) do
      add :external_url, :text
    end
  end
end
