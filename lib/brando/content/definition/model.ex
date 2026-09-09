defmodule Brando.Content.Definition.Model do
  @moduledoc false

  alias Brando.Content.Definition.{Error, Reader, Value}
  alias Brando.Content.{Module, Ref, Var}
  alias Brando.Villain.Blocks
  alias Ecto.Changeset

  @module_fields ~w(uid name namespace help_text class code type svg color multi sequence datasource datasource_module datasource_type datasource_query)a
  @ref_fields ~w(uid name description active collapsed sequence data)a
  @var_owners ~w(page_id block_id module_id table_template_id table_row_id global_set_id menu_item_id)a
  @var_assets ~w(image file video gallery palette identifier)
  @ref_assets ~w(image file video gallery)

  def module_fields, do: @module_fields
  def ref_assets, do: @ref_assets
  def var_assets, do: @var_assets

  def var_fields do
    Var.__schema__(:fields) --
      (~w(id creator_id inserted_at updated_at)a ++
         @var_owners ++ Enum.map(@var_assets, &String.to_existing_atom(&1 <> "_id")))
  end

  def from_specs!(specs, root) do
    names = Map.new(specs, &{&1.module, &1.options.uid})
    Value.unique!(Enum.map(specs, & &1.module), "source module names")
    Value.unique!(Enum.map(specs, & &1.options.uid), "definition UIDs")

    definitions = Enum.map(specs, &definition!(&1, root, names))
    {tables, modules} = Enum.split_with(definitions, &(&1["kind"] == "table_template"))
    bundle = canonicalize(%{"format_version" => 1, "modules" => modules, "table_templates" => tables})
    validate_graph!(bundle)
    bundle
  end

  defp definition!(spec, root, names) do
    opts = spec.options
    uid = Value.nonempty!(opts.uid, spec.source || spec.module)
    kind = Map.get(opts, :kind, :module) || :module
    vars = spec.vars |> Enum.with_index() |> Enum.map(fn {var, index} -> var!(var, index, uid) end)

    if kind == :table_template do
      if spec.refs != [] or spec.templates != [] or spec.children != [],
        do: Error.raise!(uid, "table templates only declare uid, name and vars")

      extra = Map.keys(Map.reject(opts, fn {_k, v} -> v == nil end)) -- [:kind, :uid, :name]
      if extra != [], do: Error.raise!(uid, "unsupported table-template options #{inspect(extra)}")
      %{"kind" => "table_template", "uid" => uid, "name" => Value.nonempty!(opts.name, uid <> ".name"), "vars" => vars}
    else
      fields =
        struct(Module)
        |> Map.take(@module_fields)
        |> Map.merge(Map.take(opts, @module_fields))
        |> Map.update!(:name, &Value.object/1)
        |> Map.update!(:namespace, &Value.object/1)
        |> Map.update!(:help_text, &Value.object/1)
        |> Value.plain()

      {engine, code} = template!(spec.templates, spec.source, root)
      refs = spec.refs |> Enum.with_index() |> Enum.map(fn {ref, index} -> ref!(ref, index, uid) end)
      children = Enum.map(spec.children, &resolve!(&1.definition, names))

      fields
      |> Map.merge(%{
        "type" => to_string(engine),
        "code" => code,
        "refs" => refs,
        "vars" => vars,
        "children" => children,
        "table_template" => resolve!(opts[:table_template], names),
        "kind" => "module"
      })
      |> normalize_module!()
    end
  end

  defp template!([%{engine: engine, source: source, file: true}], file, root),
    do: {engine, Reader.template_file!(source, file, root)}

  defp template!([%{engine: engine, source: source}], _, _), do: {engine, source}
  defp template!(_, file, _), do: Error.raise!(file, "declare exactly one template or template_file")

  defp resolve!(nil, _names), do: nil

  defp resolve!(reference, names) do
    reference = to_string(reference)
    Map.get(names, reference, reference)
  end

  defp ref!(spec, index, uid) do
    name = to_string(spec.name)
    type = to_string(spec.type)
    block_schema = block_schema!(type)
    config = Value.object(spec[:config])
    defaults = Value.object(spec[:default])

    if Enum.any?(Map.keys(config), &Map.has_key?(defaults, &1)),
      do: Error.raise!(uid <> "." <> name, "config and default overlap")

    data = Map.merge(config, defaults)
    validate_fields!(Elixir.Module.concat(block_schema, Data), data, uid <> "." <> name)
    references = if type == "markdown_source", do: Map.take(data, ~w(source_id version_id)), else: %{}

    Enum.each(references, fn {field, token} ->
      if token != nil, do: Value.nonempty!(token, uid <> "." <> name <> "." <> field)
    end)

    # External tokens are resolved only at the destination. Validate the rest
    # of the embedded data without passing tokens to its integer ID fields.
    data = Map.merge(data, Map.new(references, fn {field, _} -> {field, nil} end))

    params = %{
      "name" => name,
      "uid" => spec[:uid] || Value.digest([uid, "ref", name]),
      "description" => spec[:description],
      "active" => Map.get(spec, :active, true),
      "collapsed" => Map.get(spec, :collapsed, false),
      "sequence" => index,
      "data" => %{"type" => type, "data" => data}
    }

    params
    |> then(&Ref.changeset(struct(Ref), &1, :system))
    |> apply_valid!(uid <> ".refs." <> name)
    |> ref_record()
    |> update_in(["data", "data"], &Map.merge(&1, references))
    |> Map.put("assets", assets!(spec[:assets], @ref_assets, uid))
  end

  defp var!(spec, index, uid) do
    fields = var_fields()
    settings = Value.object(spec[:settings])
    Value.keys!(settings, fields -- [:key, :type], uid <> ".vars.settings")
    key = to_string(spec.key)
    type = to_string(spec.type)

    attributes =
      spec
      |> Map.take(~w(label placeholder instructions width placement new_row)a)
      |> Map.reject(fn {_key, value} -> value == :__unset__ end)
      |> Value.plain()

    params =
      settings
      |> Map.merge(attributes)
      |> Map.merge(%{"key" => key, "type" => type, "sequence" => index})
      |> Map.put_new("label", key)

    params = if spec[:options] in [nil, :__unset__], do: params, else: Map.put(params, "options", options!(spec.options))
    assets = assets!(spec[:assets], @var_assets, uid)

    {params, assets} =
      case Map.get(spec, :default, :__unset__) do
        :__unset__ -> {params, assets}
        default when type in ~w(image file video gallery) -> {params, Map.put(assets, type, default)}
        default -> {Map.put(params, if(type == "boolean", do: "value_boolean", else: "value"), default), assets}
      end

    validate_fields!(Var, params, uid <> ".vars." <> key)

    params
    # Creator is persistence metadata, supplied by the import actor. A sentinel
    # satisfies that required field while normalizing without any database I/O.
    |> then(&Var.changeset(struct(Var), &1, %{id: 0}))
    |> apply_valid!(uid <> ".vars." <> key)
    |> var_record()
    |> Map.put("assets", assets)
  end

  defp options!(options) when is_list(options) do
    Enum.map(options, fn
      {label, value} -> %{"label" => label, "value" => value}
      option -> Value.object(option)
    end)
  end

  defp options!(_), do: Error.raise!("options", "expected a list")

  defp assets!(value, allowed, path) do
    assets = Value.object(value)
    Value.keys!(assets, allowed, path <> ".assets")
    Enum.each(assets, fn {key, value} -> if value != nil, do: Value.nonempty!(value, path <> ".assets." <> key) end)
    Map.merge(Map.new(allowed, &{&1, nil}), assets)
  end

  def module_record(record) do
    record
    |> Map.take(@module_fields)
    |> Value.plain()
    |> Map.put("kind", "module")
    |> Map.put("refs", ordered(record.refs, &ref_record/1))
    |> Map.put("vars", ordered(record.vars, &var_record/1))
    |> normalize_module!()
  end

  def table_record(record),
    do: %{
      "kind" => "table_template",
      "uid" => record.uid,
      "name" => record.name,
      "vars" => ordered(record.vars, &var_record/1)
    }

  def ref_record(record),
    do: record |> Map.take(@ref_fields) |> Value.plain() |> Map.put("assets", Map.new(@ref_assets, &{&1, nil}))

  def var_record(record),
    do: record |> Map.take(var_fields()) |> Value.plain() |> Map.put("assets", Map.new(@var_assets, &{&1, nil}))

  # Compare persisted definitions using the same schema normalization as the
  # literal reader. Legacy empty strings must not become edits on reimport.
  def stored_ref_record(record) do
    struct(Ref)
    |> Ref.changeset(Map.delete(ref_record(record), "assets"), :system)
    |> apply_valid!(record.uid)
    |> ref_record()
  end

  def stored_var_record(record) do
    struct(Var)
    |> Var.changeset(Map.delete(var_record(record), "assets"), %{id: 0})
    |> apply_valid!(record.key)
    |> var_record()
  end

  defp ordered(records, fun) when is_list(records) do
    records
    |> Enum.sort_by(&{&1.sequence || 0, Map.get(&1, :id)})
    |> Enum.with_index()
    |> Enum.map(fn {r, i} -> Map.put(fun.(r), "sequence", i) end)
  end

  def normalize_module!(definition) do
    attrs =
      definition
      |> Map.take(Enum.map(@module_fields, &to_string/1))
      |> Map.update!("name", &Value.object/1)
      |> Map.update!("namespace", &Value.object/1)
      |> Map.update!("help_text", &Value.object/1)

    normalized =
      Module.changeset(struct(Module), attrs, :system)
      |> apply_valid!(definition["uid"])
      |> Map.take(@module_fields)
      |> Value.plain()

    Map.merge(definition, normalized)
  end

  def validate_graph!(%{"format_version" => 1, "modules" => modules, "table_templates" => tables}) do
    unless is_list(modules) and is_list(tables), do: Error.raise!("bundle", "definitions must be lists")
    Enum.each(modules, &validate_kind!(&1, "module"))
    Enum.each(tables, &validate_kind!(&1, "table_template"))
    uids = Enum.map(modules, & &1["uid"])
    table_uids = Enum.map(tables, & &1["uid"])
    Value.unique!(uids ++ table_uids, "bundle UIDs")

    Enum.each(modules ++ tables, fn definition ->
      uid = Value.nonempty!(definition["uid"], "uid")
      Value.unique!(Enum.map(definition["vars"], & &1["key"]), uid <> ".var keys")

      if definition["kind"] == "module" do
        Value.unique!(Enum.map(definition["refs"], & &1["name"]), uid <> ".ref names")
        Value.unique!(Enum.map(definition["refs"], & &1["uid"]), uid <> ".ref UIDs")
        Value.unique!(definition["children"], uid <> ".children")

        if definition["children"] != [] and definition["multi"] != true,
          do: Error.raise!(uid, "children require multi true")

        Enum.each(definition["children"], fn child ->
          unless child in uids, do: Error.raise!(uid, "unresolved child #{child}")
        end)

        if definition["table_template"] && definition["table_template"] not in table_uids,
          do: Error.raise!(uid, "unresolved table template")
      end
    end)

    children = Enum.flat_map(modules, & &1["children"])
    Value.unique!(Enum.flat_map(modules, fn module -> Enum.map(module["refs"], & &1["uid"]) end), "bundle ref UIDs")
    Value.unique!(children, "child parents")
    graph = Map.new(modules, &{&1["uid"], &1["children"]})
    Enum.each(uids, &visit!(&1, graph, MapSet.new()))
    :ok
  end

  def validate_graph!(_), do: Error.raise!("bundle", "unsupported format_version or invalid envelope")

  defp validate_kind!(definition, kind) when is_map(definition) do
    unless definition["kind"] == kind and is_list(definition["vars"]), do: Error.raise!(kind, "invalid definition")

    if kind == "module" and not (is_list(definition["refs"]) and is_list(definition["children"])),
      do: Error.raise!(kind, "refs and children must be lists")
  end

  defp validate_kind!(_, kind), do: Error.raise!(kind, "expected a definition map")

  # Declaration order controls associations; database sequence gaps do not form
  # part of the portable definition. Top-level file order has no meaning.
  def canonicalize(bundle) do
    positions = Map.new(Enum.flat_map(bundle["modules"], fn module -> Enum.with_index(module["children"]) end))

    modules =
      Enum.map(bundle["modules"], fn module ->
        if Map.has_key?(positions, module["uid"]), do: Map.put(module, "sequence", positions[module["uid"]]), else: module
      end)

    bundle
    |> Map.put("modules", Enum.sort_by(modules, & &1["uid"]))
    |> Map.update!("table_templates", &Enum.sort_by(&1, fn table -> table["uid"] end))
  end

  defp visit!(uid, graph, seen) do
    if MapSet.member?(seen, uid), do: Error.raise!(uid, "cyclic child relationship")
    Enum.each(Map.fetch!(graph, uid), &visit!(&1, graph, MapSet.put(seen, uid)))
  end

  def block_schema!(type) do
    case Enum.find(Blocks.list_blocks(), fn {key, _} -> to_string(key) == type end) do
      {_, schema} ->
        if Code.ensure_loaded?(schema), do: schema, else: Error.raise!(type, "unsupported ref type")

      nil ->
        Error.raise!(type, "unknown ref type")
    end
  end

  def validate_fields!(schema, attrs, path) do
    Value.keys!(attrs, schema.__schema__(:fields) -- schema.__schema__(:primary_key), path)

    Enum.each(schema.__schema__(:embeds), fn name ->
      case Map.get(attrs, to_string(name)) do
        nil ->
          :ok

        values ->
          embedded = schema.__schema__(:embed, name).related
          Enum.each(List.wrap(values), &validate_fields!(embedded, &1, path <> "." <> to_string(name)))
      end
    end)
  end

  def apply_valid!(changeset, path) do
    if changeset.valid?,
      do: Changeset.apply_changes(changeset),
      else: Error.raise!(path, inspect(PolymorphicEmbed.traverse_errors(changeset, fn {msg, opts} -> {msg, opts} end)))
  end
end
