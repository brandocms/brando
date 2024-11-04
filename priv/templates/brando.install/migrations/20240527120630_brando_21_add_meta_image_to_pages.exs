defmodule Brando.Repo.Migrations.AddMetaImageToPages do
  use Ecto.Migration

  def change do
    alter table(:pages_pages) do
      add :meta_image, :jsonb
    end
  end
end
