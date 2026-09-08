defmodule Brando.Content.Definition.Snapshot do
  @moduledoc false
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Module, TableTemplate}
  alias Brando.Content.Definition.{Error, Model, References, Value}
  alias Brando.Repo

  def take!(opts \\ []) do
    ensure_scope!()

    modules =
      Repo.all(
        from(m in Module, where: is_nil(m.deleted_at), order_by: [asc: m.sequence, asc: m.id], preload: [:refs, :vars])
      )

    tables = Repo.all(from(t in TableTemplate, order_by: t.id, preload: [:vars]))
    Value.unique!(Enum.map(modules, & &1.uid), "stored module UIDs")
    Value.unique!(Enum.map(tables, & &1.uid), "stored table-template UIDs")
    selected = select!(modules, opts[:uids])

    Enum.each(selected, fn module ->
      if module.source_module_id,
        do: Error.raise!(module.uid, "shared-library overrides are not supported by this importer")

      Value.nonempty!(module.uid, "module UID; run framework migrations")
    end)

    table_ids = Enum.map(selected, & &1.table_template_id) |> Enum.reject(&is_nil/1)
    selected_tables = Enum.filter(tables, &(opts[:all_tables] || &1.id in table_ids))
    table_uids = Map.new(tables, &{&1.id, &1.uid})
    bindings = Keyword.get(opts, :bindings, %{})

    {definitions, bindings} =
      Enum.map_reduce(selected, bindings, fn module, bindings ->
        if module.table_template_id && not Map.has_key?(table_uids, module.table_template_id),
          do: Error.raise!(module.uid, "table template is outside the local definition scope")

        {refs, bindings} = associations(module.refs, &Model.ref_record/1, Model.ref_assets(), bindings)
        {vars, bindings} = associations(module.vars, &Model.var_record/1, Model.var_assets(), bindings)
        children = Enum.filter(modules, &(&1.parent_id == module.id)) |> Enum.map(& &1.uid)

        definition =
          Model.module_record(module)
          |> Map.merge(%{
            "refs" => refs,
            "vars" => vars,
            "children" => children,
            "table_template" => Map.get(table_uids, module.table_template_id)
          })

        {definition, bindings}
      end)

    {table_definitions, bindings} =
      Enum.map_reduce(selected_tables, bindings, fn table, bindings ->
        Value.nonempty!(table.uid, "table-template UID; run framework migrations")
        {vars, bindings} = associations(table.vars, &Model.var_record/1, Model.var_assets(), bindings)
        {Model.table_record(table) |> Map.put("vars", vars), bindings}
      end)

    bundle = %{
      "format_version" => 1,
      "modules" => definitions,
      "table_templates" => table_definitions,
      "references" => bindings,
      "source" => References.scope()
    }

    Model.validate_graph!(bundle)
    bundle = Model.canonicalize(bundle)
    bundle = Map.put(bundle, "baseline", baselines(bundle))
    {bundle, %{modules: Map.new(modules, &{&1.uid, &1}), tables: Map.new(tables, &{&1.uid, &1})}}
  end

  def baselines(bundle) do
    Map.new(~w(modules table_templates), fn kind -> {kind, Map.new(bundle[kind], &{&1["uid"], Value.digest(&1)})} end)
  end

  def ensure_scope! do
    if Brando.Tenant.mode() != :none and is_nil(Brando.Tenant.current_prefix()),
      do: Error.raise!("scope", "select a site/environment; shared public definitions are not supported")
  end

  defp select!(modules, nil) do
    by_id = Map.new(modules, &{&1.id, &1})
    Enum.reject(modules, &root!(&1, by_id, MapSet.new()).source_module_id)
  end

  defp select!(modules, uids) do
    missing = uids -- Enum.map(modules, & &1.uid)
    if missing != [], do: Error.raise!("export", "unknown module UIDs #{inspect(missing)}")
    by_parent = Enum.group_by(modules, & &1.parent_id)
    by_id = Map.new(modules, &{&1.id, &1})
    roots = modules |> Enum.filter(&(&1.uid in uids)) |> Enum.map(&root!(&1, by_id, MapSet.new()))
    roots |> Enum.flat_map(&descendants(&1, by_parent, MapSet.new())) |> Enum.uniq_by(& &1.id)
  end

  defp root!(module, by_id, seen) do
    if MapSet.member?(seen, module.id), do: Error.raise!(module.uid, "cyclic module relationship")

    if module.parent_id do
      parent = by_id[module.parent_id] || Error.raise!(module.uid, "missing parent definition")
      root!(parent, by_id, MapSet.put(seen, module.id))
    else
      module
    end
  end

  defp descendants(module, by_parent, seen) do
    if MapSet.member?(seen, module.id), do: Error.raise!(module.uid, "cyclic module relationship")
    [module | Enum.flat_map(Map.get(by_parent, module.id, []), &descendants(&1, by_parent, MapSet.put(seen, module.id)))]
  end

  defp associations(records, encode, fields, bindings) do
    records
    |> Enum.sort_by(&{&1.sequence || 0, &1.id})
    |> Enum.with_index()
    |> Enum.map_reduce(bindings, fn {record, index}, bindings ->
      {assets, bindings} = References.encode(record, fields, bindings)
      data = record |> encode.() |> Map.merge(%{"assets" => assets, "sequence" => index})

      if Map.has_key?(data, "data") do
        {ref_data, bindings} = References.encode_data(data["data"], bindings)
        {Map.put(data, "data", ref_data), bindings}
      else
        {data, bindings}
      end
    end)
  end
end
