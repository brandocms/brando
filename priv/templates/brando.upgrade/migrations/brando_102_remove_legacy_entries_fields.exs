defmodule Brando.Repo.Migrations.RemoveLegacyEntriesFields do
  use Ecto.Migration

  def change do
    blueprints = Brando.Blueprint.list_blueprints()

    for blueprint <- blueprints,
        %{type: :entries, name: field_name} <- Brando.Blueprint.Relations.__relations__(blueprint) do

      table_name = blueprint.__schema__(:source)
      alter table(table_name) do
        remove field_name
      end
    end
  end
end
