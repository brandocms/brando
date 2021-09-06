defmodule Brando.Repo.Migrations.ConvertModuleVarsToList do
  use Ecto.Migration
  import Ecto.Query

  def up do
    query = from m in "pages_modules", select: %{id: m.id, vars: m.vars}
    modules = Brando.repo().all(query)
    for module <- modules do
      # convert from string map to list of objects
      vars =
        module.vars
        |> Enum.map(fn
          {k, v} ->
            Map.put(v, "name", k)
          var ->
            var
        end)

      query =
        from(m in "pages_modules",
          where: m.id == ^module.id,
          update: [set: [vars: ^vars]]
        )

      Brando.repo().update_all(query, [])
    end
  end

  def down do

  end
end
