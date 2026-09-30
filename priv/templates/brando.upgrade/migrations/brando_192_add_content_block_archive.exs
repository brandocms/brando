defmodule Brando.Repo.Migrations.Brando192AddContentBlockArchive do
  use Ecto.Migration

  @moduledoc """
  Where the block audit (`Brando.Content.BlockAudit`) puts a loose block tree
  before removing it: the tree's rows as they were, so it can be put back.
  """

  def change do
    create table(:content_block_archive) do
      add :root_block_id, :bigint, null: false
      add :uid, :text
      add :block_count, :integer, null: false, default: 1
      add :summary, :map, null: false, default: %{}
      add :data, :map, null: false
      add :removed_by_id, references(:users, prefix: "public", on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    create index(:content_block_archive, [:root_block_id])
  end
end
