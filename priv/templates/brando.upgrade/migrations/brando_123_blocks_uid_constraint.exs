defmodule Brando.Repo.Migrations.BlocksUniqueUID do
  use Ecto.Migration

  def change do
    create unique_index(:content_blocks, [:uid])
  end
end
