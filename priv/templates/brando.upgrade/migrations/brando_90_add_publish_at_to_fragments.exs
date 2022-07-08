defmodule Brando.Repo.Migrations.AddPublishAtToFragments do
  use Ecto.Migration

  def change do
    alter table(:pages_fragments) do
      add :publish_at, :utc_datetime
    end

    create index(:pages_fragments, [:publish_at])
  end
end
