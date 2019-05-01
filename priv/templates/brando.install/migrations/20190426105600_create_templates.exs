defmodule <%= application_module %>.Repo.Migrations.CreateVillainTemplates do
  use Ecto.Migration

  def change do
    create table(:templates) do
      add :name, :string
      add :namespace, :string
      add :help_text, :text
      add :class, :string
      add :code, :text
      add :refs, :jsonb
      timestamps()
    end

    create index(:templates, [:namespace])
  end
end
