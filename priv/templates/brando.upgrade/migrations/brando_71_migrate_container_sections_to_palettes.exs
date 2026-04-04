defmodule Brando.Repo.Migrations.ContainerSectionsToPalettes do
  use Ecto.Migration
  import Ecto.Query

  def change do
    actions =
      for {table, data_field} <- list_villain_columns() do
        from(t in table,
          update: [
            set: [
              {^data_field,
               fragment(
                 "REPLACE(?::text, '\"section_id\":', '\"palette_id\":')::jsonb",
                 field(t, ^data_field)
               )}
            ]
          ]
        )
      end

    for action <- actions do
      Brando.repo().update_all(action, [])
    end
  end

  defp list_villain_columns do
    Brando.repo().all(
      from("columns",
        prefix: "information_schema",
        select: [:table_name, :column_name],
        where: [table_schema: "public"],
        where: fragment("data_type IN ('json', 'jsonb')")
      )
    )
    |> Enum.filter(&String.ends_with?(&1.column_name, "data"))
    |> Enum.reject(&(&1.table_name in ~w(revisions content_modules sites_globals pages_properties)))
    |> Enum.map(fn row -> {row.table_name, String.to_atom(row.column_name)} end)
  end
end
