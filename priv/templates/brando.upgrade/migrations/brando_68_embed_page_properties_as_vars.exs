defmodule Brando.Repo.Migrations.EmbedPagePropertiesAsVars do
  use Ecto.Migration
  import Ecto.Query

  def change do
    alter table(:pages) do
      add :vars, :jsonb
    end

    flush()

    query =
      from m in "pages_properties",
        select: %{
          id: m.id,
          key: m.key,
          label: m.label,
          type: m.type,
          data: m.data,
          page_id: m.page_id
        }

    props = Brando.repo().all(query)

    for prop <- props do
      query =
        from(m in "pages",
          where: m.id == ^prop.page_id,
          select: %{
            id: m.id,
            vars: m.vars
          }
        )

      page = Brando.repo().one(query)


      new_var =
        %{
          key: prop.key,
          label: prop.label,
          type: prop.type,
          important: true,
          value: prop.data["value"]
        }


      new_vars = [new_var|(page.vars || [])]

      query =
        from(m in "pages",
          where: m.id == ^prop.page_id,
          update: [set: [
            vars: ^new_vars
          ]]
        )

      Brando.repo().update_all(query, [])
    end

    flush()

    drop table(:pages_properties)
  end
end
