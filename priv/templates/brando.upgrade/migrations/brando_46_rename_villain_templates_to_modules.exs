defmodule Brando.Migrations.RenameTemplatesToModules do
  use Ecto.Migration

  def change do
    villain_schemas = Brando.Villain.list_villains()

    actions = for {schema, fields} <- villain_schemas do
      replace_string =
        fields
        |> Enum.reduce([], fn ({_, f, _}, acc) -> [~s<#{f} = REPLACE(#{f}::text, '"type": "template"', '"type": "module"')::jsonb>|acc] end)
        |> Enum.join(",\n")

      """
      UPDATE
        #{schema.__schema__(:source)}
      SET
        #{replace_string}
      """
    end

    for action <- actions do
      execute action
      flush()
    end

    flush()

    rename table(:pages_templates), to: table(:pages_modules)
  end
end
