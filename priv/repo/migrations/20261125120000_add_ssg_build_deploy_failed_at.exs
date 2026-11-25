defmodule BrandoIntegration.Repo.Migrations.AddSSGBuildDeployFailedAt do
  use Ecto.Migration

  # Mirrors the brando_251 upgrade migration for the test schema.
  @moduledoc "When a static build's deploy was given up (`Brando.SSG.Publishing`)."

  def change do
    alter table(:ssg_builds, prefix: "public") do
      add :deploy_failed_at, :utc_datetime_usec
    end
  end
end
