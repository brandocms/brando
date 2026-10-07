defmodule BrandoIntegration.Repo.Migrations.AddPublicProfileToUsers do
  use Ecto.Migration

  # Mirrors the brando_202 upgrade migration for the test schema.
  @moduledoc """
  A user's public profile for JSON-LD author entities: job title and profile
  links.
  """

  def change do
    alter table(:users) do
      add :job_title, :text
      add :same_as, {:array, :string}, default: []
    end
  end
end
