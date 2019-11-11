defmodule Brando.Repo.Migrations.SequencePagesAndFragments do
  use Ecto.Migration
  import Brando.Sequence.Migration

  def change do
    alter table(:pages_pages) do
      sequenced()
    end

    alter table(:pages_fragments) do
      sequenced()
    end
  end
end
