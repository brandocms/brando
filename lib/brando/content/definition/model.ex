defmodule Brando.Content.Definition.Model do
  @moduledoc false

  alias Brando.Content.Definition.{Error, Reader, Value}
  alias Brando.Content.{Container, Module, Palette, Ref, TableTemplate, Var}
  alias Brando.Content.Var.FollowLinkDefault
  alias Brando.Villain.Blocks
  alias Ecto.Changeset

  @module_fields ~w(uid name namespace help_text class code type svg color write_with_ai multi media_drop_child media_drop_ref sequence datasource datasource_module datasource_type datasource_query)a
  @ref_fields ~w(uid name description active collapsed sequence data)a
  @var_owners ~w(page_id block_id module_id table_template_id table_row_id global_set_id menu_item_id)a
  @var_assets ~w(image file video gallery palette identifier)
  @ref_assets ~w(image file video gallery)
  @palette_fields ~w(uid name namespace key global instructions)a
  @color_fields ~w(name key hex_value instructions)a
  @container_fields ~w(uid name namespace help_text type code allow_custom_palette palette_namespace)a

  # Each kind's list in a bundle, in the order an import writes them: a
  # container names its palette, a module its table template and children
  @kinds [
    {"palette", "palettes", Palette},
    {"container", "containers", Container},
    {"table_template", "table_templates", TableTemplate},
    {"module", "modules", Module}
  ]

  # What each kind declares besides `kind`, `uid` and `name`: options, and
  # sections (`templates` for `template`/`template_file`)
  @declarations %{
    module:
      {(@module_fields -- [:uid, :name, :code, :type, :media_drop_child, :media_drop_ref]) ++
         [:table_template, :media_drop], [:refs, :vars, :children, :templates]},
    table_template: {[], [:vars]},
    palette: {@palette_fields -- [:uid, :name], [:colors]},
    container: {(@container_fields -- [:uid, :name, :code, :type]) ++ [:palette], [:templates]}
  }

  def module_fields, do: @module_fields
  def container_fields, do: @container_fields

  @doc "The kinds of definition, in the order an import writes them."
  def kinds, do: Enum.map(@kinds, &elem(&1, 0))

  @doc ~S(The key of `kind`'s list in a bundle: "modules" for "module".)
  def bundle_key(kind), do: @kinds |> List.keyfind!(kind, 0) |> elem(1)

  @doc "The schema of `kind`."
  def schema(kind), do: @kinds |> List.keyfind!(kind, 0) |> elem(2)

  @doc """
  Every definition in `bundle`, in the order an import writes them:
  palettes, containers, table templates, modules.
  """
  def definitions(bundle), do: Enum.flat_map(@kinds, fn {_kind, key, _schema} -> bundle[key] || [] end)

  @doc """
  `bundle` with a list for every kind: a bundle, lockfile or stored batch
  written before palettes and containers were definitions has none.
  """
  def with_kinds(bundle), do: Enum.reduce(@kinds, bundle, fn {_kind, key, _schema}, acc -> Map.put_new(acc, key, []) end)

  @doc "How errors and plans name a definition: `module \"hero\"`."
  def subject(kind, uid), do: ~s(#{String.replace(kind, "_", " ")} "#{uid}")
  def ref_assets, do: @ref_assets
  def var_assets, do: @var_assets

  def var_fields do
    Var.__schema__(:fields) --
      (~w(id creator_id updated_by_id inserted_at updated_at edited_at)a ++
         @var_owners ++ Enum.map(@var_assets, &String.to_existing_atom(&1 <> "_id")) ++ [:form_id])
  end

  def from_specs!(specs, root) do
    names = Map.new(specs, &{&1.module, &1.options.uid})
    Value.unique!(Enum.map(specs, & &1.module), "source module names")
    Value.unique!(Enum.map(specs, & &1.options.uid), "definition UIDs")

    definitions =
      Enum.map(specs, fn spec ->
        Error.in_file(Error.file_label(spec.source, root), fn -> definition!(spec, root, names) end)
      end)

    grouped = Enum.group_by(definitions, & &1["kind"])
    bundle = Map.new(@kinds, fn {kind, key, _schema} -> {key, Map.get(grouped, kind, [])} end)
    bundle = canonicalize(Map.put(bundle, "format_version", 1))
    validate_graph!(bundle)
    bundle
  end

  defp definition!(spec, root, names) do
    opts = spec.options
    uid = Value.nonempty!(opts.uid, "uid")
    kind = Map.get(opts, :kind, :module) || :module
    declares!(kind, spec)
    definition!(kind, spec, uid, root, names)
  end

  defp declares!(kind, spec) do
    {options, sections} = Map.fetch!(@declarations, kind)
    label = String.replace(to_string(kind), "_", " ")
    extra = Map.keys(Map.reject(spec.options, fn {_k, v} -> v == nil end)) -- [:kind, :uid, :name | options]
    if extra != [], do: Error.raise!("unsupported #{label} options #{inspect(Enum.sort(extra))}")

    case Enum.filter(~w(refs vars children templates colors)a -- sections, &(Map.get(spec, &1, []) != [])) do
      [] -> :ok
      declared -> Error.raise!("#{label} definitions don't declare #{Enum.map_join(declared, ", ", &section_name/1)}")
    end
  end

  defp section_name(:templates), do: "a template"
  defp section_name(section), do: to_string(section)

  defp definition!(:table_template, spec, uid, _root, _names) do
    vars = spec.vars |> Enum.with_index() |> Enum.map(fn {var, index} -> var!(var, index, uid) end)
    %{"kind" => "table_template", "uid" => uid, "name" => Value.nonempty!(spec.options.name, "name"), "vars" => vars}
  end

  defp definition!(:palette, spec, uid, _root, _names) do
    colors =
      Enum.map(spec.colors, fn color ->
        color |> Map.take(@color_fields) |> Map.update!(:key, &to_string/1) |> Value.plain()
      end)

    spec.options
    |> Map.take(@palette_fields)
    |> Map.merge(%{uid: uid, colors: colors})
    |> Value.plain()
    |> normalize_palette!(nil)
  end

  defp definition!(:container, spec, uid, root, names) do
    opts = spec.options
    {engine, code} = template!(spec.templates, spec.source, root)

    opts
    |> Map.take(@container_fields)
    |> Map.merge(%{uid: uid, type: engine, code: code})
    |> Value.plain()
    |> Map.put("palette", resolve!(opts[:palette], names))
    |> normalize_container!(nil)
  end

  defp definition!(:module, spec, uid, root, names) do
    opts = spec.options
    vars = spec.vars |> Enum.with_index() |> Enum.map(fn {var, index} -> var!(var, index, uid) end)

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
    |> Map.merge(media_drop(opts[:media_drop], names))
    |> Map.merge(%{
      "type" => to_string(engine),
      "code" => code,
      "refs" => refs,
      "vars" => vars,
      "children" => children,
      "table_template" => resolve!(opts[:table_template], names),
      "kind" => "module"
    })
    |> normalize_module!(nil)
  end

  defp media_drop(nil, _names), do: %{}

  defp media_drop(media_drop, names),
    do: %{"media_drop_child" => resolve!(media_drop[:child], names), "media_drop_ref" => to_string(media_drop[:ref])}

  defp template!([%{engine: engine, source: source, file: true}], file, root),
    do: {engine, Reader.template_file!(source, file, root)}

  defp template!([%{engine: engine, source: source}], _, _), do: {engine, source}
  defp template!(_, _file, _), do: Error.raise!("declare exactly one template or template_file")

  defp resolve!(nil, _names), do: nil

  defp resolve!(reference, names) do
    reference = to_string(reference)
    Map.get(names, reference, reference)
  end

  defp ref!(spec, index, uid) do
    name = to_string(spec.name)
    type = to_string(spec.type)
    subject = ~s(ref "#{name}")
    block_schema = block_schema!(type, subject)
    config = Value.object(spec[:config])
    defaults = Value.object(spec[:default])

    if Enum.any?(Map.keys(config), &Map.has_key?(defaults, &1)),
      do: Error.raise!(subject, "config and default overlap")

    data = Map.merge(config, defaults)
    validate_fields!(Elixir.Module.concat(block_schema, Data), data, subject)
    references = if type == "markdown_source", do: Map.take(data, ~w(source_id version_id)), else: %{}

    Enum.each(references, fn {field, token} ->
      if token != nil, do: Value.nonempty!(token, subject <> ": " <> field)
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
    |> apply_valid!(nil)
    |> ref_record()
    |> update_in(["data", "data"], &Map.merge(&1, references))
    |> Map.put("assets", assets!(spec[:assets], @ref_assets, subject))
  end

  defp var!(spec, index, _uid) do
    fields = var_fields()
    key = to_string(spec.key)
    subject = ~s(var "#{key}")
    settings = Value.object(spec[:settings])
    Value.keys!(settings, fields -- [:key, :type], subject <> ": settings")
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

    params =
      if spec[:options] in [nil, :__unset__],
        do: params,
        else: Map.put(params, "options", options!(spec.options, subject))

    assets = assets!(spec[:assets], @var_assets, subject)

    {params, assets} =
      case Map.get(spec, :default, :__unset__) do
        :__unset__ -> {params, assets}
        default when type in ~w(image file video gallery) -> {params, Map.put(assets, type, default)}
        default -> {Map.put(params, if(type == "boolean", do: "value_boolean", else: "value"), default), assets}
      end

    validate_fields!(Var, params, subject)

    params
    |> legacy_link_default(assets["identifier"])
    # Creator is persistence metadata, supplied by the import actor. A sentinel
    # satisfies that required field while normalizing without any database I/O.
    |> then(&Var.changeset(struct(Var), &1, %{id: 0}, nil, validate_var_values: false))
    |> apply_valid!(nil)
    |> var_record(assets["identifier"])
    |> Map.put("assets", assets)
  end

  # Before `link_default_type`, an empty link of type `:identifier` was how a
  # var opened on Content; brando_224 gives stored ones that default, and a
  # file written that way reads the same.
  defp legacy_link_default(%{"type" => "link", "link_type" => kind} = params, identifier)
       when kind in [:identifier, "identifier"] and not is_map_key(params, "link_default_type") do
    if blank?(Map.get(params, "value")) and identifier in [nil, ""],
      do: Map.put(params, "link_default_type", "identifier"),
      else: params
  end

  defp legacy_link_default(params, _identifier), do: params

  # As brando_224's backfill reads an empty value
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(value), do: is_nil(value)

  defp options!(options, _subject) when is_list(options) do
    Enum.map(options, fn
      {label, value} -> %{"label" => label, "value" => value}
      option -> Value.object(option)
    end)
  end

  defp options!(_, subject), do: Error.raise!(subject, "options must be a list")

  defp assets!(value, allowed, path) do
    assets = Value.object(value)
    Value.keys!(assets, allowed, path <> ": assets")
    Enum.each(assets, fn {key, value} -> if value != nil, do: Value.nonempty!(value, path <> ": assets." <> key) end)
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

  @doc """
  A palette as a definition. Its colours are the whole set, in order. Blank
  text reads as nil, as the changeset casts it, so a palette saved with an
  empty instructions field equals its file.
  """
  def palette_record(record) do
    record
    |> Map.take(@palette_fields)
    |> Value.plain()
    |> Map.merge(%{
      "kind" => "palette",
      "global" => Map.get(record, :global) || false,
      "colors" => Enum.map(record.colors || [], &(&1 |> Map.take(@color_fields) |> Value.plain() |> blank_nil()))
    })
    |> blank_nil()
  end

  @doc "A container as a definition; `palette` is its default palette's uid, or nil."
  def container_record(record, palette) do
    record
    |> Map.take(@container_fields)
    |> Value.plain()
    |> Map.merge(%{
      "kind" => "container",
      "allow_custom_palette" => Map.get(record, :allow_custom_palette) || false,
      "palette" => palette
    })
    |> blank_nil()
  end

  defp blank_nil(map), do: Map.new(map, fn {key, value} -> {key, if(value == "", do: nil, else: value)} end)

  # Read through the schema's changeset, as a save in the admin is: errors
  # name the definition, or nothing more than its file (`nil`) as it is read
  def normalize_palette!(definition, subject \\ :uid) do
    # Status is the environment's, as it is for nothing in a module
    attrs =
      definition
      |> Map.take(Enum.map(@palette_fields, &to_string/1) ++ ["colors"])
      |> Map.put("status", "published")

    struct(Palette)
    |> Palette.changeset(attrs, %{id: 0})
    |> apply_valid!(if(subject == :uid, do: subject("palette", definition["uid"]), else: subject))
    |> palette_record()
  end

  def normalize_container!(definition, subject \\ :uid) do
    attrs = Map.take(definition, Enum.map(@container_fields, &to_string/1))

    struct(Container)
    |> Container.changeset(attrs, :system)
    |> apply_valid!(if(subject == :uid, do: subject("container", definition["uid"]), else: subject))
    |> container_record(definition["palette"])
  end

  def ref_record(record),
    do: record |> Map.take(@ref_fields) |> Value.plain() |> Map.put("assets", Map.new(@ref_assets, &{&1, nil}))

  def var_record(record, identifier \\ nil) do
    linked = identifier || Map.get(record, :identifier_id)

    record
    |> open_on_default_tab(linked)
    |> Map.take(var_fields())
    |> Value.plain()
    |> Map.put("assets", Map.new(@var_assets, &{&1, nil}))
  end

  # Every copy of an empty link starts on its default tab
  # (`FollowLinkDefault.put/1`), so a definition's own link type there is no
  # part of it: the record has the default, whatever the file or the stored
  # var holds.
  defp open_on_default_tab(%{type: :link} = var, nil), do: FollowLinkDefault.put(var)

  defp open_on_default_tab(var, _linked), do: var

  # Compare persisted definitions using the same schema normalization as the
  # literal reader. Legacy empty strings must not become edits on reimport.
  # `subject` names the module holding it in errors
  def stored_ref_record(record, subject \\ nil) do
    struct(Ref)
    |> Ref.changeset(Map.delete(ref_record(record), "assets"), :system)
    |> apply_valid!(subject)
    |> ref_record()
  end

  # A stored value predating a validation is read as it is: one old colour
  # must not stop every snapshot, export and import.
  def stored_var_record(record, subject \\ nil) do
    struct(Var)
    |> Var.changeset(Map.delete(var_record(record), "assets"), %{id: 0}, nil,
      validate_colors: false,
      validate_var_values: false,
      sanitize_rich_text: false
    )
    |> apply_valid!(subject)
    |> var_record(Map.get(record, :identifier_id))
  end

  defp ordered(records, fun) when is_list(records) do
    records
    |> Enum.sort_by(&{&1.sequence || 0, Map.get(&1, :id)})
    |> Enum.with_index()
    |> Enum.map(fn {r, i} -> Map.put(fun.(r), "sequence", i) end)
  end

  # Errors name the module, or nothing more than its file (`nil`) as it is read
  def normalize_module!(definition, subject \\ :uid) do
    attrs =
      definition
      |> Map.take(Enum.map(@module_fields, &to_string/1))
      |> Map.update!("name", &Value.object/1)
      |> Map.update!("namespace", &Value.object/1)
      |> Map.update!("help_text", &Value.object/1)
      # Left out, `multi` means false — the column's default. Kept as nil, a
      # stored module (false) never digests like its file, and every import
      # after the first is refused as "target changed since export".
      |> Map.update("multi", false, &(&1 || false))

    normalized =
      Module.changeset(struct(Module), attrs, :system)
      |> apply_valid!(if(subject == :uid, do: ~s(module "#{definition["uid"]}"), else: subject))
      |> Map.take(@module_fields)
      |> Value.plain()

    Map.merge(definition, normalized)
  end

  def validate_graph!(%{"format_version" => 1, "modules" => _, "table_templates" => _} = bundle) do
    bundle = with_kinds(bundle)

    Enum.each(@kinds, fn {kind, key, _schema} ->
      unless is_list(bundle[key]), do: Error.raise!("bundle", "definitions must be lists")
      Enum.each(bundle[key], &validate_kind!(&1, kind))
    end)

    modules = bundle["modules"]
    uids = Enum.map(modules, & &1["uid"])
    table_uids = Enum.map(bundle["table_templates"], & &1["uid"])
    Value.unique!(Enum.map(definitions(bundle), & &1["uid"]), "bundle UIDs")

    Enum.each(definitions(bundle), &validate_definition!(&1, uids, table_uids))
    Enum.each(modules, &validate_media_drop!(&1, modules))

    children = Enum.flat_map(modules, & &1["children"])
    Value.unique!(Enum.flat_map(modules, fn module -> Enum.map(module["refs"], & &1["uid"]) end), "bundle ref UIDs")
    Value.unique!(children, "child parents")
    graph = Map.new(modules, &{&1["uid"], &1["children"]})
    Enum.each(uids, &visit!(&1, graph, MapSet.new()))
    :ok
  end

  def validate_graph!(_), do: Error.raise!("bundle", "unsupported format_version or invalid envelope")

  defp validate_definition!(%{"kind" => "palette"} = definition, _uids, _table_uids) do
    uid = Value.nonempty!(definition["uid"], "uid")
    Value.unique!(Enum.map(definition["colors"], & &1["key"]), uid <> ".color keys")
  end

  defp validate_definition!(%{"kind" => "container"} = definition, _uids, _table_uids) do
    uid = Value.nonempty!(definition["uid"], "uid")
    if definition["palette"] != nil, do: Value.nonempty!(definition["palette"], uid <> ".palette")
  end

  defp validate_definition!(definition, uids, table_uids) do
    uid = Value.nonempty!(definition["uid"], "uid")
    Value.unique!(Enum.map(definition["vars"], & &1["key"]), uid <> ".var keys")

    if definition["kind"] == "module", do: validate_module!(definition, uid, uids, table_uids)
  end

  defp validate_module!(definition, uid, uids, table_uids) do
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

  # The child a `media_drop` names is one of the module's own, and holds the
  # ref as a media, picture or video ref (`Module.media_drop_problem/3`)
  defp validate_media_drop!(%{"media_drop_child" => child, "media_drop_ref" => ref} = definition, modules)
       when is_binary(child) do
    children =
      for module <- modules, module["uid"] in definition["children"] do
        %{
          uid: module["uid"],
          refs: Enum.map(module["refs"], &%{name: &1["name"], type: &1["data"]["type"]})
        }
      end

    case Module.media_drop_problem(children, child, ref) do
      nil -> :ok
      issue -> Error.raise!(definition["uid"], "media_drop: " <> Module.describe_media_drop_issue(issue))
    end
  end

  defp validate_media_drop!(_definition, _modules), do: :ok

  defp validate_kind!(%{"kind" => "palette"} = definition, "palette") do
    unless is_list(definition["colors"]), do: Error.raise!("palette", "colors must be a list")
  end

  defp validate_kind!(%{"kind" => "container"} = definition, "container") do
    unless is_binary(definition["code"]), do: Error.raise!("container", "invalid definition")
  end

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

    bundle = Map.put(bundle, "modules", modules)

    Enum.reduce(@kinds, bundle, fn {_kind, key, _schema}, bundle ->
      if Map.has_key?(bundle, key), do: Map.update!(bundle, key, &sort_by_uid/1), else: bundle
    end)
  end

  defp sort_by_uid(definitions), do: Enum.sort_by(definitions, & &1["uid"])

  defp visit!(uid, graph, seen) do
    if MapSet.member?(seen, uid), do: Error.raise!(uid, "cyclic child relationship")
    Enum.each(Map.fetch!(graph, uid), &visit!(&1, graph, MapSet.put(seen, uid)))
  end

  def block_schema!(type, subject \\ nil) do
    case Enum.find(Blocks.list_blocks(), fn {key, _} -> to_string(key) == type end) do
      {_, schema} ->
        if Code.ensure_loaded?(schema),
          do: schema,
          else: Error.raise!(subject || type, ref_type(subject, type, "unsupported"))

      nil ->
        Error.raise!(subject || type, ref_type(subject, type, "unknown"))
    end
  end

  defp ref_type(nil, _type, problem), do: problem <> " ref type"
  defp ref_type(_subject, type, problem), do: "#{problem} ref type #{inspect(type)}"

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

  # `subject` names what holds the changeset in errors (`module "uid"`), or
  # is nil within a definition's file; a var or ref names itself
  def apply_valid!(changeset, subject) do
    if changeset.valid?,
      do: Changeset.apply_changes(changeset),
      else: Error.changeset!(changeset, subject)
  end
end
