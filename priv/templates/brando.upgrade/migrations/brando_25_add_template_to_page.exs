defmodule Brando.Repo.Migrations.AddTemplateToPage do
  use Ecto.Migration

  def change do
    alter table(:pages_pages) do
      add :template, :text, default: "default.html"
    end
  end
end
