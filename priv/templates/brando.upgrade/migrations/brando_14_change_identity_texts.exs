defmodule Brando.Repo.Migrations.ChangeIdentityTexts do
  use Ecto.Migration

  def change do
    alter table(:sites_identities) do
      modify :description, :text
      modify :title, :text
    end
  end
end
