defmodule Brando.Repo.Migrations.AddIdentifierMetas do
  use Ecto.Migration

  def change do
    alter table(:content_blocks) do
      add :identifier_metas, :jsonb
    end
  end
end
