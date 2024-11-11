defmodule Brando.Migrations.Brando.MigrateVillainRefsToTags do
  use Ecto.Migration
  import Ecto.Query

  def up do
    query =
      from m in "content_modules",
        select: %{
          id: m.id,
          code: m.code,
        }

    modules = Brando.Repo.all(query)

    for module <- modules do
      updated_code = Regex.replace ~r/%{(\w+)}/, module.code, "{% ref refs.\\1 %}"

      query =
        from(m in "content_modules",
          where: m.id == ^module.id,
          update: [set: [
            code: ^updated_code
          ]]
        )

      Brando.Repo.update_all(query, [])
    end
  end

  def down do

  end
end
