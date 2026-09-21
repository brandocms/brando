defmodule Brando.Repo.Migrations.AddUpdatedByToE2eBlueprints do
  use Ecto.Migration

  @tables ~w(projects_projects projects_categories projects_clients)a

  def change do
    for table <- @tables do
      alter table(table) do
        add :updated_by_id, references(:users, on_delete: :nilify_all)
        add :edited_at, :utc_datetime
      end

      create index(table, [:updated_by_id])
    end
  end
end
