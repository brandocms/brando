defmodule Brando.Repo.Migrations.AddPublishAtToPages do
  use Ecto.Migration

  def change do
    alter table(:pages_pages) do
      add :publish_at, :utc_datetime
    end

    create index(:pages_pages, [:publish_at])
  end
end
