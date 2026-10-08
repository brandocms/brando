defmodule Brando.UsageRulesExamples do
  @moduledoc false

  # Checks the Elixir examples in the generated `usage-rules.md`.
  #
  # Every example must parse, and every `Brando.*` or `BrandoAdmin.*` module it
  # names must exist, with every remote call to one (directly, through an
  # alias, a pipe or a capture) defined at that arity.
  #
  # On top of that, two kinds of examples are compiled for real:
  #
  #   * `:module`: every top-level form is a `defmodule`. Compiled as written,
  #     next to the scratch `MyApp` modules defined by `define_scratch_modules/0`.
  #   * `:blueprint`: Blueprint DSL without its module, such as an
  #     `attributes do ... end` section, an `input` line or `use
  #     Brando.Blueprint, ...`. Wrapped in a minimal Blueprint (and in the
  #     sections an entity belongs to) and compiled.
  #
  # Anything else (`:expression`) is only parsed and checked for references.
  # Compiling must not raise or warn, apart from the warnings in @benign.

  @scratch_module UsageRulesExample.Blueprint

  @root_dsl ~w(attributes relations assets json_ld_schema meta_schema forms listings datasources
               translations identifier absolute_url persist_identifier trait table data_layer
               primary_key factory content_icon authorization def defp @ import alias require)a

  # Root declarations a Blueprint has once. An example repeating one shows
  # alternatives.
  @singletons ~w(identifier absolute_url table data_layer primary_key content_icon persist_identifier factory)a

  # Where an entity belongs when an example shows it on its own, innermost
  # section first.
  @wrappers %{
    attribute: ["attributes do"],
    relation: ["relations do"],
    asset: ["assets do"],
    form: ["forms do"],
    blocks: ["form do", "forms do"],
    tab: ["form do", "forms do"],
    fieldset: [~s|tab "Content" do|, "form do", "forms do"],
    alert: [~s|tab "Content" do|, "form do", "forms do"],
    input: ["fieldset do", ~s|tab "Content" do|, "form do", "forms do"],
    inputs_for: ["fieldset do", ~s|tab "Content" do|, "form do", "forms do"],
    listing: ["listings do"],
    action: ["listing do", "listings do"],
    sort: ["listing do", "listings do"],
    selection_action: ["listing do", "listings do"],
    filter: ["listing do", "listings do"],
    child_listing: ["listing do", "listings do"],
    export: ["listing do", "listings do"],
    datasource: ["datasources do"],
    context: ["translations do"]
  }

  # Application modules (`MyApp.Articles`) do not exist here; calls to them
  # are fine. Calls to Brando modules that do not exist are not.
  @benign [
    ~r/protocol has already been consolidated/,
    ~r/redefining module/,
    ~r/^(?!Brando)[A-Z][\w.]*\.[\w!?]+\/\d+ is undefined \(module (?!Brando)[\w.]+ is not available/
  ]

  # Application modules the guides' examples assume: Gettext backends (with no
  # translations, which compile in milliseconds), the schema the Querying guide
  # builds a context for, and the subform schema the Blueprint forms guide
  # translates labels against.
  @scratch_modules [
    {MyAppAdmin.Gettext,
     """
     defmodule MyAppAdmin.Gettext do
       use Gettext.Backend, otp_app: :my_app, priv: "priv/no_translations"
     end
     """},
    {MyAppWeb.Gettext,
     """
     defmodule MyAppWeb.Gettext do
       use Gettext.Backend, otp_app: :my_app, priv: "priv/no_translations"
     end
     """},
    {MyApp.Projects.Project,
     """
     defmodule MyApp.Projects.Project do
       use Brando.Blueprint,
         application: "MyApp",
         domain: "Projects",
         schema: "Project",
         singular: "project",
         plural: "projects"

       trait :status
       trait :timestamped

       attributes do
         attribute :title, :string, required: true
         attribute :slug, :slug, required: true
         attribute :featured, :boolean
       end
     end
     """},
    {MyApp.Articles.Link,
     """
     defmodule MyApp.Articles.Link do
       use Brando.Blueprint,
         application: "MyApp",
         domain: "Articles",
         schema: "Link",
         singular: "link",
         plural: "links"

       data_layer :embedded

       attributes do
         attribute :title, :string
         attribute :url, :string
       end
     end
     """}
  ]

  @doc """
  Defines the application modules that examples refer to while compiling.
  Examples that define one of them replace it, so this runs again after each.
  """
  def define_scratch_modules do
    for {module, source} <- @scratch_modules, not Code.ensure_loaded?(module), do: quietly_compile(source)
    :ok
  end

  defp quietly_compile(source) do
    ExUnit.CaptureIO.with_io(:stderr, fn ->
      Code.with_diagnostics([log: false], fn -> Code.compile_string(source, "scratch.ex") end)
    end)
  end

  @doc "Checks one example. Returns `{:ok, kind}` or `{:error, reason}`."
  def check(code) do
    with {:ok, ast} <- parse(code),
         :ok <- check_references(ast) do
      kind = kind(ast)

      case compile(kind, code, ast) do
        :ok -> {:ok, kind}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp parse(code) do
    case Code.string_to_quoted(code, columns: true) do
      {:ok, ast} -> {:ok, ast}
      {:error, {meta, message, token}} -> {:error, "does not parse (line #{meta[:line]}): #{inspect(message)} #{token}"}
    end
  end

  ## Kinds

  defp kind(ast) do
    forms = top_level(ast)

    cond do
      Enum.all?(forms, &module_form?/1) and Enum.any?(forms, &match?({:defmodule, _, _}, &1)) -> :module
      blueprint_fragment?(forms) -> :blueprint
      true -> :expression
    end
  end

  defp top_level({:__block__, _, forms}), do: forms
  defp top_level(form), do: [form]

  defp module_form?({name, _, _}) when name in [:defmodule, :alias, :require, :import], do: true
  defp module_form?(_), do: false

  defp blueprint_fragment?([{:use, _, [{:__aliases__, _, [:Brando, :Blueprint]} | _]} | rest]),
    do: Enum.all?(rest, &dsl_form?/1)

  defp blueprint_fragment?(forms) do
    Enum.all?(forms, &dsl_form?/1) and Enum.any?(forms, &(not match?({name, _, _} when name in [:def, :defp, :@], &1)))
  end

  defp dsl_form?({name, _, args}) when is_list(args), do: name in @root_dsl or Map.has_key?(@wrappers, name)
  defp dsl_form?(_), do: false

  ## Compiling

  defp compile(:expression, _code, _ast), do: :ok
  defp compile(:module, code, _ast), do: compile_string(code, [])

  defp compile(:blueprint, code, ast) do
    forms = top_level(ast)

    if alternatives?(forms) do
      # `identifier ~H"..."` written three ways: compile each on its own.
      Enum.find_value(forms, :ok, fn form ->
        with :ok <- compile_fragment([form], Macro.to_string(form)), do: nil
      end)
    else
      compile_fragment(forms, code)
    end
  end

  defp compile_fragment(forms, code) do
    {use_line, body} =
      case forms do
        [{:use, _, _} | _] -> {nil, code}
        _ -> {scratch_use(code), wrap_entities(forms, code)}
      end

    # A fragment's forms and listings refer to fields, traits and functions the
    # rest of its Blueprint would declare, so the checks Brando runs after
    # compiling a Blueprint do not apply to it. The DSL itself, its options and
    # the code inside it are still compiled.
    """
    defmodule #{inspect(@scratch_module)} do
    #{use_line}
    #{body}
    end
    """
    |> compile_string([~r/\A\*\* \(Spark\.Error\.DslError\)/])
  end

  defp alternatives?(forms) do
    names = Enum.map(forms, &elem(&1, 0))
    Enum.any?(@singletons, fn name -> Enum.count(names, &(&1 == name)) > 1 end)
  end

  # The JSON-LD guide has Blueprints refer to schemas through `alias Brando.JSONLD`.
  defp scratch_use(code) do
    """
    use Brando.Blueprint,
      application: "MyApp",
      domain: "Examples",
      schema: "Example",
      singular: "example",
      plural: "examples"

    #{if String.contains?(code, "JSONLD."), do: "alias Brando.JSONLD"}
    """
  end

  # An example made only of entities of one section (`attribute` lines,
  # `input` lines), and perhaps the functions they call, is wrapped in that
  # section.
  defp wrap_entities(forms, code) do
    {functions, entities} = Enum.split_with(forms, &match?({name, _, _} when name in [:def, :defp, :@], &1))

    case entities |> Enum.map(&elem(&1, 0)) |> Enum.uniq() do
      [name] when is_map_key(@wrappers, name) ->
        inner = Enum.map_join(entities, "\n", &Macro.to_string/1)
        wrapped = Enum.reduce(@wrappers[name], inner, fn opening, inner -> "#{opening}\n#{inner}\nend" end)
        Enum.join([wrapped | Enum.map(functions, &Macro.to_string/1)], "\n\n")

      _ ->
        code
    end
  end

  defp compile_string(code, also_benign) do
    {{result, diagnostics}, _stderr} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Code.with_diagnostics([log: false], fn ->
          try do
            {:ok, Code.compile_string(code, "usage-rules.md")}
          rescue
            error -> {:error, Exception.message(error)}
          end
        end)
      end)

    case result do
      {:ok, modules} ->
        Enum.each(modules, fn {module, _binary} ->
          :code.purge(module)
          :code.delete(module)
        end)

        define_scratch_modules()

        case Enum.reject(diagnostics, &benign?(&1, also_benign)) do
          [] -> :ok
          problems -> {:error, Enum.map_join(problems, "\n", &format_diagnostic/1)}
        end

      {:error, message} ->
        details = diagnostics |> Enum.filter(&(&1.severity == :error)) |> Enum.map_join("\n", &format_diagnostic/1)
        {:error, String.trim(message <> "\n" <> details)}
    end
  end

  defp benign?(%{severity: :warning, message: message}, also_benign),
    do: Enum.any?(@benign ++ also_benign, &Regex.match?(&1, message))

  defp benign?(_diagnostic, _also_benign), do: false

  defp format_diagnostic(%{severity: severity, message: message, position: position}) do
    "#{severity} at #{inspect(position)}: #{message}"
  end

  ## References

  defp check_references(ast) do
    aliases = collect_aliases(ast)
    defined = collect_defined_modules(ast, aliases)

    {_ast, problems} =
      ast
      |> Macro.prewalk(&unpipe/1)
      |> Macro.prewalk([], fn node, problems -> reference(node, problems, aliases, defined) end)

    case problems |> Enum.reverse() |> Enum.uniq() do
      [] -> :ok
      problems -> {:error, Enum.join(problems, "\n")}
    end
  end

  # `a |> f(b)` becomes `f(a, b)`, so calls are checked at their real arity.
  defp unpipe({:|>, _, [left, {call, meta, args}]}) when is_list(args), do: {call, meta, [left | args]}
  defp unpipe(node), do: node

  defp reference({:&, _, [{:/, _, [{{:., _, [module, function]}, _, []}, arity]}]} = _node, problems, aliases, defined)
       when is_atom(function) and is_integer(arity) do
    {:ok, check_call(module, function, arity, problems, aliases, defined)}
  end

  defp reference({{:., _, [{:__aliases__, _, _} = module, function]}, _, args} = node, problems, aliases, defined)
       when is_atom(function) and is_list(args) do
    {node, check_call(module, function, length(args), problems, aliases, defined)}
  end

  defp reference({:__aliases__, _, _} = node, problems, aliases, defined) do
    case brando_module(node, aliases, defined) do
      nil -> {node, problems}
      module -> {node, check_module(module, problems)}
    end
  end

  defp reference(node, problems, _aliases, _defined), do: {node, problems}

  defp check_call(module_ast, function, arity, problems, aliases, defined) do
    case brando_module(module_ast, aliases, defined) do
      nil ->
        problems

      module ->
        problems = check_module(module, problems)

        cond do
          not Code.ensure_loaded?(module) -> problems
          function_exported?(module, function, arity) -> problems
          macro_exported?(module, function, arity) -> problems
          true -> ["#{inspect(module)}.#{function}/#{arity} is undefined" | problems]
        end
    end
  end

  defp check_module(module, problems) do
    if Code.ensure_loaded?(module), do: problems, else: ["module #{inspect(module)} does not exist" | problems]
  end

  defp brando_module({:__aliases__, _, [first | rest]}, aliases, defined) when is_atom(first) do
    parts =
      case Map.fetch(aliases, first) do
        {:ok, full} -> full ++ rest
        :error -> [first | rest]
      end

    module = Module.concat(parts)

    cond do
      hd(parts) not in [:Brando, :BrandoAdmin] -> nil
      Enum.any?(defined, &(module == &1 or String.starts_with?(inspect(module), inspect(&1) <> "."))) -> nil
      true -> module
    end
  end

  defp brando_module(_ast, _aliases, _defined), do: nil

  defp collect_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{:__aliases__, _, parts}]} = node, acc ->
          {node, Map.put(acc, List.last(parts), parts)}

        {:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [as]}]]} = node, acc ->
          {node, Map.put(acc, as, parts)}

        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = node, acc ->
          {node,
           Enum.reduce(children, acc, fn
             {:__aliases__, _, parts}, acc -> Map.put(acc, List.last(parts), base ++ parts)
             _, acc -> acc
           end)}

        node, acc ->
          {node, acc}
      end)

    aliases
  end

  defp collect_defined_modules(ast, aliases) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [{:__aliases__, _, [first | rest]} | _]} = node, acc ->
          parts = Map.get(aliases, first, [first]) ++ rest
          {node, [Module.concat(parts) | acc]}

        node, acc ->
          {node, acc}
      end)

    modules
  end
end
