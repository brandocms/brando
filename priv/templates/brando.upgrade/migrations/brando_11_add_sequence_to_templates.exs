defmodule Brando.Repo.Migrations.AddSequenceToTemplates do
  use Ecto.Migration
  use Brando.Sequence.Migration

  def change do
    alter table(:pages_templates) do
      sequenced()
    end
  end
end
