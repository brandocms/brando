defmodule Brando.Repo.Migrations.SequencePagesAndFragments do
  use Ecto.Migration
  import Brando.Sequence.Migration

  def change do
    alter table(:pages_pages) do
      add :sequence, :integer
    end

    alter table(:pages_fragments) do
      add :sequence, :integer
    end
  end
end
