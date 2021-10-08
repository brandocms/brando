defmodule Brando.Migrations.FragmentsDataJSONBRenameTemplatesToModules do
  use Ecto.Migration
  import Ecto.Query

  def change do
    execute """
    ALTER TABLE pages_fragments
      ALTER COLUMN data
      SET DATA TYPE jsonb
      USING data::jsonb;
    """

    flush()

    villain_schemas = Enum.reject(Brando.Villain.list_villains(), &(elem(&1, 0) == Brando.Content.Template))

    actions =
      for {schema, fields} <- villain_schemas do
        Enum.map(fields, fn
          {_, f, _} ->
            from t in schema.__schema__(:source),
              update: [set: [{^f, fragment("REPLACE(?::text, '\"type\": \"template\"', '\"type\": \"module\"')::jsonb", field(t, ^f))}]]

              %{name: f} ->
                source = if schema.__schema__(:source) == "pages", do: "pages_pages", else: schema.__schema__(:source)
                from t in source,
                  update: [set: [{^f, fragment("REPLACE(?::text, '\"type\": \"template\"', '\"type\": \"module\"')::jsonb", field(t, ^f))}]]
        end)
      end
      |> List.flatten()

    for action <- actions do
      Brando.repo().update_all(action, [])
    end
  end
end
