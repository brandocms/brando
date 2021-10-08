defmodule Brando.Repo.Migrations.ContainerSectionsToPalettes do
  use Ecto.Migration
  import Ecto.Query

  def change do
    villain_schemas = Enum.reject(Brando.Villain.list_villains(), &(elem(&1, 0) == Brando.Content.Template))

    actions =
      for {schema, fields} <- villain_schemas do
        Enum.map(fields, fn %{name: f} ->
          from(t in schema.__schema__(:source),
            update: [
              set: [
                {^f,
                 fragment("REPLACE(?::text, '\"section_id\":', '\"palette_id\":')::jsonb", field(t, ^f))}
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
