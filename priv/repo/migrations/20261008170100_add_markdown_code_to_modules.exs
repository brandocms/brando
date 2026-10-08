defmodule Brando.Repo.Migrations.AddMarkdownCodeToModules do
  use Ecto.Migration

  # A module's optional Markdown template, see `Brando.Villain.Markdown`.
  def change do
    alter table(:content_modules) do
      add :markdown_code, :text
    end
  end
end
