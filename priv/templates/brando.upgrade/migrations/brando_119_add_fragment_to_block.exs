defmodule Brando.Repo.Migrations.AddFragmentToBlock do
  use Ecto.Migration

  def up do
    alter table(:content_blocks) do
      add :fragment_id, references(:pages_fragments, on_delete: :nilify_all)
    end
  end

  def down do
    alter table(:content_blocks) do
      remove :fragment_id
    end
  end
end
