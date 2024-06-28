defmodule Brando.Repo.Migrations.AddSVGToTemplates do
  use Ecto.Migration
  use Brando.Sequence.Migration

  def change do
    alter table(:pages_templates) do
      add :svg, :text
    end
  end
end
