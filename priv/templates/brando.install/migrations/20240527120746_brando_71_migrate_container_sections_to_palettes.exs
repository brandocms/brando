defmodule Brando.Repo.Migrations.ContainerSectionsToPalettes do
  use Ecto.Migration
  import Ecto.Query

  def change do
    # Add your own schemas to the reject list, if they were created AFTER this migration
    villain_schemas =
      Enum.reject(
        Brando.Villain.list_blocks(),
        &(elem(&1, 0) in [
            Brando.Content.Template,
            Brando.Pages.Page,
            Brando.Pages.Fragment
            # your schemas here
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
        Enum.map(fields, fn %{name: f} ->
          from(t in schema.__schema__(:source),
            update: [
              set: [
                {^f,
                 fragment(
                   "REPLACE(?::text, '\"section_id\":', '\"palette_id\":')::jsonb",
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
