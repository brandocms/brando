defmodule Brando.Repo.Migrations.AddHasURLtoPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :has_url, :boolean, default: true
    end
  end
end
