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

    # Add your own schemas to the reject list, if they were created AFTER this migration
    villain_schemas =
      Enum.reject(
        Brando.Villain.list_villains(),
        &(elem(&1, 0) in [
            Brando.Content.Template,
            Brando.Pages.Page,
            Brando.Pages.Fragment
            # your schemas here
          ])
      )

    # since these are old now, we use :data as field name (since list_villains will return :blocks for these)
    villain_schemas =
      villain_schemas ++
        [
          {Brando.Pages.Page, [%{name: :data}]},
          {Brando.Pages.Fragment, [%{name: :data}]}
        ]

    actions =
      for {schema, fields} <- villain_schemas do
        Enum.map(fields, fn
          {_, f, _} ->
            from(t in schema.__schema__(:source),
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

          %{name: f} ->
            source =
              if schema.__schema__(:source) == "pages",
                do: "pages_pages",
                else: schema.__schema__(:source)

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
        end)
      end
      |> List.flatten()

    for action <- actions do
      Brando.repo().update_all(action, [])
    end
  end
end
