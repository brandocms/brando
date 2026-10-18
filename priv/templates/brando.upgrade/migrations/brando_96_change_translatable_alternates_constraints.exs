defmodule Brando.Repo.Migrations.ChangeTranslatableAlternatesConstraints do
  use Ecto.Migration

  alias Brando.Migration.Introspect

  def change do
    blueprints = Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page, Brando.Pages.Fragment]

    for blueprint <- blueprints do
      alternate_source = "#{blueprint.__schema__(:source)}_alternates"

      # A Blueprint whose table is created by a later migration has no
      # alternates table yet; that migration creates it with these constraints
      if blueprint.has_trait(Brando.Trait.Translatable) and blueprint.has_alternates?() and
           Introspect.table_exists?(alternate_source) do
        drop_if_exists constraint(alternate_source, "#{alternate_source}_entry_id_fkey")
        drop_if_exists constraint(alternate_source, "#{alternate_source}_linked_entry_id_fkey")

        alter table(alternate_source) do
          modify :entry_id, references(blueprint.__schema__(:source), on_delete: :delete_all)
          modify :linked_entry_id, references(blueprint.__schema__(:source), on_delete: :delete_all)
        end
      end
    end
  end
end
