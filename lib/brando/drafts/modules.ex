defmodule Brando.Drafts.Modules do
  @moduledoc "Captures and checks the module contracts a recovery copy depends on."
  alias Brando.Drafts.Params

  @contract_fields ~w(type multi datasource datasource_module datasource_type datasource_query table_template_id)a

  def manifest(block_fields) do
    block_fields |> Map.values() |> List.flatten() |> Enum.reduce(%{}, &collect/2)
  end

  defp collect(%{"block" => block}, acc), do: collect(block, acc)

  defp collect(block, acc) do
    acc =
      if block["module_id"] do
        Map.put_new_lazy(acc, key(block), fn -> definition(fetch(block)) end)
      else
        acc
      end

    Enum.reduce(block["children"] || [], acc, &collect/2)
  end

  def check(block_fields, captured) do
    Enum.reduce(block_fields, {%{}, []}, fn {field, blocks}, {safe_fields, issues} ->
      {safe, found} = check_blocks(blocks, captured)
      {Map.put(safe_fields, field, safe), issues ++ found}
    end)
  end

  defp check_blocks(blocks, captured) do
    Enum.reduce(blocks, {[], []}, fn entry_block, {safe, issues} ->
      block = entry_block["block"] || entry_block
      current = if block["module_id"], do: fetch(block)
      old = Map.get(captured, key(block))
      reasons = reasons(block, old, current)

      if reasons == [] do
        {children, child_issues} = check_blocks(block["children"] || [], captured)
        adapted = block |> Map.put("children", children) |> add_defaults(current)
        adapted = if entry_block["block"], do: Map.put(entry_block, "block", adapted), else: adapted
        {safe ++ [adapted], issues ++ child_issues}
      else
        issue = %{uid: block["uid"], module_id: block["module_id"], reasons: reasons, content: entry_block}
        {safe, issues ++ [issue]}
      end
    end)
  end

  defp reasons(%{"module_id" => id}, _old, nil) when not is_nil(id), do: ["The module is missing or unavailable."]

  defp reasons(%{"module_id" => id}, nil, _current) when not is_nil(id),
    do: ["The draft has no module definition to compare."]

  defp reasons(_block, _old, nil), do: []

  defp reasons(block, old, current) do
    latest = definition(current)
    contract = Enum.filter(@contract_fields, &(old[to_string(&1)] != latest[to_string(&1)]))

    identity = if old["uid"] != latest["uid"], do: ["The original module was replaced."], else: []
    tables = if old["table"] != latest["table"], do: ["The table definition changed."], else: []

    fields =
      compare_fields("Reference", old["refs"] || %{}, latest["refs"] || %{}) ++
        compare_fields("Variable", old["vars"] || %{}, latest["vars"] || %{})

    # A block may already have been stale when the copy was made.
    instance =
      compare_fields("Reference", ref_types(block["refs"] || []), latest["refs"] || %{}) ++
        compare_fields("Variable", var_types(block["vars"] || []), latest["vars"] || %{})

    Enum.uniq(identity ++ tables ++ fields ++ instance ++ Enum.map(contract, &"Module setting #{&1} changed."))
  end

  defp compare_fields(label, old, current) do
    Enum.flat_map(old, fn {name, type} ->
      cond do
        not Map.has_key?(current, name) -> ["#{label} “#{name}” was removed or renamed."]
        compatible_type?(type, current[name]) -> []
        true -> ["#{label} “#{name}” changed type."]
      end
    end)
  end

  defp compatible_type?(type, type), do: true
  defp compatible_type?(type, "media"), do: type in ["picture", "video", "gallery", "svg"]
  defp compatible_type?("media", type), do: type in ["picture", "video", "gallery", "svg"]
  defp compatible_type?(_, _), do: false

  defp add_defaults(block, nil), do: block

  defp add_defaults(block, module) do
    block
    |> add_missing("refs", "name", module.refs || [])
    |> add_missing("vars", "key", module.vars || [])
  end

  defp add_missing(block, field, key, definitions) do
    existing = block[field] || []
    keys = MapSet.new(existing, & &1[key])

    additions =
      definitions
      |> Enum.map(&Params.snapshot/1)
      |> Enum.reject(&MapSet.member?(keys, &1[key]))
      |> Enum.map(&Params.without_identity/1)
      |> Enum.map(fn params ->
        if field == "refs", do: Map.put(params, "uid", Brando.Utils.generate_uid()), else: params
      end)

    Map.put(block, field, existing ++ additions)
  end

  defp definition(nil), do: nil

  defp definition(module) do
    params = Params.snapshot(module)

    params
    |> Map.take(Enum.map(@contract_fields, &to_string/1) ++ ["uid", "version"])
    |> Map.put("multi", params["multi"] || false)
    |> Map.put("refs", ref_types(params["refs"] || []))
    |> Map.put("vars", var_types(params["vars"] || []))
    |> Map.put("table", table_definition(module))
  end

  defp table_definition(%{table_template_id: nil}), do: nil

  defp table_definition(%{table_template_id: id} = module) do
    schema = Brando.Content.TableTemplate
    prefix = Ecto.get_meta(module, :prefix)

    case Brando.Repo.get(schema, id, prefix: prefix) do
      nil -> nil
      table -> table |> Brando.Repo.preload(:vars, prefix: prefix) |> Params.snapshot() |> Map.take(["vars"])
    end
  end

  defp table_definition(_), do: nil

  defp ref_types(refs), do: Map.new(refs, &{&1["name"], get_in(&1, ["data", "type"])})
  defp var_types(vars), do: Map.new(vars, &{&1["key"], &1["type"]})
  defp key(block), do: "#{block["module_origin"] || "local"}:#{block["module_id"]}"

  defp fetch(block) do
    origin = if block["module_origin"] == "shared", do: :shared, else: :local

    case Brando.Content.fetch_module(block["module_id"], origin) do
      %{deleted_at: nil} = module -> module
      _ -> nil
    end
  end
end
