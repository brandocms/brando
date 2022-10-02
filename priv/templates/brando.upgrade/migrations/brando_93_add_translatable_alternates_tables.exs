defmodule Brando.Repo.Migrations.AddTranslatableAlternatesTables do
  use Ecto.Migration

  def change do
    blueprints = Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page, Brando.Pages.Fragment]

    for blueprint <- blueprints do
      if blueprint.has_trait(Brando.Trait.Translatable) do
        alternate_source = "#{blueprint.__schema__(:source)}_alternates"

        create table(alternate_source) do
          add :entry_id, references(blueprint.__schema__(:source), on_delete: :nilify_all)
          add :linked_entry_id, references(blueprint.__schema__(:source), on_delete: :nilify_all)
          timestamps()
        end

        create unique_index(alternate_source, [:entry_id, :linked_entry_id])
      end
    end
  end
end
