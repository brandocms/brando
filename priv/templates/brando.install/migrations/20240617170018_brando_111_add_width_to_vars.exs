defmodule Brando.Repo.Migrations.AddWidthToVars do
  use Ecto.Migration

  def up do
    alter table(:content_vars) do
      add :width, :string, default: "full"
    end
  end

  def down do
    alter table(:content_vars) do
      remove :width
    end
  end
end
