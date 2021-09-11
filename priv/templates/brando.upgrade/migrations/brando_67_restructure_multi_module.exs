defmodule Brando.Repo.Migrations.RestructureMultiModule do
  use Ecto.Migration
  import Ecto.Query

  def up do
    alter table(:content_modules) do
      add :entry_template, :jsonb
      add :wrapper_boolean, :boolean, default: false
    end

    flush()

    query =
      from m in "content_modules",
        select: %{
          id: m.id,
          name: m.name,
          namespace: m.namespace,
          help_text: m.help_text,
          class: m.class,
          code: m.code,
          svg: m.svg,
          multi: m.multi,
          wrapper: m.wrapper,
          vars: m.vars,
          refs: m.refs
      }, where: m.multi == true

    modules = Brando.repo().all(query)

    for module <- modules do
      entry_template = Map.drop(module, [:multi, :wrapper, :id])
      wrapper_code = module.wrapper

      query =
        from(m in "content_modules",
          where: m.id == ^module.id,
          update: [set: [
            entry_template: ^entry_template,
            code: ^wrapper_code,
            wrapper_boolean: true,
            vars: [],
            refs: []
          ]]
        )

      Brando.repo().update_all(query, [])
    end

    flush()

    alter table(:content_modules) do
      remove :wrapper
      remove :multi
    end

    flush()

    rename table(:content_modules), :wrapper_boolean, to: :wrapper
  end

  def down do
  end
end
