defmodule Brando.Repo.Migrations.MigrateOldModules do
  use Ecto.Migration
  import Ecto.Query

  def up do
    alter table("content_modules") do
      add :type, :text, default: "liquid"
      add :parent_id, references(:content_modules, on_delete: :delete_all)
    end

    flush()

    ## move entry templates to own module with parent_id reference

    query =
      from(m in "content_modules",
        select: %{
          id: m.id,
          entry_template: m.entry_template,
          name: m.name,
          namespace: m.namespace
        },
        order_by: [desc: m.id]
      )

    entries = Brando.repo().all(query)
    Enum.map(entries, &extract_entry_template/1)

    alter table("content_modules") do
      remove :entry_template
    end

    flush()

    query =
      from(m in "content_modules",
        select: %{id: m.id, vars: m.vars},
        order_by: [desc: m.id]
      )

    entries = Brando.repo().all(query)

    for entry <- entries do
      process_vars(:module_id, entry.id, 1, entry.vars)
    end

    alter table("content_modules") do
      remove :vars
    end

    query =
      from(m in "content_modules",
        select: %{id: m.id, refs: m.refs},
        where: not is_nil(m.refs),
        order_by: [desc: m.id]
      )

    entries = Brando.repo().all(query)

    for entry <- entries do
      {table_template_id, new_refs} =
        Enum.reduce(entry.refs, {nil, []}, fn
          %{"data" => %{"type" => "table"}} = ref, {_, refs} ->
            # create a new table template
            table_template = %{
              name: "Table template",
              inserted_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now(),
              creator_id: 1
            }

            {_, [%{id: table_template_id}]} =
              Brando.repo().insert_all("content_table_templates", [table_template],
                returning: [:id]
              )

            old_cols = get_in(ref, ["data", "data", "template_row", "cols"])
            process_vars(:table_template_id, table_template_id, 1, old_cols)

            # we don't include this ref.
            {table_template_id, refs}

          ref, {table_template_id, refs} ->
            updated_ref =
              ref
              |> put_in(["id"], Ecto.UUID.generate())
              |> put_in(["data", "uid"], Ecto.UUID.generate())
              |> put_in(["data", "active"], !ref["data"]["hidden"])
              |> pop_in(["data", "hidden"])
              |> elem(1)

            {table_template_id, refs ++ [updated_ref]}
        end)

      update_args =
        Keyword.new([
          {:refs, new_refs},
          {:table_template_id, table_template_id}
        ])

      query =
        from(m in "content_modules",
          where: m.id == ^entry.id,
          update: [set: ^update_args]
        )

      Brando.repo().update_all(query, [])
    end
  end

  def down do
  end

  defp fix_refs(refs) do
    Enum.reduce(refs, [], fn
      ref, acc ->
        updated_ref =
          ref
          |> put_in([Access.key("id")], Ecto.UUID.generate())
          |> put_in([Access.key("data"), Access.key("uid")], Brando.Utils.generate_uid())
          |> put_in([Access.key("data"), Access.key("active")], !ref["data"]["hidden"])
          |> pop_in([Access.key("data"), Access.key("hidden")])
          |> elem(1)

        acc ++ List.wrap(updated_ref)
    end)
  end

  defp extract_entry_template(%{entry_template: entry_template} = entry)
       when not is_nil(entry_template) do
    new_module =
      %{
        type: "liquid",
        name: "#{entry.name} [Entry Template]",
        namespace: entry.namespace,
        parent_id: entry.id,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        vars: Map.get(entry_template, "vars"),
        refs: Map.get(entry_template, "refs") |> fix_refs(),
        class: Map.get(entry_template, "class"),
        code: Map.get(entry_template, "code")
      }

    Brando.repo().insert_all("content_modules", [new_module])
  end

  defp extract_entry_template(entry), do: entry

  defp process_vars(_, _, _, nil), do: nil
  defp process_vars(_, _, _, []), do: nil

  defp process_vars(fk_name, fk_value, creator_id, vars) do
    for var <- vars do
      base_var = build_var(var, fk_name, fk_value, creator_id)

      new_var =
        case var do
          %{"type" => "color"} ->
            Map.merge(base_var, %{
              value: get_in(var, ["value"]),
              color_picker: get_in(var, ["picker"]),
              color_opacity: get_in(var, ["opacity"]),
              palette_id: get_in(var, ["palette_id"])
            })

          %{"type" => "image"} ->
            Map.merge(base_var, %{
              image_id: get_in(var, ["value_id"])
            })

          %{"type" => "file"} ->
            Map.merge(base_var, %{
              file_id: get_in(var, ["value_id"])
            })

          %{"type" => "boolean"} ->
            Map.merge(base_var, %{
              value_boolean: get_in(var, ["value"])
            })

          %{"type" => "select"} ->
            Map.merge(base_var, %{
              value: get_in(var, ["value"]),
              options: get_in(var, ["options"])
            })

          _ ->
            Map.merge(base_var, %{
              value: get_in(var, ["value"])
            })
        end

      new_var =
        Map.merge(new_var, %{
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        })

      Brando.repo().insert_all("content_vars", [new_var])
    end
  end

  def build_var(var, fk_name, fk_value, creator_id) do
    %{
      type: get_in(var, ["type"]),
      important: get_in(var, ["important"]),
      instructions: get_in(var, ["instructions"]),
      key: get_in(var, ["key"]),
      label: get_in(var, ["label"]),
      placeholder: get_in(var, ["placeholder"]),
      creator_id: creator_id
    }
    |> Map.put(fk_name, fk_value)
  end
end
