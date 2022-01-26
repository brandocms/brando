defmodule Brando.Repo.Migrations.MigrateVillainModuleIds do
  use Ecto.Migration
  import Ecto.Query

  def change do
    # Add your own schemas to the reject list, if they were created AFTER this migration
    villain_schemas = Enum.reject(Brando.Villain.list_villains(), &(elem(&1, 0) in [
      Brando.Content.Template
      # your schemas here
    ]))

    actions =
      for {schema, fields} <- villain_schemas do
        Enum.map(fields, fn %{name: f} ->
          from(t in schema.__schema__(:source),
            update: [
              set: [
                {^f,
                 fragment("REPLACE(?::text, '\"id\":', '\"module_id\":')::jsonb", field(t, ^f))}
              ]
            ]
          )
        end)
      end
      |> List.flatten()

    for action <- actions do
      Brando.repo().update_all(action, [])
    end
  end
end
