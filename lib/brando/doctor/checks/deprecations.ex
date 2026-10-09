defmodule Brando.Doctor.Checks.Deprecations do
  @moduledoc """
  Calls to deprecated Brando functions and macros (those marked
  `@deprecated`) in the project's `lib/`, and references to the modules
  renamed in 0.55, whose old names are deprecated: a router's
  `get "/robots.txt", Brando.SEOController, :robots`, say, or the same
  route as `SEOController` inside `scope "/", Brando do`.

  The source is read as code, not text: aliases (`alias Brando.HTML`,
  `alias Brando.{HTML, Utils}`, `as:`), imports and pipes are followed, so
  `picture_tag(…)` after `import Brando.HTML` is found, and a function of the
  same name in another module is not. An alias reaches the code after it in
  its own module or function, as the compiler reads it. Calls made through
  `apply/3` or a variable module cannot be seen.

  Reads the source tree, so it is skipped in a release.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Deprecated.LexicalAliases
  alias Brando.Deprecated.RenamedModules
  alias Brando.Doctor.Context

  @impl true
  def id, do: "deprecations"

  @impl true
  def label, do: dgettext("doctor", "Deprecations")

  @impl true
  def needs_source?, do: true

  @impl true
  def run(%Context{root: root}) do
    lib = Path.join(root, "lib")

    lib
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(&scan_file(&1, deprecated()))
    |> Enum.map(fn finding -> %{finding | file: Path.relative_to(finding.file, root)} end)
    |> evaluate()
  end

  @doc "Turns findings (`%{file, line, call, reason}`) into a result."
  def evaluate([]), do: ok(dgettext("doctor", "none in lib/"))

  def evaluate(findings) do
    files = findings |> Enum.map(& &1.file) |> Enum.uniq() |> length()

    warning(
      dngettext("doctor", "%{count} call in lib/", "%{count} calls in lib/", length(findings)) <>
        " (" <> dngettext("doctor", "%{count} file", "%{count} files", files) <> ")",
      fix: dgettext("doctor", "replace them as the deprecation notes say (mix brando.doctor --verbose)"),
      items: Enum.map(findings, &"#{&1.file}:#{&1.line} #{&1.call}: #{&1.reason}")
    )
  end

  @doc """
  Brando's deprecated functions and macros: `%{{module, name, arity} => reason}`.
  """
  def deprecated do
    {:ok, modules} = :application.get_key(:brando, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__info__, 1),
        {{name, arity}, reason} <- module.__info__(:deprecated),
        into: %{},
        do: {{module, name, arity}, reason}
  end

  @doc "Finds calls in `deprecated` (see `deprecated/0`) in the file at `path`."
  def scan_file(path, deprecated) do
    case path |> File.read!() |> Code.string_to_quoted(file: path, columns: false) do
      {:ok, ast} -> ast |> scan(deprecated) |> Enum.map(&Map.put(&1, :file, path))
      {:error, _} -> []
    end
  rescue
    # A file the scanner cannot follow is not worth failing the check over
    _ -> []
  end

  @doc "Finds calls in `deprecated` in quoted code."
  def scan(ast, deprecated) do
    ast = RenamedModules.mark_scoped_routes(ast)
    imports = collect_imports(ast, deprecated)

    {_ast, found} =
      Macro.prewalk(ast, [], fn
        # Declaring an alias uses nothing: what is reached through it is
        # reported where it is used (`alias Brando.Meta` for `Meta.HTML`)
        {:alias, _, _}, acc ->
          {:ok, acc}

        # A route inside `scope "/", Brando do`: Phoenix joins the scope's
        # alias to the plug's
        {:match, [{:scope_alias, scope} | _] = meta, [verb, path, {:__aliases__, _, _} = plug | rest]}, acc ->
          {{:match, meta, [verb, path | rest]}, scoped_route(scope, plug, acc)}

        {verb, [{:scope_alias, scope} | _] = meta, [path, {:__aliases__, _, _} = plug | rest]}, acc ->
          {{verb, meta, [path | rest]}, scoped_route(scope, plug, acc)}

        # A piped call has one more argument than it shows
        {:|>, meta, [left, {call, call_meta, args}]}, acc when is_list(args) ->
          {{:|>, meta, [left, {call, [{:piped, true} | call_meta], args}]}, acc}

        # The module is reported with its deprecated function, or else once
        # if renamed; the arguments are still scanned, the receiver is not.
        # A name an alias may or may not reach is checked as both modules.
        {{:., _, [{:__aliases__, _, _} = receiver, name]}, meta, args}, acc when is_atom(name) and is_list(args) ->
          acc =
            receiver
            |> LexicalAliases.modules()
            |> Enum.reduce(acc, &check_call(&1, {name, arity(meta, args)}, meta, deprecated, &2))

          {{:__block__, [], args}, acc}

        {:__aliases__, meta, parts} = node, acc when is_list(parts) ->
          {node, node |> LexicalAliases.modules() |> Enum.reduce(acc, &renamed(&1, meta, &2))}

        {{:., _, [module, name]}, meta, args} = node, acc when is_atom(module) and is_atom(name) and is_list(args) ->
          {node, check(module, name, arity(meta, args), meta, deprecated, acc)}

        {name, meta, args} = node, acc when is_atom(name) and is_list(args) ->
          case Map.get(imports, {name, arity(meta, args)}) do
            nil -> {node, acc}
            module -> {node, check(module, name, arity(meta, args), meta, deprecated, acc)}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp arity(meta, args), do: length(args) + if(meta[:piped], do: 1, else: 0)

  defp check_call(module, {name, arity}, meta, deprecated, acc) do
    case check(module, name, arity, meta, deprecated, acc) do
      ^acc -> renamed(module, meta, acc)
      found -> found
    end
  end

  defp check(module, name, arity, meta, deprecated, acc) do
    case Map.get(deprecated, {module, name, arity}) do
      nil ->
        acc

      reason ->
        call = "#{inspect(module)}.#{name}/#{arity}"
        [%{file: nil, line: meta[:line], call: call, reason: reason} | acc]
    end
  end

  # A reference to a module renamed in 0.55: a router or socket names a
  # controller or channel without calling it
  defp scoped_route(scope, {:__aliases__, meta, _} = plug, acc) do
    module = RenamedModules.scoped_module(scope, plug)

    case module && RenamedModules.new_name(module) do
      nil ->
        acc

      new ->
        reason =
          "renamed to #{inspect(new)}; the old name is removed in Brando #{RenamedModules.removed_in()}. " <>
            "The route gets it from its scope's alias: name the controller #{inspect(new)} and add alias: false"

        [%{file: nil, line: meta[:line], call: inspect(module), reason: reason} | acc]
    end
  end

  defp renamed(module, meta, acc) do
    if RenamedModules.new_name(module) do
      [%{file: nil, line: meta[:line], call: inspect(module), reason: RenamedModules.reason(module)} | acc]
    else
      acc
    end
  end

  # `{name, arity} => module` for deprecated functions brought in by `import`
  defp collect_imports(ast, deprecated) do
    {_ast, imports} =
      Macro.prewalk(ast, %{}, fn
        {:import, _, [{:__aliases__, _, _} = target | rest]} = node, acc ->
          opts = List.first(rest) || []
          {node, Map.merge(acc, imported(LexicalAliases.module(target), opts, deprecated))}

        node, acc ->
          {node, acc}
      end)

    imports
  end

  defp imported(module, opts, deprecated) do
    only = if is_list(opts), do: opts[:only]
    except = if(is_list(opts), do: opts[:except]) || []

    for {{^module, name, arity}, _reason} <- deprecated,
        (is_nil(only) or not is_list(only) or {name, arity} in only) and {name, arity} not in List.wrap(except),
        into: %{},
        do: {{name, arity}, module}
  end
end
