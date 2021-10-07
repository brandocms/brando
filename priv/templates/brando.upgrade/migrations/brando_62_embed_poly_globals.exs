defmodule Brando.Repo.Migrations.ConvertGlobalsDataValueToValue do
  use Ecto.Migration
  import Ecto.Query

  def up do
    alter table(:sites_global_categories) do
      add :globals, :jsonb
    end

    flush()

    query =
      from c in "sites_global_categories",
        select: %{
          id: c.id
        }

    categories = Brando.repo.all(query)

    for category <- categories do
      globals_query = from g in "sites_globals",
        select: %{
            id: g.id,
            key: g.key,
            label: g.label,
            type: g.type,
            data: g.data,
            global_category_id: g.global_category_id
          },
          where: g.global_category_id == ^category.id

      globals = Brando.repo.all(globals_query)
      category = Map.put(category, :globals, globals)

      new_category = process_category(category)

      update_query =
        from c in "sites_global_categories",
          where: c.id == ^category.id,
          update: [set: [globals: ^new_category.globals]]

      Brando.repo().update_all(update_query, [])
    end

    drop table(:sites_globals)
  end

  def process_category(%{globals: globals} = category) do
    %{category | globals: process_globals(globals)}
  end

  def process_globals(globals) do
    for global <- globals do
      process_global(global)
    end
  end

  def process_global(%{type: "boolean", data: %{"value" => value}} = global) do
    %{
      type: "boolean",
      value: value,
      label: global.label,
      key: global.key
    }
  end

  def process_global(%{type: "html", data: %{"value" => value}} = global) do
    %{
      type: "html",
      value: value,
      label: global.label,
      key: global.key
    }
  end

  def process_global(%{type: "text", data: %{"value" => value}} = global) do
    %{
      type: "text",
      value: value,
      label: global.label,
      key: global.key
    }
  end

  def process_global(%{type: "string", data: %{"value" => value}} = global) do
    %{
      type: "string",
      value: value,
      label: global.label,
      key: global.key
    }
  end

  def process_global(%{type: "datetime", data: %{"value" => value}} = global) do
    {:ok, dt, _} = DateTime.from_iso8601(value)
    %{
      type: "datetime",
      value: dt,
      label: global.label,
      key: global.key
    }
  end

  def process_global(%{type: "color", data: %{"value" => value}} = global) do
    %{
      type: "color",
      value: value,
      label: global.label,
      key: global.key
    }
  end

  def down do

  end
end
