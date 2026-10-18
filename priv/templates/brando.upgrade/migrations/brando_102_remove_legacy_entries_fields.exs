defmodule Brando.Repo.Migrations.RemoveLegacyEntriesFields do
  use Ecto.Migration

  alias Brando.Migration.Introspect

  def change do
    blueprints = Brando.Blueprint.list_blueprints()

    # Only tables that still have the legacy column. A Blueprint whose table
    # is created by a later migration has no table here yet.
    for blueprint <- blueprints,
        %{type: :entries, name: field_name} <- Brando.Blueprint.Relations.__relations__(blueprint),
        table_name = blueprint.__schema__(:source),
        Introspect.column_exists?(table_name, field_name) do
      alter table(table_name) do
        remove field_name
      end
    end
  end
end
