defmodule Brando.Repo.Migrations.AddContainerToBlock do
  use Ecto.Migration

  def up do
    alter table(:content_blocks) do
      add :container_id, references(:content_containers, on_delete: :nilify_all)
    end
  end

  def down do
    alter table(:content_blocks) do
      remove :container_id
    end
  end
end
