defmodule Brando.Repo.Migrations.RenameModuleWrapperToMulti do
  use Ecto.Migration

  def up do
    rename table(:content_modules), :wrapper, to: :multi
  end

  def down do
    rename table(:content_modules), :multi, to: :wrapper
  end
end
