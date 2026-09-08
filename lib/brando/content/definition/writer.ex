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

    lock = Map.take(bundle, ~w(format_version source baseline references))
    temporary = path <> ".tmp-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

    try do
      File.write!(temporary, Jason.encode!(lock, pretty: true) <> "\n", [:exclusive])
      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end

    :ok
  end

  def files(bundle) do
    definitions = bundle["modules"] ++ bundle["table_templates"]
    files = Enum.flat_map(definitions, &definition_files/1)
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
      Enum.each(files, fn {name, body} -> File.write!(Path.join(staging, name), body) end)
      File.rename!(staging, directory)
    after
      File.rm_rf(staging)
    end

    Map.keys(files) |> Enum.sort()
  end

  defp definition_files(definition) do
    key = String.slice(Value.digest(definition["uid"]), 0, 16)
    name = if definition["kind"] == "module", do: "module_" <> key, else: "table_" <> key
    template_name = name <> if(definition["type"] == "heex", do: ".heex", else: ".liquid")
    module_name = "BrandoDefinitions.D" <> key

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
        do: ["\n  template_file :", definition["type"], ", ", literal(template_name), "\n"],
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
      ~w(kind uid name namespace help_text class svg color multi sequence datasource datasource_module datasource_type datasource_query table_template description active collapsed config default assets label placeholder instructions width placement new_row options settings)a,
      &{&1, 1}
    ) ++
      [ref: 2, var: 2, child: 1, template_file: 2]
  end
end
