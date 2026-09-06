defmodule Brando.Repo.Migrations.AddBlockSlots do
  use Ecto.Migration

  def change do
    alter table(:content_blocks) do
      add :slot_name, :text
      add :slot_kind, :text
      add :slot_module_set, :text
    end

    create index(:content_blocks, [:parent_id, :slot_kind, :slot_name])
  end
end
