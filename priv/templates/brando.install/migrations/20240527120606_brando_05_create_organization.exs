defmodule Brando.Repo.Migrations.CreateOrganization do
  use Ecto.Migration

  def change do
    create table(:sites_organizations) do
      add :name, :string
      add :alternate_name, :string
      add :email, :string
      add :phone, :string
      add :address, :string
      add :zipcode, :string
      add :city, :string
      add :country, :string
      add :description, :string
      add :title_prefix, :string
      add :title, :string
      add :title_postfix, :string
      add :image, :jsonb
      add :logo, :jsonb
      add :url, :string

      timestamps()
    end
  end
end
