defmodule Brando.Repo.Migrations.AddBreadcrumbsToPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :breadcrumbs, :jsonb, default: "[]"
    end
  end
end
