defmodule Brando.Content.Definition.Writer do
  @moduledoc false

  alias Brando.Content.Definition.{Error, Model, Value}

  def write_lock!(bundle, directory) do
    path = Path.join(directory, "modules.lock.json")

    case File.lstat(path) do
      {:error, :enoent} -> :ok
      {:ok, %{type: :regular}} -> :ok
      _ -> Error.raise!(path, "expected a regular lockfile")
    end

    lock = bundle |> Map.take(~w(format_version source baseline references)) |> Map.merge(listed_files(path))
    temporary = path <> ".tmp-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

    try do
      File.write!(temporary, Jason.encode!(lock, pretty: true) <> "\n", [:exclusive])
      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end

    :ok
  end

  # An export lists its files in the lock. Moving the baseline forward (an
  # import, the dev watcher) changes no file, so the list stays as it is.
  defp listed_files(path) do
    with {:ok, body} <- File.read(path),
         {:ok, %{"files" => files}} when is_list(files) <- Jason.decode(body) do
      %{"files" => files}
    else
      _ -> %{}
    end
  end

  def files(bundle) do
    definitions = bundle["modules"] ++ bundle["table_templates"]
    names = names(definitions)
    files = Enum.flat_map(definitions, &definition_files(&1, names[identity(&1)]))
    Value.unique!(Enum.map(files, &elem(&1, 0)), "output filenames")

    lock =
      bundle |> Map.take(~w(format_version source baseline references)) |> Map.put("files", Enum.map(files, &elem(&1, 0)))

    Map.new([{"modules.lock.json", Jason.encode!(lock, pretty: true) <> "\n"} | files])
  end

  def write!(bundle, directory) do
    files = files(bundle)

    if File.exists?(directory),
      do: Error.raise!(directory, "export requires a new directory; existing authored files are never overwritten")

    staging = directory <> ".tmp-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    File.mkdir_p!(staging)

    try do
      Enum.each(files, fn {name, body} ->
        path = Path.join(staging, name)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, body)
      end)

      File.rename!(staging, directory)
    after
      File.rm_rf(staging)
    end

    Map.keys(files) |> Enum.sort()
  end

  # Files are named for people: `<namespace>/<name>` in the admin language, and
  # table templates under `tables/`. A child module lives in a folder beside its
  # parent, `<parent>/<child>`, like `foo.ex` and `foo/` in Elixir. Identity is
  # the `uid` inside each file, so these names only have to be unique within one
  # export. Definitions that would share a path, or a module name, get a short
  # UID digest appended.
  defp names(definitions) do
    parents =
      for %{"kind" => "module"} = parent <- definitions, child <- parent["children"] || [], into: %{} do
        {child, parent["uid"]}
      end

    paths = paths(definitions, parents, %{})

    modules =
      definitions
      |> Enum.map(&{identity(&1), module_name(paths[identity(&1)])})
      |> disambiguate(definitions, & &1, fn module, key -> module <> "D" <> key end)

    Map.new(definitions, &{identity(&1), %{path: paths[identity(&1)], module: modules[identity(&1)]}})
  end

  # Top-down, so a child follows its parent's final path, digest included
  defp paths([], _parents, assigned), do: assigned

  defp paths(pending, parents, assigned) do
    {ready, waiting} = Enum.split_with(pending, &(is_nil(parent(&1, parents)) or assigned[parent(&1, parents)]))
    if ready == [], do: Error.raise!("children", "child modules form a cycle")

    named = Enum.map(ready, &{identity(&1), readable_path(&1, assigned[parent(&1, parents)])})
    taken = Enum.frequencies_by(Map.values(assigned) ++ Enum.map(named, &elem(&1, 1)), &String.downcase/1)
    keys = Map.new(ready, &{identity(&1), key(&1)})

    assigned =
      Enum.reduce(named, assigned, fn {identity, path}, assigned ->
        path = if taken[String.downcase(path)] > 1, do: path <> "-" <> keys[identity], else: path
        Map.put(assigned, identity, path)
      end)

    paths(waiting, parents, assigned)
  end

  defp parent(%{"kind" => "module", "uid" => uid}, parents) do
    if parent = parents[uid], do: {"module", parent}
  end

  defp parent(_definition, _parents), do: nil

  defp disambiguate(named, definitions, compare, suffix) do
    counts = Enum.frequencies_by(named, fn {_, name} -> compare.(name) end)
    keys = Map.new(definitions, &{identity(&1), key(&1)})

    Map.new(named, fn {identity, name} ->
      if counts[compare.(name)] > 1, do: {identity, suffix.(name, keys[identity])}, else: {identity, name}
    end)
  end

  defp identity(definition), do: {definition["kind"], definition["uid"]}
  defp key(definition), do: String.slice(Value.digest(definition["uid"]), 0, 8)

  defp readable_path(%{"kind" => "table_template"} = definition, _parent_path),
    do: Path.join("tables", slug(definition["name"]) || "table-" <> key(definition))

  defp readable_path(definition, parent_path) do
    name = slug(definition["name"]) || "module-" <> key(definition)

    case {parent_path, slug(definition["namespace"])} do
      {nil, nil} -> name
      {nil, namespace} -> Path.join(namespace, name)
      {parent_path, _} -> Path.join(parent_path, name)
    end
  end

  # Names are locale maps (or plain strings on older records)
  defp slug(value) when is_map(value) do
    language = to_string(Brando.config(:default_admin_language) || "en")
    present = value |> Enum.reject(fn {_, text} -> text in [nil, ""] end) |> Enum.sort()

    case Map.new(present) do
      %{^language => text} -> slug(text)
      %{"en" => text} -> slug(text)
      _ -> present |> List.first({nil, nil}) |> elem(1) |> slug()
    end
  end

  defp slug(value) when is_binary(value) do
    case Brando.Utils.slugify(value) do
      slug when slug in [nil, ""] -> nil
      slug -> slug
    end
  end

  defp slug(_), do: nil

  defp module_name(path) do
    segments =
      path
      |> Path.split()
      |> Enum.map(fn segment ->
        segment = segment |> String.replace("-", "_") |> Macro.camelize()
        if segment =~ ~r/^[A-Z]/, do: segment, else: "D" <> segment
      end)

    Enum.join(["BrandoDefinitions" | segments], ".")
  end

  defp definition_files(definition, %{path: name, module: module_name}) do
    template_name = name <> if(definition["type"] == "heex", do: ".heex", else: ".liquid")

    fields =
      if definition["kind"] == "module",
        do: Model.module_fields() -- [:type, :code],
        else: [:uid, :name]

    header = ["defmodule ", module_name, " do\n  use Brando.Content.Definition\n\n"]
    kind = if definition["kind"] == "table_template", do: "  kind :table_template\n", else: ""

    attributes =
      Enum.map(fields, fn field -> ["  ", to_string(field), " ", literal(definition[to_string(field)]), "\n"] end)

    table =
      if definition["table_template"], do: ["  table_template ", literal(definition["table_template"]), "\n"], else: ""

    refs = section("refs", Enum.map(definition["refs"] || [], &ref/1))
    vars = section("vars", Enum.map(definition["vars"], &var/1))
    children = section("children", Enum.map(definition["children"] || [], &["    child ", literal(&1), "\n"]))

    template =
      if definition["kind"] == "module",
        do: ["\n  template_file :", definition["type"], ", ", literal(Path.basename(template_name)), "\n"],
        else: ""

    source = IO.iodata_to_binary([header, kind, attributes, table, refs, vars, children, template, "end\n"])
    source = source |> Code.format_string!(locals_without_parens: locals(), line_length: 100) |> IO.iodata_to_binary()
    files = [{name <> ".exs", source <> "\n"}]
    if definition["kind"] == "module", do: files ++ [{template_name, definition["code"]}], else: files
  end

  defp ref(ref) do
    schema = Model.block_schema!(ref["data"]["type"])
    protected = Enum.map(schema.protected_attrs(), &to_string/1)
    {defaults, config} = Map.split(ref["data"]["data"], protected)

    [
      "    ref ",
      literal(ref["name"]),
      ", ",
      literal(ref["data"]["type"]),
      " do\n",
      Enum.map(~w(uid description active collapsed), &["      ", &1, " ", literal(ref[&1]), "\n"]),
      "      config ",
      literal(config),
      "\n      default ",
      literal(defaults),
      "\n      assets ",
      literal(ref["assets"]),
      "\n    end\n"
    ]
  end

  defp var(var) do
    visible = ~w(label placeholder instructions width placement new_row options)
    default_key = if var["type"] == "boolean", do: "value_boolean", else: "value"
    settings = Map.drop(var, visible ++ ~w(key type assets sequence) ++ [default_key])

    default =
      if var["type"] in ~w(image file video gallery),
        do: "",
        else: ["      default ", literal(var[default_key]), "\n"]

    # Media vars still carry the generic value column; preserve it in settings.
    settings =
      if var["type"] in ~w(image file video gallery), do: Map.put(settings, default_key, var[default_key]), else: settings

    [
      "    var ",
      literal(var["key"]),
      ", ",
      literal(var["type"]),
      " do\n",
      Enum.map(visible, &["      ", &1, " ", literal(var[&1]), "\n"]),
      default,
      "      settings ",
      literal(settings),
      "\n      assets ",
      literal(var["assets"]),
      "\n    end\n"
    ]
  end

  defp section(_, []), do: ""
  defp section(name, entries), do: ["\n  ", name, " do\n", entries, "  end\n"]

  defp literal(value) when is_map(value),
    do: "%{" <> Enum.map_join(Enum.sort(value), ", ", fn {k, v} -> literal(k) <> " => " <> literal(v) end) <> "}"

  defp literal(value) when is_list(value), do: "[" <> Enum.map_join(value, ", ", &literal/1) <> "]"
  defp literal(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)

  defp locals do
    Enum.map(
      ~w(kind uid name namespace help_text class svg color write_with_ai multi sequence datasource datasource_module datasource_type datasource_query table_template description active collapsed config default assets label placeholder instructions width placement new_row options settings)a,
      &{&1, 1}
    ) ++
      [ref: 2, var: 2, child: 1, template_file: 2]
  end
end
