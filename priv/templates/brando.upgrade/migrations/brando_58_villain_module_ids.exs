defmodule Brando.Repo.Migrations.MigrateVillainModuleIds do
  use Ecto.Migration
  import Ecto.Query

  def change do
    for {table, data_field} <- list_villain_columns() do
      execute("""
      UPDATE #{table}
      SET #{data_field} = REPLACE(#{data_field}::text, '"id":', '"module_id":')::jsonb
      WHERE #{data_field} IS NOT NULL
      """)
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
    |> Enum.map(&{&1.table_name, &1.column_name})
  end
end
