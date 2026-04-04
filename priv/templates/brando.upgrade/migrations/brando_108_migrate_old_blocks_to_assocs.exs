defmodule Brando.Repo.Migrations.MigrateOldBlocksToAssocs do
  use Ecto.Migration
  import Ecto.Query

  @legacy_block_types ~w(text markdown image picture video divider header blockquote datasource map svg html)

  def up do
    # First, ensure we have a wrapper module for legacy free-standing blocks
    wrapper_module_id = ensure_legacy_wrapper_module()

    for {table, data_field, new_block_rel} <- list_villain_columns() do
      query =
        from(m in table,
          select: %{id: m.id, data: field(m, ^data_field)},
          where: not is_nil(field(m, ^data_field)),
          order_by: [desc: m.id]
        )

      entries = Brando.repo().all(query)

      for entry <- entries do
        parse_block_data(table, entry, entry.data, new_block_rel, wrapper_module_id)
      end
    end

    # Process refs: strip table refs and convert to table_rows
    query =
      from(m in "content_blocks",
        select: %{id: m.id, refs: m.refs, uid: m.uid, creator_id: m.creator_id},
        where: not is_nil(m.refs),
        order_by: [desc: m.id]
      )

    entries = Brando.repo().all(query)

    for entry <- entries do
      new_refs =
        Enum.reduce(entry.refs, [], fn
          %{"data" => %{"type" => "table"}} = ref, acc ->
            rows = get_in(ref, ["data", "data", "rows"])

            Enum.map(rows || [], fn row ->
              table_row = %{
                block_id: entry.id,
                inserted_at: DateTime.utc_now(),
                updated_at: DateTime.utc_now()
              }

              {_, [%{id: table_row_id}]} =
                Brando.repo().insert_all("content_table_rows", [table_row], returning: [:id])

              old_cols = get_in(row, ["cols"])
              process_vars(:table_row_id, table_row_id, entry.creator_id, old_cols)
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

      Brando.repo().update_all(query, [])
    end
  end

  def down do
  end

  def parse_block_data(table_name, entry, blocks, new_block_rel, wrapper_module_id)
      when is_list(blocks) do
    for {block, idx} <- Enum.with_index(blocks) do
      process_block(block, idx, nil, table_name, entry.id, new_block_rel, wrapper_module_id)
    end
  end

  defp process_block(
         block,
         idx,
         parent_id,
         table_name,
         entry_id,
         new_block_rel \\ "blocks",
         wrapper_module_id \\ nil
       ) do
    join_source = Enum.join([table_name, new_block_rel], "_")

    case block do
      # Legacy free-standing block types — wrap in a module block with content as ref
      %{"type" => type} = legacy_block when type in @legacy_block_types ->
        ref_data = build_legacy_ref_data(legacy_block)

        ref = %{
          "name" => "content",
          "id" => Ecto.UUID.generate(),
          "data" =>
            Map.merge(ref_data, %{
              "uid" => Brando.Utils.generate_uid(),
              "active" => true
            })
        }

        new_block = %{
          type: "module",
          multi: false,
          parent_id: parent_id,
          uid: Map.get(legacy_block, "uid") || Brando.Utils.generate_uid(),
          active: !Map.get(legacy_block, "hidden", false),
          collapsed: Map.get(legacy_block, "collapsed"),
          module_id: wrapper_module_id,
          datasource: false,
          refs: [ref],
          source: join_source,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          sequence: parent_id && idx
        }

        {_, [%{id: block_id}]} =
          Brando.repo().insert_all("content_blocks", [new_block], returning: [:id])

        unless new_block.parent_id do
          Brando.repo().insert_all(join_source, [
            %{entry_id: entry_id, block_id: block_id, sequence: idx}
          ])
        end

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
          source: join_source,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          sequence: parent_id && idx
        }

        {regular_refs, list_refs} = fix_refs(get_in(container, ["data", "refs"]) || [])
        new_container = Map.put(new_container, :refs, regular_refs)

        {_, [%{id: container_id}]} =
          Brando.repo().insert_all("content_blocks", [new_container], returning: [:id])

        process_list_refs(container_id, list_refs)

        unless new_container.parent_id do
          Brando.repo().insert_all(join_source, [
            %{entry_id: entry_id, block_id: container_id, sequence: idx}
          ])
        end

        c_blocks = get_in(container, ["data", "blocks"])

        for {c_block, c_block_idx} <- Enum.with_index(c_blocks || []) do
          process_block(
            c_block,
            c_block_idx,
            container_id,
            table_name,
            entry_id,
            new_block_rel,
            wrapper_module_id
          )
        end

      %{"type" => "fragment", "data" => %{"fragment_id" => fragment_id}} = fragment_block ->
        new_block = %{
          type: "fragment",
          multi: false,
          parent_id: parent_id,
          uid: Map.get(fragment_block, "uid"),
          description: Map.get(fragment_block, "description"),
          active: !Map.get(fragment_block, "hidden", false),
          collapsed: Map.get(fragment_block, "collapsed"),
          fragment_id: fragment_id,
          source: join_source,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          sequence: parent_id && idx
        }

        {_, [%{id: block_id}]} =
          Brando.repo().insert_all("content_blocks", [new_block], returning: [:id])

        unless new_block.parent_id do
          Brando.repo().insert_all(join_source, [
            %{entry_id: entry_id, block_id: block_id, sequence: idx}
          ])
        end

      %{"type" => "module", "data" => %{"multi" => true}} = module ->
        {regular_refs, list_refs} = fix_refs(get_in(module, ["data", "refs"]) || [])

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
          refs: regular_refs,
          source: join_source,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          sequence: parent_id && idx
        }

        {_, [%{id: block_id}]} =
          Brando.repo().insert_all("content_blocks", [new_block], returning: [:id])

        process_list_refs(block_id, list_refs)

        unless new_block.parent_id do
          Brando.repo().insert_all(join_source, [
            %{entry_id: entry_id, block_id: block_id, sequence: idx}
          ])
        end

        entries = get_in(module, ["data", "entries"])

        for {entry_block, entry_idx} <- Enum.with_index(entries || []) do
          process_block(
            entry_block,
            entry_idx,
            block_id,
            table_name,
            entry_id,
            new_block_rel,
            wrapper_module_id
          )
        end

      %{"type" => module_or_module_entry} = module
      when module_or_module_entry in ["module", "module_entry"] ->
        module_id =
          if module_or_module_entry == "module" do
            get_in(module, ["data", "module_id"])
          else
            query = from(m in "content_blocks", where: m.id == ^parent_id, select: m.module_id)
            parent_module_id = Brando.repo().one(query)

            query =
              from(m in "content_modules", where: m.parent_id == ^parent_module_id, select: m.id)

            Brando.repo().one(query)
          end

        {regular_refs, list_refs} = fix_refs(get_in(module, ["data", "refs"]) || [])

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
          refs: regular_refs,
          source: join_source,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          sequence: parent_id && idx
        }

        {_, [%{id: block_id}]} =
          Brando.repo().insert_all("content_blocks", [new_block], returning: [:id])

        process_list_refs(block_id, list_refs)

        unless new_block.parent_id do
          Brando.repo().insert_all(join_source, [
            %{entry_id: entry_id, block_id: block_id, sequence: idx}
          ])
        end

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

        Table.....: #{inspect(table_name)}
        Entry id..: #{inspect(entry_id)}

        #{inspect(unknown_block, pretty: true)}

        Make sure you convert old style free standing blocks to modules
        before migrating.

        """
    end
  end

  # Build ref data for legacy block types
  defp build_legacy_ref_data(%{"type" => "text", "data" => data}),
    do: %{"type" => "text", "data" => data}

  defp build_legacy_ref_data(%{"type" => "markdown", "data" => data}) do
    text = Map.get(data, "text", "")

    html =
      case Earmark.as_html(text) do
        {:ok, converted, _} -> converted
        _ -> text
      end

    %{"type" => "text", "data" => %{"text" => html, "type" => "paragraph"}}
  end

  defp build_legacy_ref_data(%{"type" => "image", "data" => data}) do
    %{
      "type" => "picture",
      "data" =>
        Map.merge(
          %{
            "path" => Map.get(data, "url", ""),
            "width" => Map.get(data, "width"),
            "height" => Map.get(data, "height"),
            "sizes" => %{},
            "title" => Map.get(data, "title", ""),
            "credits" => Map.get(data, "credits", ""),
            "alt" => Map.get(data, "alt")
          },
          Map.take(data, ["focal", "cdn", "dominant_color"])
        )
    }
  end

  defp build_legacy_ref_data(%{"type" => "picture", "data" => data}),
    do: %{"type" => "picture", "data" => data}

  defp build_legacy_ref_data(%{"type" => "video", "data" => data}),
    do: %{"type" => "video", "data" => data}

  defp build_legacy_ref_data(%{"type" => "header", "data" => data}),
    do: %{"type" => "header", "data" => data}

  defp build_legacy_ref_data(%{"type" => "divider", "data" => _data}),
    do: %{"type" => "text", "data" => %{"text" => "---", "type" => "paragraph"}}

  defp build_legacy_ref_data(%{"type" => "blockquote", "data" => data}),
    do: %{
      "type" => "text",
      "data" => %{"text" => "> #{Map.get(data, "text", "")}", "type" => "paragraph"}
    }

  defp build_legacy_ref_data(%{"type" => _type, "data" => data}),
    do: %{"type" => "text", "data" => %{"text" => Map.get(data, "text", ""), "type" => "paragraph"}}

  defp ensure_legacy_wrapper_module do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Check if wrapper module already exists
    existing =
      Brando.repo().one(
        from(m in "content_modules",
          where: m.namespace == "migration" and m.class == "legacy-content",
          select: m.id
        )
      )

    if existing do
      existing
    else
      module_refs = [
        %{
          "name" => "content",
          "data" => %{
            "type" => "text",
            "data" => %{"text" => "", "type" => "paragraph"}
          }
        }
      ]

      module_code = "{% for ref in refs %}{{ ref.content }}{% endfor %}"

      {_, [%{id: id}]} =
        Brando.repo().insert_all(
          "content_modules",
          [
            %{
              name: "Legacy Content Wrapper",
              namespace: "migration",
              class: "legacy-content",
              help_text: "Auto-generated module for wrapping legacy villain blocks during migration",
              code: module_code,
              refs: module_refs,
              wrapper: false,
              datasource: false,
              type: "liquid",
              sequence: 999,
              inserted_at: now,
              updated_at: now
            }
          ],
          returning: [:id]
        )

      id
    end
  end

  defp fix_refs(refs) do
    {regular_refs, list_refs} =
      Enum.split_with(refs, fn ref ->
        get_in(ref, ["data", "type"]) != "list"
      end)

    fixed_regular =
      Enum.map(regular_refs, fn ref ->
        ref
        |> put_in([Access.key("id")], Ecto.UUID.generate())
        |> put_in([Access.key("data"), Access.key("uid")], Brando.Utils.generate_uid())
        |> put_in([Access.key("data"), Access.key("active")], !ref["data"]["hidden"])
        |> pop_in([Access.key("data"), Access.key("hidden")])
        |> elem(1)
      end)

    {fixed_regular, list_refs}
  end

  # Create table rows from list refs after block insertion
  defp process_list_refs(_block_id, []), do: :ok

  defp process_list_refs(block_id, list_refs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    for list_ref <- list_refs do
      list_data = get_in(list_ref, ["data", "data"]) || %{}
      rows = (is_map(list_data) && list_data["rows"]) || []

      for {row, idx} <- Enum.with_index(rows) do
        {_, [%{id: row_id}]} =
          Brando.repo().insert_all(
            "content_table_rows",
            [%{block_id: block_id, sequence: idx, inserted_at: now, updated_at: now}],
            returning: [:id]
          )

        value = (is_map(row) && row["value"]) || ""

        Brando.repo().insert_all("content_vars", [
          %{
            type: "html",
            key: "text",
            label: "Text",
            value: value,
            table_row_id: row_id,
            important: false,
            color_picker: false,
            color_opacity: false,
            inserted_at: now,
            updated_at: now
          }
        ])
      end

      # Update the module to use table_rows if it references this list ref
      ref_name = list_ref["name"]

      if ref_name do
        # Find the module for this block and update its code
        %{rows: module_rows} =
          Brando.repo().query!(
            """
            SELECT m.id, m.code, m.table_template_id
            FROM content_modules m
            JOIN content_blocks b ON b.module_id = m.id
            WHERE b.id = $1
            LIMIT 1
            """,
            [block_id]
          )

        case module_rows do
          [[module_id, code, existing_template_id]] when is_binary(code) ->
            # Create table template if module doesn't have one yet
            template_id =
              if existing_template_id do
                existing_template_id
              else
                {_, [%{id: tid}]} =
                  Brando.repo().insert_all(
                    "content_table_templates",
                    [%{name: "List item (#{ref_name})", creator_id: 1,
                       inserted_at: now, updated_at: now}],
                    returning: [:id]
                  )

                Brando.repo().insert_all("content_vars", [
                  %{type: "html", key: "text", label: "Text", value: "<p>Item</p>",
                    table_template_id: tid, important: false,
                    color_picker: false, color_opacity: false,
                    inserted_at: now, updated_at: now}
                ])

                tid
              end

            # Build the replacement code for the list ref
            inner = get_in(list_ref, ["data", "data"]) || %{}
            id_attr = is_map(inner) && inner["id"]
            class_attr = is_map(inner) && inner["class"]

            ul_attrs =
              [id_attr && "id=\"#{id_attr}\"", class_attr && "class=\"#{class_attr}\""]
              |> Enum.reject(&is_nil/1)

            attrs_str = if ul_attrs != [], do: " " <> Enum.join(ul_attrs, " "), else: ""

            ref_tag = ~s({% ref refs.#{ref_name} %})
            replacement = """
            {% if block.table_rows.size > 0 %}
            <ul#{attrs_str}>
              {% for row in block.table_rows %}
                <li>{{ row.text }}</li>
              {% endfor %}
            </ul>
            {% endif %}\
            """

            new_code = String.replace(code, ref_tag, replacement)

            Brando.repo().query!(
              "UPDATE content_modules SET code = $1, table_template_id = $2 WHERE id = $3",
              [new_code, template_id, module_id]
            )

          _ ->
            :ok
        end
      end
    end
  end

  defp process_datasource(block_id, datasource_selected_ids) do
    for {id, idx} <- Enum.with_index(datasource_selected_ids) do
      Brando.repo().insert_all("content_block_identifiers", [
        %{block_id: block_id, identifier_id: id, sequence: idx}
      ])
    end
  end

  defp process_vars(block_id, vars) do
    for var <- vars do
      base_var = build_var(var, block_id)

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
            Map.merge(base_var, %{image_id: get_in(var, ["value_id"])})

          %{"type" => "file"} ->
            Map.merge(base_var, %{file_id: get_in(var, ["value_id"])})

          %{"type" => "boolean"} ->
            Map.merge(base_var, %{value_boolean: get_in(var, ["value"])})

          %{"type" => "select"} ->
            Map.merge(base_var, %{
              value: get_in(var, ["value"]),
              options: get_in(var, ["options"])
            })

          _ ->
            Map.merge(base_var, %{value: get_in(var, ["value"])})
        end

      new_var =
        Map.merge(new_var, %{
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        })

      Brando.repo().insert_all("content_vars", [new_var])
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
            Map.merge(base_var, %{image_id: get_in(var, ["value_id"])})

          %{"type" => "file"} ->
            Map.merge(base_var, %{file_id: get_in(var, ["value_id"])})

          %{"type" => "boolean"} ->
            Map.merge(base_var, %{value_boolean: get_in(var, ["value"])})

          %{"type" => "select"} ->
            Map.merge(base_var, %{
              value: get_in(var, ["value"]),
              options: get_in(var, ["options"])
            })

          _ ->
            Map.merge(base_var, %{value: get_in(var, ["value"])})
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

  # Discovers villain data columns and derives block relation names.
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
    |> Enum.map(fn row ->
      data_field = String.to_atom(row.column_name)

      blocks_rel =
        row.column_name
        |> String.replace("_data", "")
        |> then(fn
          "data" -> "blocks"
          other -> other
        end)

      {row.table_name, data_field, blocks_rel}
    end)
  end
end
