defmodule Brando.Repo.Migrations.Brando177AddIdentityServices do
  use Ecto.Migration

  @moduledoc """
  Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_177_*`.
  """

  def change do
    create table(:sites_services) do
      add :name, :string, null: false
      add :description, :text
      add :alternate_names, {:array, :string}, default: []
      add :service_type, :string
      add :url, :string
      add :area_served, {:array, :string}, default: []
      add :sequence, :integer, default: 0
      add :identity_id, references(:sites_identities, on_delete: :delete_all)
      add :identifier_id, references(:content_identifiers, on_delete: :nilify_all)
      timestamps()
    end

    create index(:sites_services, [:identity_id])
    create index(:sites_services, [:identifier_id])
  end
end
