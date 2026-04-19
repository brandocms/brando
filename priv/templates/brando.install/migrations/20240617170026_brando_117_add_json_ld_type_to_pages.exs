defmodule Brando.Repo.Migrations.AddJsonLdTypeToPages do
  use Ecto.Migration

  def up do
    alter table(:pages) do
      add_if_not_exists :json_ld_type, :string, default: "WebPage"
    end
  end

  def down do
    alter table(:pages) do
      remove_if_exists :json_ld_type, :string
    end
  end
end
