if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.AdminRouteScopes do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Phoenix names a FormLive's route helper after the LiveView, so
    # `Articles.CategoryFormLive` and `Menu.CategoryFormLive` both route
    # `admin_category_form_path`, and one Blueprint's links open the other's
    # form. A FormLive routed in a plain `scope "/menu", App.Menu do`, whose
    # routes are all that domain's admin LiveViews, gets its own helpers from
    # `as: :menu` on the scope, and the Blueprints routed there follow them
    # with `router_scope: :menu`. Anything else is left for the developer.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Keyword, as: CodeKeyword
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.RouteInventory
    alias Rewrite.Source
    alias Sourceror.Zipper

    @admin_view ~r/use\s+BrandoAdmin\.LiveView\.(?:Listing|Form),\s*schema:\s*(?:Elixir\.)?([A-Z][\w.]*)/

    @doc """
    Scopes the routers' plain domain scopes holding one of `pairs` (converted
    FormLives sharing a route helper), and sets `router_scope` on the
    Blueprints routed there.

    Returns `{igniter, scoped, refused}`: `scoped` lists each scope written,
    as `%{router:, line:, code:, name:, schemas:, forms:}`, and `refused` maps
    each FormLive left alone to the lines saying why.
    """
    def resolve(igniter, pairs, routers) do
      igniter = Igniter.include_glob(igniter, "{lib,test}/**/*.{ex,exs,heex,eex,leex}")
      sources = sources(igniter)
      scopes = Enum.flat_map(routers, &plain_scopes(igniter, &1))

      {plans, refused} =
        Enum.reduce(pairs, {%{}, %{}}, fn pair, {plans, refused} ->
          case plan(igniter, pair, scopes, pairs, sources) do
            {:ok, scope} -> {Map.update(plans, scope.key, scope, &%{&1 | forms: &1.forms ++ scope.forms}), refused}
            {:error, reasons} -> {plans, Map.put(refused, pair.form, reasons)}
          end
        end)

      plans = plans |> Map.values() |> Enum.sort_by(&{&1.router, &1.line})
      {Enum.reduce(plans, igniter, &apply_scope(&2, &1)), plans, refused}
    end

    defp sources(igniter) do
      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
      |> Enum.filter(fn {path, _content} -> String.starts_with?(path, ["lib/", "test/"]) end)
      |> Enum.sort()
    end

    @doc "`path:line: code` for each route in `routers` naming one of `modules`."
    def route_lines(igniter, routers, modules) do
      for router <- routers,
          content = igniter.rewrite |> Rewrite.source!(router) |> Source.get(:content),
          lines = String.split(content, "\n"),
          zipper <- content |> Sourceror.parse_string!() |> Zipper.zip() |> Common.find_all(&live_call?/1),
          [%{module: module}] <- [RouteInventory.at(zipper)],
          module in modules,
          line = zipper |> Zipper.node() |> Sourceror.get_line(),
          do: "#{router}:#{line}: #{lines |> Enum.at(line - 1) |> String.trim()}"
    end

    defp live_call?(zipper), do: CodeFunction.function_call?(zipper, :live, [2, 3, 4])

    ## Plan

    # `scope "/menu", App.Menu do … end`, with no options and no enclosing
    # scope that names one.
    defp plain_scopes(igniter, router) do
      content = igniter.rewrite |> Rewrite.source!(router) |> Source.get(:content)

      content
      |> Sourceror.parse_string!()
      |> Zipper.zip()
      |> Common.find_all(&plain_scope?/1)
      |> Enum.reject(&named_ancestor?/1)
      |> Enum.map(fn zipper ->
        node = Zipper.node(zipper)
        code = scope_code(node)

        %{
          key: {router, code},
          router: router,
          line: Sourceror.get_line(node),
          code: code,
          routes: RouteInventory.at(zipper)
        }
      end)
      |> unique_keys()
    end

    defp plain_scope?(zipper) do
      match?(
        {:scope, _, [{:__block__, _, [path]}, {:__aliases__, _, _}, [{{:__block__, _, [:do]}, _body}]]}
        when is_binary(path),
        Zipper.node(zipper)
      )
    end

    defp named_ancestor?(zipper) do
      zipper
      |> Zipper.up()
      |> Stream.unfold(fn
        nil -> nil
        zipper -> {Zipper.node(zipper), Zipper.up(zipper)}
      end)
      |> Enum.any?(fn
        {:scope, _, arguments} when is_list(arguments) -> Enum.any?(arguments, &names?/1)
        _node -> false
      end)
    end

    defp names?(options) when is_list(options), do: Enum.any?(options, &match?({{:__block__, _, [:as]}, _}, &1))
    defp names?(_argument), do: false

    # The rewrite finds a scope by its first line, so two alike are left alone.
    defp unique_keys(scopes) do
      scopes
      |> Enum.group_by(& &1.key)
      |> Enum.flat_map(fn
        {_key, [scope]} -> [scope]
        {_key, _many} -> []
      end)
    end

    defp plan(igniter, pair, scopes, pairs, sources) do
      namespace = pair.form |> Module.split() |> Enum.drop(-1)

      with {:ok, scope} <- find_scope(scopes, pair.form),
           :ok <- one_domain(scope, namespace),
           {:ok, schemas} <- schemas(scope, pairs, sources),
           :ok <- blueprints(igniter, schemas),
           :ok <- unreferenced(scope, sources) do
        name = namespace |> List.last() |> Macro.underscore()
        {:ok, Map.merge(scope, %{name: name, schemas: schemas, forms: [pair.form]})}
      end
    end

    defp find_scope(scopes, form) do
      case Enum.find(scopes, fn scope -> Enum.any?(scope.routes, &(&1.module == form)) end) do
        nil -> {:error, ["its routes are not in a `scope \"/path\", App.Domain do` of their own"]}
        scope -> {:ok, scope}
      end
    end

    defp one_domain(scope, namespace) do
      case Enum.reject(scope.routes, &(&1.kind == :live and parent(&1.module) == namespace)) do
        [] ->
          :ok

        others ->
          {:error,
           for(
             route <- others,
             do: "`#{scope.code}` (#{scope.router}:#{scope.line}) also routes #{describe(route)}"
           )}
      end
    end

    defp parent(nil), do: nil
    defp parent(module), do: module |> Module.split() |> Enum.drop(-1)

    defp describe(%{module: nil, path: path}), do: path
    defp describe(%{module: module}), do: inspect(module)

    # The Blueprint each LiveView in the scope edits or lists.
    defp schemas(scope, pairs, sources) do
      forms = Map.new(pairs, &{&1.form, &1.schema})

      scope.routes
      |> Enum.map(&(&1.module |> then(fn module -> {module, forms[module] || listed_schema(module, sources)} end)))
      |> Enum.split_with(fn {_module, schema} -> schema != nil end)
      |> case do
        {found, []} -> {:ok, found |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()}
        {_found, unknown} -> {:error, Enum.map(unknown, &"cannot tell which Blueprint #{inspect(elem(&1, 0))} edits")}
      end
    end

    defp listed_schema(module, sources) do
      definition = ~r/^\s*defmodule\s+#{Regex.escape(inspect(module))}\s+do\b/m

      Enum.find_value(sources, fn {_path, content} ->
        with true <- content =~ definition,
             [[_, schema]] <- Regex.scan(@admin_view, content) do
          Module.concat([schema])
        else
          _ -> nil
        end
      end)
    end

    defp blueprints(igniter, schemas) do
      case Enum.flat_map(schemas, &blueprint_problem(igniter, &1)) do
        [] -> :ok
        problems -> {:error, problems}
      end
    end

    defp blueprint_problem(igniter, schema) do
      with {:ok, {_igniter, _source, zipper}} <- ProjectModule.find_module(igniter, schema),
           {:ok, options} <- blueprint_options(zipper) do
        if CodeKeyword.get_key(options, :router_scope) == :error,
          do: [],
          else: ["#{inspect(schema)} already sets `router_scope`"]
      else
        _ -> ["#{inspect(schema)} has no `use Brando.Blueprint` with a keyword list of options"]
      end
    end

    defp blueprint_options(zipper) do
      with {:ok, body} <- Common.move_to_do_block(zipper), do: use_options(body)
    end

    # The options of `use Brando.Blueprint`, given the module's body.
    defp use_options(body) do
      with {:ok, use_zipper} <- Igniter.Code.Module.move_to_use(body, Brando.Blueprint),
           {:ok, options} <- CodeFunction.move_to_nth_argument(use_zipper, 1),
           true <- Igniter.Code.List.list?(options) do
        {:ok, options}
      else
        _ -> :error
      end
    end

    # Other code calling a helper the scope renames: `admin_<name>_path` of a
    # route with an action (`CategoryFormLive, :update` routes
    # `admin_category_form_path`), or `admin_live_path` with one of its views
    # within the next few lines.
    defp unreferenced(scope, sources) do
      shorts = for %{module: module} <- scope.routes, do: module |> Module.split() |> List.last()

      named =
        for %{module: module, action: action} <- scope.routes,
            is_atom(action) and not is_nil(action),
            uniq: true,
            do: module |> Module.split() |> List.last() |> Macro.underscore() |> String.replace_suffix("_live", "")

      helper = ~r/\badmin_(?:#{Enum.join(named, "|")})_(?:path|url)\b/
      live_helper = ~r/\badmin_live_(?:path|url)\b/

      findings =
        for {path, content} <- sources,
            path != scope.router,
            lines = String.split(content, "\n"),
            {line, number} <- Enum.with_index(lines, 1),
            (named != [] and line =~ helper) or (line =~ live_helper and names_view?(lines, number, shorts)),
            do: "#{path}:#{number}: #{String.trim(line)}"

      if findings == [],
        do: :ok,
        else: {:error, Enum.map(findings, &"#{&1} (names a route helper `as:` would rename)")}
    end

    defp names_view?(lines, number, shorts) do
      call = lines |> Enum.slice(number - 1, 4) |> Enum.join(" ")
      Enum.any?(shorts, &(call =~ ~r/\b#{&1}\b/))
    end

    ## Rewrite

    defp apply_scope(igniter, scope) do
      name = Sourceror.parse_string!(":" <> scope.name)

      igniter
      |> Igniter.update_elixir_file(scope.router, fn zipper ->
        Common.update_all_matches(zipper, &scope_at?(&1, scope.code), &add_as(&1, name))
      end)
      |> then(fn igniter ->
        Enum.reduce(scope.schemas, igniter, fn schema, igniter ->
          ProjectModule.find_and_update_module!(igniter, schema, &set_router_scope(&1, name))
        end)
      end)
    end

    defp scope_at?(zipper, code), do: plain_scope?(zipper) and scope_code(Zipper.node(zipper)) == code

    defp scope_code({:scope, _, [path, namespace, _body]}),
      do: "scope #{Sourceror.to_string(path)}, #{Sourceror.to_string(namespace)}"

    defp add_as(zipper, name) do
      Zipper.update(zipper, fn {:scope, meta, [path, namespace, body]} ->
        as = [{{:__block__, [format: :keyword], [:as]}, name}]
        {:scope, meta, [path, namespace, as, body]}
      end)
      |> then(&{:ok, &1})
    end

    defp set_router_scope(body, name) do
      with {:ok, options} <- use_options(body) do
        CodeKeyword.set_keyword_key(options, :router_scope, name)
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.AdminRouteScopes do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
