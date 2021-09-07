defmodule Koi.Repo.Migrations.MoveModulesToContentNamespace do
  use Ecto.Migration

  def change do
    rename table(:pages_modules), to: table(:content_modules)
  end
end
