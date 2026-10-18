defmodule Brando.Repo.Migrations.AddTranslatableAlternatesTables do
  use Ecto.Migration

  alias Brando.Migration.Introspect

  def change do
    blueprints = Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page, Brando.Pages.Fragment]

    for blueprint <- blueprints do
      alternate_source = "#{blueprint.__schema__(:source)}_alternates"

      # A Blueprint whose table is created by a later migration gets its
      # alternates table from that migration
      if blueprint.has_trait(Brando.Trait.Translatable) and blueprint.has_alternates?() and
           Introspect.table_exists?(blueprint.__schema__(:source)) do
        create table(alternate_source) do
          add :entry_id, references(blueprint.__schema__(:source), on_delete: :delete_all)
          add :linked_entry_id, references(blueprint.__schema__(:source), on_delete: :delete_all)
          timestamps()
        end

        create unique_index(alternate_source, [:entry_id, :linked_entry_id])
      end
    end
  end
end
