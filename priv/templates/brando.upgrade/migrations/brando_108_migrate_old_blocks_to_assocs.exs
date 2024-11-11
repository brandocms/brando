defmodule Brando.Repo.Migrations.MigrateOldBlocksToAssocs do
  use Ecto.Migration
  import Ecto.Query

  def up do
    villain_schemas = Brando.Villain.list_blocks()

    for {schema, _} <- villain_schemas do
      table = schema.__schema__(:source)

      data_fields =
        Brando.Repo.all(
          from("columns",
            prefix: "information_schema",
            select: [:column_name, :data_type],
            where: [table_name: ^table]
          )
        )
        |> Enum.filter(fn row ->
          row[:data_type] == "jsonb" && String.ends_with?(row[:column_name], "data")
        end)

      for %{column_name: data_field_string} <- data_fields do
        data_field = String.to_atom(data_field_string)

        new_block_rel =
          data_field_string
          |> String.replace("_data", "_blocks")
          |> String.replace("data", "blocks")

        query =
          from(m in schema.__schema__(:source),
            select: %{id: m.id, data: field(m, ^data_field)},
            where: not is_nil(field(m, ^data_field)),
            order_by: [desc: m.id]
          )

        entries = Brando.Repo.all(query)

        for entry <- entries do
          parse_block_data(schema, entry, Map.get(entry, data_field), new_block_rel)
        end
      end
    end

    query =
      from(m in "content_blocks",
        select: %{id: m.id, refs: m.refs, uid: m.uid, creator_id: m.creator_id},
        where: not is_nil(m.refs),
        order_by: [desc: m.id]
      )

    entries = Brando.Repo.all(query)

    for entry <- entries do
      # strip table refs and add them as table_rows in the block
      new_refs =
        Enum.reduce(entry.refs, [], fn
          %{"data" => %{"type" => "table"}} = ref, acc ->
            rows = get_in(ref, ["data", "data", "rows"])

            # create a new content_table_rows for each row
            Enum.map(rows, fn
              row ->
                table_row = %{
                  block_id: entry.id,
                  inserted_at: DateTime.utc_now(),
                  updated_at: DateTime.utc_now()
                }

                {_, [%{id: table_row_id}]} =
                  Brando.Repo.insert_all("content_table_rows", [table_row], returning: [:id])

                old_cols = get_in(row, ["cols"])
                process_vars(:table_row_id, table_row_id, entry.creator_id, old_cols)

                # skip the table ref..
                acc
            end)

            acc

          ref, acc ->
            acc ++ [ref]
        end)

      update_args = Keyword.new([{:refs, new_refs}])

      query =
        from(m in "content_blocks",
          where: m.id == ^entry.id,
          update: [set: ^update_args]
        )

      Brando.Repo.update_all(query, [])
    end
  end

  def down do
  end

  def parse_block_data(schema, entry, blocks, new_block_rel) when is_list(blocks) do
    for {block, idx} <- Enum.with_index(blocks) do
      process_block(block, idx, nil, schema, entry.id, new_block_rel)
    end
  end

  defp process_block(block, idx, parent_id, schema, entry_id, new_block_rel \\ "blocks") do
    table_name = schema.__schema__(:source)
    join_source = Enum.join([table_name, new_block_rel], "_")
    join_schema = Module.concat([schema, Macro.camelize(new_block_rel)])

    case block do
      %{"type" => "container"} = container ->
        new_container = %{
          type: "container",
          anchor: get_in(container, ["data", "target_id"]),
          palette_id: get_in(container, ["data", "palette_id"]),
          parent_id: parent_id,
          multi: false,
          uid: Map.get(container, "uid"),
          description: get_in(container, ["data", "description"]),
          active: !Map.get(container, "hidden", false),
          collapsed: Map.get(container, "collapsed"),
          datasource: get_in(container, ["data", "datasource"]) || false,
          refs: fix_refs(get_in(container, ["data", "refs"]) || []),
          source: to_string(join_schema),
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          sequence: parent_id && idx
        }

        # repo insert block
        {_, [%{id: container_id}]} =
          Brando.Repo.insert_all("content_blocks", [new_container], returning: [:id])

        # only insert to join table if we have no parent
        unless new_container.parent_id do
          Brando.Repo.insert_all(join_source, [
            %{
              entry_id: entry_id,
              block_id: container_id,
              sequence: idx
            }
          ])
        end

        # now process blocks with container_id as parent.
        c_blocks = get_in(container, ["data", "blocks"])

        for {c_block, c_block_idx} <- Enum.with_index(c_blocks) do
          process_block(c_block, c_block_idx, container_id, schema, entry_id)
        end

      %{"type" => "fragment", "data" => %{"fragment_id" => fragment_id}} = fragment_block ->
        # multi with entries
        new_block = %{
          type: "fragment",
          multi: false,
          parent_id: parent_id,
          uid: Map.get(fragment_block, "uid"),
          description: Map.get(fragment_block, "description"),
          active: !Map.get(fragment_block, "hidden", false),
          collapsed: Map.get(fragment_block, "collapsed"),
          fragment_id: fragment_id,
          source: to_string(join_schema),
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          sequence: parent_id && idx
        }

        # repo insert block
        {_, [%{id: block_id}]} =
          Brando.Repo.insert_all("content_blocks", [new_block], returning: [:id])

        unless new_block.parent_id do
          Brando.Repo.insert_all(join_source, [
            %{
              entry_id: entry_id,
              block_id: block_id,
              sequence: idx
            }
          ])
        end

      %{"type" => "module", "data" => %{"multi" => true}} = module ->
        # multi with entries
        new_block = %{
          type: "module",
          multi: true,
          parent_id: parent_id,
          uid: Map.get(module, "uid"),
          description: Map.get(module, "description"),
          active: !Map.get(module, "hidden", false),
          collapsed: Map.get(module, "collapsed"),
          module_id: get_in(module, ["data", "module_id"]),
          datasource: get_in(module, ["data", "datasource"]) || false,
          refs: fix_refs(get_in(module, ["data", "refs"]) || []),
          source: to_string(join_schema),
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          sequence: parent_id && idx
        }

        # repo insert block
        {_, [%{id: block_id}]} =
          Brando.Repo.insert_all("content_blocks", [new_block], returning: [:id])

        unless new_block.parent_id do
          Brando.Repo.insert_all(join_source, [
            %{
              entry_id: entry_id,
              block_id: block_id,
              sequence: idx
            }
          ])
        end

        # insert entries
        entries = get_in(module, ["data", "entries"])

        for {entry_block, entry_idx} <- Enum.with_index(entries) do
          process_block(entry_block, entry_idx, block_id, schema, entry_id)
        end

      %{"type" => module_or_module_entry} = module
      when module_or_module_entry in ["module", "module_entry"] ->
        module_id =
          if module_or_module_entry == "module" do
            get_in(module, ["data", "module_id"])
          else
            # module_entry has no module_id -- we must grab it the module who has parent_id as parent_id
            # first we get the parent block
            query = from(m in "content_blocks", where: m.id == ^parent_id, select: m.module_id)
            parent_module_id = Brando.Repo.one(query)

            query =
              from(m in "content_modules", where: m.parent_id == ^parent_module_id, select: m.id)

            Brando.Repo.one(query)
          end

        new_block = %{
          type: module_or_module_entry,
          multi: false,
          uid: Map.get(module, "uid"),
          parent_id: parent_id,
          description: Map.get(module, "description"),
          active: !Map.get(module, "hidden", false),
          collapsed: Map.get(module, "collapsed"),
          module_id: module_id,
          datasource: get_in(module, ["data", "datasource"]) || false,
          refs: fix_refs(get_in(module, ["data", "refs"]) || []),
          source: to_string(join_schema),
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          sequence: parent_id && idx
        }

        # repo insert block
        {_, [%{id: block_id}]} =
          Brando.Repo.insert_all("content_blocks", [new_block], returning: [:id])

        # only insert to join table if we have no parent
        unless new_block.parent_id do
          Brando.Repo.insert_all(join_source, [
            %{
              entry_id: entry_id,
              block_id: block_id,
              sequence: idx
            }
          ])
        end

        # TODO: build "datasource_selected_ids" as relations
        datasource_selected_ids = get_in(module, ["data", "datasource_selected_ids"])

        if datasource_selected_ids do
          process_datasource(block_id, datasource_selected_ids)
        end

        vars = get_in(module, ["data", "vars"])

        if vars do
          process_vars(block_id, vars)
        end

      unknown_block ->
        raise """

        got unknown block in migration for:

        Schema....: #{inspect(schema)}
        Entry id..: #{inspect(entry_id)}

        #{inspect(unknown_block, pretty: true)}

        Make sure you convert old style free standing blocks to modules
        before migrating.

        """
    end
  end

  defp fix_refs(refs) do
    Enum.map(refs, fn ref ->
      ref
      |> put_in([Access.key("id")], Ecto.UUID.generate())
      |> put_in([Access.key("data"), Access.key("uid")], Brando.Utils.generate_uid())
      |> put_in([Access.key("data"), Access.key("active")], !ref["data"]["hidden"])
      |> pop_in([Access.key("data"), Access.key("hidden")])
      |> elem(1)
    end)
  end

  defp process_datasource(block_id, datasource_selected_ids) do
    for {id, idx} <- Enum.with_index(datasource_selected_ids) do
      block_identifier =
        %{
          block_id: block_id,
          identifier_id: id,
          sequence: idx
        }

      Brando.Repo.insert_all("content_block_identifiers", [block_identifier])
    end
  end

  defp process_vars(block_id, vars) do
    for var <- vars do
      new_var =
        case var do
          %{"type" => "color"} ->
            base_var = build_var(var, block_id)

            Map.merge(base_var, %{
              value: get_in(var, ["value"]),
              color_picker: get_in(var, ["picker"]),
              color_opacity: get_in(var, ["opacity"]),
              palette_id: get_in(var, ["palette_id"])
            })

          %{"type" => "image"} ->
            base_var = build_var(var, block_id)

            Map.merge(base_var, %{
              image_id: get_in(var, ["value_id"])
            })

          %{"type" => "file"} ->
            base_var = build_var(var, block_id)

            Map.merge(base_var, %{
              file_id: get_in(var, ["value_id"])
            })

          %{"type" => "boolean"} ->
            base_var = build_var(var, block_id)

            Map.merge(base_var, %{
              value_boolean: get_in(var, ["value"])
            })

          %{"type" => "select"} ->
            base_var = build_var(var, block_id)

            Map.merge(base_var, %{
              value: get_in(var, ["value"]),
              options: get_in(var, ["options"])
            })

          _ ->
            base_var = build_var(var, block_id)

            Map.merge(base_var, %{
              value: get_in(var, ["value"])
            })
        end

      new_var =
        Map.merge(new_var, %{
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        })

      Brando.Repo.insert_all("content_vars", [new_var])
    end
  end

  def build_var(var, block_id) do
    %{
      type: get_in(var, ["type"]),
      important: get_in(var, ["important"]),
      instructions: get_in(var, ["instructions"]),
      key: get_in(var, ["key"]),
      label: get_in(var, ["label"]),
      placeholder: get_in(var, ["placeholder"]),
      block_id: block_id
    }
  end

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

      Brando.Repo.insert_all("content_vars", [new_var])
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
