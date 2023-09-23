defmodule Brando.Repo.Migrations.EncodeModuleSvgToBase64 do
  use Ecto.Migration
  import Ecto.Query

  def change do
    query =
      from(m in "content_modules",
        select: %{
          id: m.id,
          svg: m.svg
        },
        where: not is_nil(m.svg)
      )

    modules = Brando.repo().all(query)

    for module <- modules do
      if String.starts_with?(module.svg, "<svg") do
        updated_svg = Base.encode64(module.svg, padding: false)

        query =
          from(m in "content_modules",
            where: m.id == ^module.id,
            update: [
              set: [
                svg: ^updated_svg
              ]
            ]
          )

        Brando.repo().update_all(query, [])
      end
    end
  end
end
