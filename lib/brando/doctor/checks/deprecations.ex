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
    |> Enum.sort_by(&{&1.file, &1.line})
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

  @doc """
  Finds calls in `deprecated` (see `deprecated/0`) in the file at `path`,
  and in the templates its `embed_templates` calls compile in.
  """
  def scan_file(path, deprecated) do
    case path |> File.read!() |> Code.string_to_quoted(file: path, columns: false) do
      {:ok, ast} ->
        ast
        |> scan(deprecated, templates: &read_templates(path, &1, &2))
        |> Enum.map(&Map.update!(&1, :file, fn file -> file || path end))

      {:error, _} ->
        []
    end
  rescue
    # A file the scanner cannot follow is not worth failing the check over
    _ -> []
  end

  @doc """
  Finds calls in `deprecated` in quoted code, and the renamed modules named
  in its templates: a `~H` sigil, and, given `templates:` (a function of an
  `embed_templates` call's pattern and options returning
  `[{path, text}]`), the files it compiles in. A finding in a template file
  has that file's path.
  """
  def scan(ast, deprecated, opts \\ []) do
    ast = RenamedModules.mark_scoped_routes(ast)
    templates = Keyword.get(opts, :templates, fn _pattern, _options -> [] end)

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

        # Names in a template resolve through the aliases where it is written
        {:embed_templates, [{:lexical_env, env} | _], [pattern | options]} = node, acc ->
          found =
            Enum.reduce(templates.(pattern, options), acc, fn {path, text}, acc ->
              text |> LexicalAliases.names_in_text(env, 1) |> template_findings(path) |> Enum.concat(acc)
            end)

          {node, found}

        {_sigil, [{:lexical_env, _} | _], [{:<<>>, _, _} | _]} = node, acc ->
          {node, node |> LexicalAliases.template_names() |> template_findings(nil) |> Enum.concat(acc)}

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

        # A local call, through the imports in scope where it is made
        {name, meta, args} = node, acc when is_atom(name) and is_list(args) ->
          {node, local_call(name, arity(meta, args), meta, deprecated, acc)}

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

  defp local_call(name, arity, meta, deprecated, acc) do
    imports = Enum.filter(meta[:imports] || [], &imported?(&1, name, arity))

    case Enum.find(imports, &Map.has_key?(deprecated, {&1.module, name, arity})) do
      nil -> acc
      %{module: module} -> check(module, name, arity, meta, deprecated, acc)
    end
  end

  # Whether `import module, only: …, except: …` brings in `name/arity`
  defp imported?(%{only: only, except: except}, name, arity) do
    (not is_list(only) or {name, arity} in only) and {name, arity} not in List.wrap(except)
  end

  defp template_modules({:either, candidates}),
    do: candidates |> Enum.map(&LexicalAliases.to_module/1) |> Enum.reject(&is_nil/1)

  defp template_modules(resolved), do: List.wrap(LexicalAliases.to_module(resolved))

  # Findings, newest first, for the renamed modules among a template's
  # names; `file` is the template file's path, or nil for a sigil
  defp template_findings(names, file) do
    names
    |> Enum.flat_map(fn %{resolved: resolved, line: line} ->
      resolved |> template_modules() |> Enum.reduce([], &renamed(&1, [line: line], &2)) |> Enum.reverse()
    end)
    |> Enum.map(&%{&1 | file: file})
    |> Enum.reverse()
  end

  # The templates `embed_templates pattern, root: …` in the file at `path`
  # compiles in, as Phoenix finds them
  defp read_templates(path, pattern, options) when is_binary(pattern) do
    root =
      case options do
        [options | _] when is_list(options) -> options[:root]
        _ -> nil
      end

    path
    |> Path.dirname()
    |> Path.expand()
    |> Path.join(if(is_binary(root), do: root, else: "."))
    |> Path.join(pattern <> ".{heex,eex,leex}")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&{&1, File.read!(&1)})
  end

  defp read_templates(_path, _pattern, _options), do: []
end
