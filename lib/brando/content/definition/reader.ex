defmodule Brando.Content.Definition.Reader do
  @moduledoc false

  alias Brando.Content.Definition.{Dsl, Error}

  def files!(directory) do
    directory
    |> File.ls!()
    |> Enum.sort()
    |> Enum.flat_map(fn name ->
      path = Path.join(directory, name)

      case File.lstat!(path).type do
        :directory -> files!(path)
        :regular -> if Path.extname(path) == ".exs", do: [path], else: []
        _ -> Error.raise!(path, "symlinks and special files are not supported")
      end
    end)
  end

  def read!(path) do
    source = regular_file!(path)

    case Code.string_to_quoted(source, file: path) do
      {:ok, {:defmodule, _, [name, [do: body]]}} ->
        spec = %{
          source: Path.expand(path),
          module: module_name!(name),
          options: %{},
          refs: [],
          vars: [],
          templates: [],
          children: []
        }

        {spec, used?} = Enum.reduce(statements(body), {spec, false}, &declaration!(&1, &2, path))
        unless used?, do: Error.raise!(path, "expected use Brando.Content.Definition")
        Map.update!(spec, :options, &validate!(&1, Dsl.options(), path))

      {:ok, _} ->
        Error.raise!(path, "expected one defmodule declaration")

      {:error, reason} ->
        Error.raise!(path, "invalid Elixir syntax: #{inspect(reason)}")
    end
  end

  def regular_file!(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular}} -> File.read!(path)
      _ -> Error.raise!(path, "expected a regular file (symlinks are not supported)")
    end
  end

  def template_file!(file, source, root) do
    unless Path.type(file) == :relative, do: Error.raise!(source, "template_file must be relative")
    target = Path.expand(file, Path.dirname(source))
    root = Path.expand(root)

    unless String.starts_with?(target, root <> "/"),
      do: Error.raise!(source, "template_file escapes the definition directory")

    # Reject symlinked parent directories as well as the final file.
    target
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.reduce(root, fn part, parent ->
      path = Path.join(parent, part)

      case File.lstat(path) do
        {:ok, %{type: type}} when type in [:directory, :regular] -> path
        _ -> Error.raise!(path, "expected a regular template path")
      end
    end)
    |> regular_file!()
  end

  defp declaration!({:use, _, [name]}, {spec, false}, path) do
    if module_name!(name) != "Elixir.Brando.Content.Definition", do: Error.raise!(path, "unsupported use declaration")
    {spec, true}
  end

  defp declaration!({section, _, [[do: body]]}, {spec, used?}, path) when section in [:refs, :vars, :children] do
    if Map.get(spec, {:seen, section}), do: Error.raise!(path, "duplicate #{section} section")
    entries = Enum.map(statements(body), &entity!(&1, section, path))
    {spec |> Map.put(section, entries) |> Map.put({:seen, section}, true), used?}
  end

  defp declaration!({name, _, [engine, code]}, {spec, used?}, path) when name in [:template, :template_file] do
    engine = literal!(engine, path)
    code = literal!(code, path)

    unless engine in [:heex, :liquid] and is_binary(code),
      do: Error.raise!(path, "template requires :heex/:liquid and a string")

    {Map.update!(spec, :templates, &(&1 ++ [%{engine: engine, source: code, file: name == :template_file}])), used?}
  end

  defp declaration!({name, _, [value]}, {spec, used?}, path) do
    unless Keyword.has_key?(Dsl.options(), name), do: Error.raise!(path, "unknown declaration #{name}")
    if Map.has_key?(spec.options, name), do: Error.raise!(path, "duplicate #{name} declaration")
    {put_in(spec.options[name], literal!(value, path)), used?}
  end

  defp declaration!(ast, _, path),
    do: Error.raise!(path, "expected a literal DSL declaration, got #{Macro.to_string(ast)}")

  defp entity!({:child, _, [definition]}, :children, path), do: %{definition: literal!(definition, path)}

  defp entity!({name, _, args}, section, path) when name in [:ref, :var] and section in [:refs, :vars] do
    expected = if section == :refs, do: :ref, else: :var
    unless name == expected and length(args) in [2, 3], do: Error.raise!(path, "invalid #{section} declaration")
    [key, type | rest] = args
    key_field = if name == :ref, do: :name, else: :key
    fields = %{key_field => literal!(key, path), type: literal!(type, path)}

    fields =
      case rest do
        [] -> fields
        [[do: body]] -> Enum.reduce(statements(body), fields, &field!(&1, &2, path))
        _ -> Error.raise!(path, "use a do block for #{name} settings")
      end

    validate!(fields, if(name == :ref, do: Dsl.ref_schema(), else: Dsl.var_schema()), path)
  end

  defp entity!(ast, section, path), do: Error.raise!(path, "invalid #{section} entry: #{Macro.to_string(ast)}")

  defp field!({name, _, [value]}, fields, path) do
    if Map.has_key?(fields, name), do: Error.raise!(path, "duplicate #{name} setting")
    Map.put(fields, name, literal!(value, path))
  end

  defp field!(ast, _, path), do: Error.raise!(path, "expected a literal setting: #{Macro.to_string(ast)}")

  defp validate!(fields, schema, path) do
    case Spark.Options.validate(Map.to_list(fields), schema) do
      {:ok, opts} -> Map.new(opts)
      {:error, error} -> Error.raise!(path, Exception.message(error))
    end
  end

  defp statements({:__block__, _, nodes}), do: nodes
  defp statements(nil), do: []
  defp statements(node), do: [node]

  defp module_name!({:__aliases__, _, parts}), do: "Elixir." <> Enum.map_join(parts, ".", &Atom.to_string/1)
  defp module_name!(_), do: Error.raise!("definition", "expected a module name")

  defp literal!({:%{}, _, pairs}, path), do: Map.new(pairs, fn {k, v} -> {literal!(k, path), literal!(v, path)} end)
  defp literal!({:{}, _, values}, path), do: values |> Enum.map(&literal!(&1, path)) |> List.to_tuple()
  defp literal!({:__aliases__, _, _} = name, _path), do: module_name!(name)

  defp literal!({sigil, _, [{:<<>>, _, [text]}, []]}, _path) when sigil in [:sigil_S, :sigil_s] and is_binary(text),
    do: text

  defp literal!({:-, _, [number]}, _path) when is_number(number), do: -number
  defp literal!({left, right}, path), do: {literal!(left, path), literal!(right, path)}
  defp literal!(values, path) when is_list(values), do: Enum.map(values, &literal!(&1, path))
  defp literal!(value, _path) when is_binary(value) or is_number(value) or is_atom(value), do: value
  defp literal!(ast, path), do: Error.raise!(path, "only literals are supported: #{Macro.to_string(ast)}")
end
