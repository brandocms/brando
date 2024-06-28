defmodule Brando.Repo.Migrations.AddLanguageToIdentity do
  use Ecto.Migration

  def change do
    rename table(:sites_identity), to: table(:sites_identities)

    alter table(:sites_identities) do
      add :language, :text, default: "en"
    end
  end
end
