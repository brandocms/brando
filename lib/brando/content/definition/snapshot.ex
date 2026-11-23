defmodule Brando.Content.Definition.Snapshot do
  @moduledoc false
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definition.{Error, Model, References, Value}
  alias Brando.Content.{Container, Module, Palette, TableTemplate}
  alias Brando.Repo
  alias Brando.Type.I18nString

  def take!(opts \\ []) do
    ensure_scope!()

    modules =
      Repo.all(
        from(m in Module, where: is_nil(m.deleted_at), order_by: [asc: m.sequence, asc: m.id], preload: [:refs, :vars])
      )

    tables = Repo.all(from(t in TableTemplate, order_by: t.id, preload: [:vars]))
    # A row without a uid (inserted around its changeset) is no definition
    palettes = Repo.all(from(p in Palette, where: is_nil(p.deleted_at) and not is_nil(p.uid), order_by: p.id))
    containers = Repo.all(from(c in Container, where: is_nil(c.deleted_at) and not is_nil(c.uid), order_by: c.id))
    Value.unique!(Enum.map(modules, & &1.uid), "stored module UIDs")
    Value.unique!(Enum.map(tables, & &1.uid), "stored table-template UIDs")
    selected = select!(modules, module_uids(opts[:uids], palettes, containers))

    Enum.each(selected, fn module ->
      if module.source_module_id,
        do: Error.raise!(module.uid, "shared-library overrides are not supported by this importer")

      Value.nonempty!(module.uid, "module UID; run framework migrations")
    end)

    table_ids = Enum.map(selected, & &1.table_template_id) |> Enum.reject(&is_nil/1)
    selected_tables = Enum.filter(tables, &(opts[:all_tables] || &1.id in table_ids))
    table_uids = Map.new(tables, &{&1.id, &1.uid})
    bindings = Keyword.get(opts, :bindings, %{})
    # A palette is named by its uid wherever a definition points at it,
    # unless the caller carries palettes its own way (`styles: false`)
    palette_uids = Map.new(palettes, &{&1.id, &1.uid})
    uids = if Keyword.get(opts, :styles, true), do: %{"palette" => palette_uids}, else: %{}

    {definitions, bindings} =
      Enum.map_reduce(selected, bindings, fn module, bindings ->
        if module.table_template_id && not Map.has_key?(table_uids, module.table_template_id),
          do: Error.raise!(module.uid, "table template is outside the local definition scope")

        subject = ~s(module "#{module.uid}")
        {refs, bindings} = associations(module.refs, &Model.stored_ref_record(&1, subject), Model.ref_assets(), bindings)

        {vars, bindings} =
          associations(module.vars, &Model.stored_var_record(&1, subject), Model.var_assets(), bindings, uids)

        children = Enum.filter(modules, &(&1.parent_id == module.id)) |> Enum.map(& &1.uid)

        definition =
          module
          |> without_stale_media_drop(modules)
          |> Model.module_record()
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
        subject = ~s(table template "#{table.uid}")

        {vars, bindings} =
          associations(table.vars, &Model.stored_var_record(&1, subject), Model.var_assets(), bindings, uids)

        {Model.table_record(table) |> Map.put("vars", vars), bindings}
      end)

    {selected_palettes, selected_containers} =
      if Keyword.get(opts, :styles, true),
        do: select_styles(opts[:uids], palettes, containers, definitions ++ table_definitions),
        else: {[], []}

    bundle = %{
      "format_version" => 1,
      "modules" => definitions,
      "table_templates" => table_definitions,
      "palettes" => Enum.map(selected_palettes, &Model.palette_record/1),
      "containers" => Enum.map(selected_containers, &Model.container_record(&1, palette_uids[&1.palette_id])),
      "references" => bindings,
      "source" => References.scope()
    }

    Model.validate_graph!(bundle)
    bundle = Model.canonicalize(bundle)
    bundle = Map.put(bundle, "baseline", baselines(bundle))

    {bundle,
     %{
       modules: Map.new(modules, &{&1.uid, &1}),
       tables: Map.new(tables, &{&1.uid, &1}),
       palettes: Map.new(palettes, &{&1.uid, &1}),
       containers: Map.new(containers, &{&1.uid, &1})
     }}
  end

  # A `media_drop` its child module no longer fits (the child deleted or
  # moved, its ref renamed or retyped, the module no longer multi) is left
  # out, as if unset: the module renders no drop zone, an import of the
  # export plans a noop, and `Brando.Doctor.Checks.ModuleMediaDrop` names it.
  defp without_stale_media_drop(module, modules) do
    children = Enum.filter(modules, &(&1.parent_id == module.id))

    if Module.media_drop_issue(module, children),
      do: %{module | media_drop_child: nil, media_drop_ref: nil},
      else: module
  end

  # The module UIDs an export selects: those `uids` names that are no palette
  # or container
  defp module_uids(nil, _palettes, _containers), do: nil

  defp module_uids(uids, palettes, containers),
    do: uids -- (Enum.map(palettes, & &1.uid) ++ Enum.map(containers, & &1.uid))

  # The local palettes and containers an export writes (a shared-library
  # override is the library's): every one, or those `uids` names, with the
  # palettes the selected containers, modules and table templates point at
  defp select_styles(uids, palettes, containers, with_vars) do
    local_palettes = Enum.filter(palettes, &is_nil(&1.source_palette_id))
    local_containers = Enum.filter(containers, &is_nil(&1.source_container_id))

    if is_nil(uids) do
      {local_palettes, local_containers}
    else
      selected_containers = Enum.filter(local_containers, &(&1.uid in uids))
      by_id = Map.new(palettes, &{&1.id, &1.uid})
      used = for definition <- with_vars, var <- definition["vars"], token = var["assets"]["palette"], do: token

      named =
        MapSet.new(uids ++ used ++ for(container <- selected_containers, uid = by_id[container.palette_id], do: uid))

      {Enum.filter(local_palettes, &MapSet.member?(named, &1.uid)), selected_containers}
    end
  end

  @doc """
  The rows of every kind that have one of `uids` here, the trash included,
  as `%{uid => [{kind, record}]}` with active rows first: a uid is one
  definition's while it is in the trash too, since a restore brings it back.
  """
  def stored(uids) do
    found =
      for kind <- Model.kinds(),
          record <- Repo.all(from(r in Model.schema(kind), where: r.uid in ^uids, order_by: r.id)),
          do: {kind, record}

    found
    |> Enum.sort_by(fn {_kind, record} -> not is_nil(Map.get(record, :deleted_at)) end)
    |> Enum.group_by(fn {_kind, record} -> record.uid end)
  end

  @doc "The record of `kind` with `uid` among `records` (what `take!/1` returns), or nil."
  def record(records, kind, uid), do: Map.fetch!(records, records_key(kind))[uid]

  @doc "The key of `kind`'s records in what `take!/1` returns."
  def records_key("module"), do: :modules
  def records_key("table_template"), do: :tables
  def records_key("palette"), do: :palettes
  def records_key("container"), do: :containers

  # Version 2 digests leave empty values out, so a field added to a block type
  # doesn't turn every untouched definition into a conflict. Lockfiles without
  # a version hold exact digests of every key; they are compared exactly until
  # the next import or export rewrites them.
  @baseline_version 2

  def baselines(bundle) do
    Model.kinds()
    |> Map.new(fn kind ->
      key = Model.bundle_key(kind)
      {key, Map.new(bundle[key] || [], &{&1["uid"], version_2_digest(&1)})}
    end)
    |> Map.put("version", @baseline_version)
  end

  @doc "`definition`'s digest as a current (version 2) baseline records it."
  def digest(definition), do: version_2_digest(definition)

  @doc "`definition`'s digest as `bundle`'s baseline records them."
  def baseline_digest(bundle, definition) do
    if get_in(bundle, ["baseline", "version"]) == @baseline_version,
      do: version_2_digest(definition),
      else: definition |> with_html_vars() |> with_plain_instructions() |> Value.digest()
  end

  defp version_2_digest(definition),
    do:
      definition
      |> drop_implied_link_defaults()
      |> with_html_vars()
      |> with_plain_instructions()
      |> Value.baseline_digest()

  # A var's instructions were text before brando_234 made them a language
  # map, and a baseline from before the upgrade was digested with the text:
  # digests use it for instructions in one language, so the upgrade is no
  # change to the definition.
  defp with_plain_instructions(%{"vars" => vars} = definition) when is_list(vars),
    do: %{definition | "vars" => Enum.map(vars, &plain_instructions/1)}

  defp with_plain_instructions(definition), do: definition

  defp plain_instructions(%{"instructions" => instructions} = var),
    do: %{var | "instructions" => I18nString.plain(instructions)}

  defp plain_instructions(var), do: var

  # A `rich_text` var was an `html` var before brando_225, and a baseline from
  # before the upgrade was digested with that name: digests use it, so the
  # rename is no change to the definition.
  defp with_html_vars(%{"vars" => vars} = definition) when is_list(vars),
    do: %{definition | "vars" => Enum.map(vars, &html_var/1)}

  defp with_html_vars(definition), do: definition

  defp html_var(%{"type" => "rich_text"} = var), do: %{var | "type" => "html"}
  defp html_var(var), do: var

  # Before `link_default_type`, an empty link of type identifier was how a var
  # opened on Content, and brando_224 gave those the default they implied. A
  # baseline from before the upgrade has no default there: it is the same
  # definition.
  defp drop_implied_link_defaults(%{"vars" => vars} = definition) when is_list(vars),
    do: %{definition | "vars" => Enum.map(vars, &drop_implied_link_default/1)}

  defp drop_implied_link_defaults(definition), do: definition

  defp drop_implied_link_default(
         %{"type" => "link", "link_type" => "identifier", "link_default_type" => "identifier"} = var
       ) do
    if Map.get(var, "value") in [nil, ""] and get_in(var, ["assets", "identifier"]) in [nil, ""],
      do: Map.delete(var, "link_default_type"),
      else: var
  end

  defp drop_implied_link_default(var), do: var

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
    if missing != [], do: Error.raise!("export", "unknown UIDs #{inspect(missing)}")
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

  defp associations(records, encode, fields, bindings, uids \\ %{}) do
    records
    |> Enum.sort_by(&{&1.sequence || 0, &1.id})
    |> Enum.with_index()
    |> Enum.map_reduce(bindings, fn {record, index}, bindings ->
      {assets, bindings} = References.encode(record, fields, bindings, uids)
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
