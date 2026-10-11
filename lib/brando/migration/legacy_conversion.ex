defmodule Brando.Migration.LegacyConversion do
  @moduledoc """
  Compares the Villain JSON a site kept after the upgrade migrations
  (brando_103 to brando_133) with the blocks those migrations wrote.

  `check/1` reads one database schema and changes nothing.
  `mix brando.check.legacy_conversion` runs it in every environment, and its
  documentation lists what is compared and what is not.

  Blocks are paired by position: brando_123 gave every block a new uid, and
  brando_108 stored a block's place in its Villain list as its `sequence` (on
  the join table row for root blocks).
  """

  alias Brando.Type.I18nString

  # brando_108 puts each of these free-standing Villain blocks in a "Legacy
  # Content Wrapper" module block, its content in one ref named `content`
  @wrapped_types ~w(text markdown image picture video divider header blockquote datasource map svg html)

  # Tables with a json `*data` column that brando_103 and brando_108 pass over
  @not_villain ~w(revisions content_modules sites_globals pages_properties)

  # Refs brando_108 turns into table rows
  @row_ref_types ~w(table list)

  @content_tables ~w(content_blocks content_vars content_refs content_table_rows content_block_identifiers content_modules)

  @type severity :: :missing | :extra
  @type finding :: %{
          table: String.t(),
          entry_id: term(),
          path: [String.t()],
          message: String.t(),
          severity: severity()
        }
  @type source :: %{table: String.t(), column: String.t(), join_table: String.t()}
  @type report :: %{
          schema: String.t(),
          sources: [map()],
          dropped: [source()],
          findings: [finding()]
        }

  @doc """
  Checks every table in `schema` that still has a Villain column next to its
  blocks join table. Returns `{:error, message}` when the schema has no
  converted blocks to compare with (brando_132 creates `content_refs`).
  """
  @spec check(String.t()) :: {:ok, report()} | {:error, String.t()}
  def check(schema \\ "public") do
    tables = list_tables(schema)

    case Enum.reject(@content_tables, &MapSet.member?(tables, &1)) do
      [] ->
        {:ok, run(schema, tables)}

      missing ->
        {:error,
         "#{Enum.join(missing, ", ")} not found in schema #{schema}. Run the upgrade migrations (to brando_133 at least) first."}
    end
  end

  @doc "A finding as one line: `pages #12 › block 3 (module \"Values\") › vars: heading missing`."
  @spec format(finding()) :: String.t()
  def format(finding) do
    Enum.join(["#{finding.table} ##{finding.entry_id}" | finding.path] ++ [finding.message], " › ")
  end

  defp run(schema, tables) do
    {sources, dropped} = sources(schema, tables)
    content = if sources == [], do: nil, else: load_content(schema)
    checked = Enum.map(sources, &check_source(schema, &1, content))

    %{
      schema: schema,
      sources: Enum.map(checked, &elem(&1, 0)),
      dropped: dropped,
      findings: Enum.flat_map(checked, &elem(&1, 1))
    }
  end

  ## Discovery

  defp sources(schema, tables) do
    join_tables = list_join_tables(schema)

    sources =
      """
      SELECT table_name, column_name FROM information_schema.columns
      WHERE table_schema = $1 AND data_type IN ('json', 'jsonb') AND column_name LIKE '%data'
      ORDER BY table_name, column_name
      """
      |> rows([schema])
      |> Enum.reject(fn [table, _column] -> table in @not_villain end)
      |> Enum.map(fn [table, column] -> %{table: table, column: column, join_table: join_table(table, column)} end)
      |> Enum.filter(&MapSet.member?(join_tables, &1.join_table))

    checked = MapSet.new(sources, & &1.join_table)

    dropped =
      join_tables
      |> Enum.reject(&MapSet.member?(checked, &1))
      |> Enum.flat_map(&dropped_source(&1, tables))
      |> Enum.sort_by(& &1.join_table)

    {sources, dropped}
  end

  # The join table brando_103 created for a Villain column: `data` →
  # `<table>_blocks`, `<field>_data` → `<table>_<field>`
  defp join_table(table, column) do
    relation =
      case String.replace(column, "_data", "") do
        "data" -> "blocks"
        other -> other
      end

    "#{table}_#{relation}"
  end

  # A join table with no Villain column next to it: the column it would have
  # is named after the longest table name the join table starts with
  defp dropped_source(join_table, tables) do
    tables
    |> Enum.filter(&String.starts_with?(join_table, &1 <> "_"))
    |> Enum.max_by(&String.length/1, fn -> nil end)
    |> case do
      nil ->
        []

      table ->
        column =
          case String.replace_prefix(join_table, table <> "_", "") do
            "blocks" -> "data"
            field -> field <> "_data"
          end

        [%{table: table, column: column, join_table: join_table}]
    end
  end

  defp list_tables(schema) do
    "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 AND table_type = 'BASE TABLE'"
    |> rows([schema])
    |> MapSet.new(&hd/1)
  end

  defp list_join_tables(schema) do
    """
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = $1 AND column_name IN ('entry_id', 'block_id')
    GROUP BY table_name HAVING count(*) = 2
    """
    |> rows([schema])
    |> MapSet.new(&hd/1)
  end

  ## Loading

  defp load_content(schema) do
    blocks =
      "SELECT id, type, parent_id, sequence, module_id, fragment_id FROM #{name(schema, "content_blocks")}"
      |> rows()
      |> Enum.map(fn [id, type, parent_id, sequence, module_id, fragment_id] ->
        %{
          id: id,
          type: type,
          parent_id: parent_id,
          sequence: sequence,
          module_id: module_id,
          fragment_id: fragment_id
        }
      end)

    vars =
      """
      SELECT block_id, key, value IS NOT NULL AND btrim(value) <> '', value_boolean IS TRUE,
             image_id IS NOT NULL, file_id IS NOT NULL
      FROM #{name(schema, "content_vars")} WHERE block_id IS NOT NULL ORDER BY block_id, id
      """
      |> rows()
      |> Enum.group_by(&hd/1, fn [_, key, value, boolean, image, file] ->
        %{key: key, value: value, boolean: boolean, image: image, file: file}
      end)

    %{
      blocks: Map.new(blocks, &{&1.id, &1}),
      children:
        blocks
        |> Enum.reject(&is_nil(&1.parent_id))
        |> Enum.sort_by(&{&1.sequence, &1.id})
        |> Enum.group_by(& &1.parent_id, &{&1.sequence, &1}),
      vars: vars,
      refs:
        "SELECT block_id, name FROM #{name(schema, "content_refs")} WHERE block_id IS NOT NULL ORDER BY block_id, sequence, id"
        |> rows()
        |> Enum.group_by(&hd/1, fn [_block_id, name] -> name end),
      fragments:
        "SELECT id FROM #{name(schema, "pages_fragments")}"
        |> rows()
        |> MapSet.new(&hd/1),
      table_rows: counts(schema, "content_table_rows"),
      identifiers: counts(schema, "content_block_identifiers"),
      modules:
        "SELECT id, name FROM #{name(schema, "content_modules")}"
        |> rows()
        |> Map.new(fn [id, name] -> {id, I18nString.localized(name)} end)
    }
  end

  defp counts(schema, table) do
    "SELECT block_id, count(*) FROM #{name(schema, table)} WHERE block_id IS NOT NULL GROUP BY block_id"
    |> rows()
    |> Map.new(fn [block_id, count] -> {block_id, count} end)
  end

  ## Comparing

  defp check_source(schema, source, content) do
    column = quote_name(source.column)

    entries =
      rows("SELECT id, #{column} FROM #{name(schema, source.table)} WHERE #{column} IS NOT NULL ORDER BY id")

    roots =
      "SELECT entry_id, block_id, sequence FROM #{name(schema, source.join_table)} ORDER BY entry_id, sequence, block_id"
      |> rows()
      |> Enum.group_by(&hd/1, fn [_, block_id, sequence] -> {sequence, Map.fetch!(content.blocks, block_id)} end)

    findings =
      for [id, legacy] <- entries, is_list(legacy) do
        at = %{table: source.table, entry_id: id, path: []}
        compare_level(legacy, Map.get(roots, id, []), at, content, :block)
      end

    {Map.put(source, :entries, length(entries)), List.flatten(findings)}
  end

  defp compare_level(legacy, new, at, content, kind) do
    by_position = by_position(new)

    blocks =
      legacy
      |> Enum.with_index()
      |> Enum.flat_map(fn {block, index} ->
        at = step(at, label(kind, index + 1, block, content))

        case Map.get(by_position, index) do
          nil -> [missing(at, "not found")]
          %{type: type} = new_block -> compare_paired(block, new_block, type, at, content)
        end
      end)

    compare_counts(legacy, Enum.map(new, &elem(&1, 1)), at, kind) ++ blocks
  end

  defp compare_paired(legacy, new, type, at, content) do
    if type == expected_type(legacy),
      do: compare_block(legacy, new, at, content),
      else: [missing(at, "a #{type} block now")]
  end

  # By the sequence brando_108 wrote, which is the block's place in its Villain
  # list; by order when sequences repeat or are missing
  defp by_position(new) do
    sequences = Enum.map(new, &elem(&1, 0))

    if Enum.all?(sequences, &is_integer/1) and Enum.uniq(sequences) == sequences do
      Map.new(new)
    else
      new |> Enum.map(&elem(&1, 1)) |> Enum.with_index() |> Map.new(fn {block, index} -> {index, block} end)
    end
  end

  defp compare_counts(legacy, new, at, kind) do
    before = Enum.frequencies_by(legacy, &expected_type/1)
    now = Enum.frequencies_by(new, & &1.type)
    noun = if kind == :entry, do: "entries", else: "blocks"

    cond do
      before == now ->
        []

      Enum.any?(before, fn {type, count} -> Map.get(now, type, 0) < count end) ->
        [missing(at, "#{noun}: #{describe(before)} in Villain, #{describe(now)} now")]

      true ->
        [extra(at, "#{noun}: #{describe(before)} in Villain, #{describe(now)} now")]
    end
  end

  defp describe(counts) when counts == %{}, do: "none"

  defp describe(counts) do
    counts |> Enum.sort() |> Enum.map_join(", ", fn {type, count} -> "#{count} #{type}" end)
  end

  defp compare_block(%{"type" => type}, new, at, content) when type in @wrapped_types do
    compare_names("refs", ["content"], Map.get(content.refs, new.id, []), at)
  end

  # brando_108 keeps no fragment for one deleted since, which rendered nothing
  defp compare_block(%{"type" => "fragment"} = legacy, new, at, content) do
    id = data(legacy, "fragment_id")

    cond do
      is_nil(id) or id == new.fragment_id -> []
      is_nil(new.fragment_id) and not MapSet.member?(content.fragments, id) -> []
      true -> [missing(at, "fragment_id: #{id} in Villain, #{new.fragment_id || "none"} now")]
    end
  end

  defp compare_block(legacy, new, at, content) do
    refs = legacy |> list("refs") |> Enum.filter(&is_map/1)
    {row_refs, refs} = Enum.split_with(refs, &(ref_type(&1) in @row_ref_types))

    Enum.concat([
      compare_vars(legacy |> list("vars") |> Enum.filter(&is_map/1), Map.get(content.vars, new.id, []), at),
      compare_names(
        "refs",
        refs |> Enum.map(& &1["name"]) |> Enum.reject(&is_nil/1),
        Map.get(content.refs, new.id, []),
        at
      ),
      compare_count(
        "table rows",
        row_refs |> Enum.map(&row_count/1) |> Enum.sum(),
        Map.get(content.table_rows, new.id, 0),
        at
      ),
      compare_count(
        "datasource entries",
        length(list(legacy, "datasource_selected_ids")),
        Map.get(content.identifiers, new.id, 0),
        at
      ),
      compare_children(legacy, new, at, content)
    ])
  end

  defp compare_children(%{"type" => "container"} = legacy, new, at, content) do
    compare_level(list(legacy, "blocks"), Map.get(content.children, new.id, []), at, content, :block)
  end

  defp compare_children(%{"type" => "module"} = legacy, new, at, content) do
    if data(legacy, "multi") == true,
      do: compare_level(list(legacy, "entries"), Map.get(content.children, new.id, []), at, content, :entry),
      else: []
  end

  defp compare_children(_legacy, _new, _at, _content), do: []

  # Vars the block has beyond Villain's are not reported: saving a module adds
  # the vars it defines to every block using it
  defp compare_vars(legacy, new, at) do
    new_by_key = Enum.group_by(new, & &1.key)

    legacy
    |> Enum.group_by(& &1["key"])
    |> Enum.sort_by(fn {key, _} -> Enum.find_index(legacy, &(&1["key"] == key)) end)
    |> Enum.flat_map(fn {key, vars} ->
      now = Map.get(new_by_key, key, [])

      emptied =
        vars
        |> Enum.zip(now)
        |> Enum.filter(fn {var, row} -> filled?(var) and not filled?(var["type"], row) end)
        |> Enum.map(fn _ -> missing(at, "vars: #{display(key)} had a value, empty now") end)

      deficit("vars", key, length(vars), length(now), at) ++ emptied
    end)
  end

  defp compare_names(label, legacy, new, at) do
    now = Enum.frequencies(new)

    legacy
    |> Enum.frequencies()
    |> Enum.sort_by(fn {name, _} -> Enum.find_index(legacy, &(&1 == name)) end)
    |> Enum.flat_map(fn {name, count} -> deficit(label, name, count, Map.get(now, name, 0), at) end)
  end

  defp deficit(label, key, before, 0, at) when before > 0, do: [missing(at, "#{label}: #{display(key)} missing")]

  defp deficit(label, key, before, now, at) when before > now,
    do: [missing(at, "#{label}: #{before} × #{display(key)} in Villain, #{now} now")]

  defp deficit(_label, _key, _before, _now, _at), do: []

  defp compare_count(_label, same, same, _at), do: []

  defp compare_count(label, before, now, at) when before > now,
    do: [missing(at, "#{label}: #{before} in Villain, #{now} now")]

  defp compare_count(label, before, now, at), do: [extra(at, "#{label}: #{before} in Villain, #{now} now")]

  # brando_108 moves image and file vars' `value_id` to `image_id`/`file_id`
  # and a boolean's `value` to `value_boolean`
  defp filled?(%{"type" => type} = var) when type in ["image", "file"], do: not is_nil(var["value_id"])
  defp filled?(%{"type" => "boolean"} = var), do: var["value"] in [true, "true"]
  defp filled?(%{"value" => value}) when is_binary(value), do: String.trim(value) != ""
  defp filled?(%{"value" => value}), do: not is_nil(value)
  defp filled?(_var), do: false

  defp filled?("image", row), do: row.image
  defp filled?("file", row), do: row.file
  defp filled?("boolean", row), do: row.boolean
  defp filled?(_type, row), do: row.value

  defp expected_type(%{"type" => type}) when type in @wrapped_types, do: "module"
  defp expected_type(%{"type" => type}), do: type
  defp expected_type(_block), do: nil

  defp label(:entry, number, _block, _content), do: "entry #{number}"

  defp label(:block, number, %{"type" => type}, _content) when type in @wrapped_types,
    do: "block #{number} (#{type}, wrapped)"

  defp label(:block, number, %{"type" => "module"} = block, content) do
    case Map.get(content.modules, data(block, "module_id")) do
      nil -> "block #{number} (module #{data(block, "module_id")})"
      name -> ~s|block #{number} (module "#{name}")|
    end
  end

  defp label(:block, number, block, _content), do: "block #{number} (#{expected_type(block)})"

  defp ref_type(%{"data" => %{"type" => type}}), do: type
  defp ref_type(_ref), do: nil

  defp row_count(%{"data" => %{"data" => %{"rows" => rows}}}) when is_list(rows), do: length(rows)
  defp row_count(_ref), do: 0

  defp data(%{"data" => %{} = data}, key), do: Map.get(data, key)
  defp data(_block, _key), do: nil

  defp list(block, key) do
    case data(block, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp display(nil), do: "(no key)"
  defp display(key), do: key

  defp step(at, label), do: %{at | path: at.path ++ [label]}

  defp missing(at, message), do: finding(at, message, :missing)
  defp extra(at, message), do: finding(at, message, :extra)

  defp finding(at, message, severity) do
    %{table: at.table, entry_id: at.entry_id, path: at.path, message: message, severity: severity}
  end

  ## SQL

  defp rows(sql, params \\ []), do: Brando.repo().query!(sql, params, log: false).rows

  defp name(schema, table), do: quote_name(schema) <> "." <> quote_name(table)

  defp quote_name(name), do: ~s(") <> String.replace(name, ~s("), ~s("")) <> ~s(")
end
