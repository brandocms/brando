defmodule Brando.Migrations.Brando.UpdateModuleEntryTemplateBinaryId do
  use Ecto.Migration
  import Ecto.Query

  def up do
    query =
      from(m in "content_modules",
        select: %{
          id: m.id,
          entry_template: m.entry_template
        },
        where: not is_nil(m.entry_template)
      )

    modules = Brando.repo().all(query)

    for module <- modules do
      updated_code =
        Regex.replace(~r/%{(\w+)}/, module.entry_template["code"], "{% ref refs.\\1 %}")

      updated_entry_template =
        Map.merge(module.entry_template, %{"id" => Ecto.UUID.generate(), "code" => updated_code})

      query =
        from(m in "content_modules",
          where: m.id == ^module.id,
          update: [
            set: [
              entry_template: ^updated_entry_template
            ]
          ]
        )

      Brando.repo().update_all(query, [])
    end
  end

  def down do
  end
end
