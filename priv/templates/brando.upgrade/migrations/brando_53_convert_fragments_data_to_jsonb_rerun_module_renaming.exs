defmodule Brando.Migrations.FragmentsDataJSONBRenameTemplatesToModules do
  use Ecto.Migration
  import Ecto.Query

  alias Brando.Migration.Introspect

  def change do
    execute """
    ALTER TABLE pages_fragments
      ALTER COLUMN data
      SET DATA TYPE jsonb
      USING data::jsonb;
    """

    flush()

    villain_schemas =
      Enum.reject(
        Brando.Content.Blocks.list_blocks(),
        &(elem(&1, 0) in [
            Brando.Content.Template,
            Brando.Pages.Page,
            Brando.Pages.Fragment
          ])
      )

    # since these are old now, we use :data as field name (since list_blocks will return :blocks for these)
    villain_schemas =
      villain_schemas ++
        [
          {Brando.Pages.Page, [%{name: :data}]},
          {Brando.Pages.Fragment, [%{name: :data}]}
        ]

    actions =
      for {schema, fields} <- villain_schemas do
        Enum.flat_map(fields, fn
          {_, f, _} ->
            rename_modules(schema.__schema__(:source), f)

          %{name: f} ->
            source =
              if schema.__schema__(:source) == "pages",
                do: "pages_pages",
                else: schema.__schema__(:source)

            rename_modules(source, f)
        end)
      end
      |> List.flatten()

    for action <- actions do
      Brando.Repo.update_all(action, [])
    end
  end

  # The schemas come from the application's current code: on a database
  # migrated from scratch, their tables are created by later migrations
  defp rename_modules(source, f) do
    if Introspect.column_exists?(source, f) do
      [
        from(t in source,
          update: [
            set: [
              {^f,
               fragment(
                 "REPLACE(?::text, '\"type\": \"template\"', '\"type\": \"module\"')::jsonb",
                 field(t, ^f)
               )}
            ]
          ]
        )
      ]
    else
      []
    end
  end
end
