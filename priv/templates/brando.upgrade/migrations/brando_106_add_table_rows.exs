defmodule Brando.Repo.Migrations.AddTableRows do
  use Ecto.Migration
  import Ecto.Query

  def up do
    create table(:content_table_rows) do
      add :sequence, :integer
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      timestamps()
    end

    alter table(:content_vars) do
      add :table_row_id, references(:content_table_rows, on_delete: :delete_all)
    end
    create index(:content_vars, [:table_row_id])
  end

  def down do
    alter table(:content_vars) do
      remove :table_row_id
    end

    drop table(:content_table_rows)
  end
end
