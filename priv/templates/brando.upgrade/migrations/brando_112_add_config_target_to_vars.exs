defmodule Brando.Repo.Migrations.AddConfigTargetToVars do
  use Ecto.Migration

  def up do
    alter table(:content_vars) do
      add :config_target, :text
    end
  end

  def down do
    alter table(:content_vars) do
      remove :config_target
    end
  end
end
