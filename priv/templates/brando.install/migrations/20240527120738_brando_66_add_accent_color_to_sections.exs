defmodule Brando.Repo.Migrations.AddAccentColorToContentSections do
  use Ecto.Migration

  def change do
    alter table(:content_sections) do
      add :color_accent, :text
    end
  end
end
