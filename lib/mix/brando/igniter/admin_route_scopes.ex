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
    # with `router_scope: :menu`. Flat routes, the generated 0.53 shape, are
    # wrapped in a new scope (`plan_flat/6`). Anything else is left for the
    # developer.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Keyword, as: CodeKeyword
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.RouteInventory
    alias Mix.Brando.Igniter.Source, as: IgniterSource
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
      sources = IgniterSource.project_sources(igniter)
      scopes = Enum.flat_map(routers, &plain_scopes(igniter, &1))

      {plans, refused} =
        Enum.reduce(pairs, {%{}, %{}}, fn pair, {plans, refused} ->
          case plan(igniter, pair, scopes, pairs, sources) do
            {:ok, scope} -> {Map.update(plans, scope.key, scope, &%{&1 | forms: &1.forms ++ scope.forms}), refused}
            {:error, reasons} -> {plans, Map.put(refused, pair.form, reasons)}
          end
        end)

      {plans, refused} = plan_flat(igniter, pairs, Map.values(plans), refused, {routers, scopes}, sources)
      plans = Enum.sort_by(plans, &{&1.router, &1.line})
      {Enum.reduce(plans, igniter, &apply_scope(&2, &1)), plans, refused}
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
      case helper_calls(scope, sources) ++ renaming_aliases(scope, sources) do
        [] -> :ok
        findings -> {:error, findings}
      end
    end

    defp helper_calls(scope, sources) do
      shorts = for %{module: module} <- scope.routes, do: module |> Module.split() |> List.last()

      named =
        for %{module: module, action: action} <- scope.routes,
            is_atom(action) and not is_nil(action),
            uniq: true,
            do: module |> Module.split() |> List.last() |> Macro.underscore() |> String.replace_suffix("_live", "")

      helper = ~r/\badmin_(?:#{Enum.join(named, "|")})_(?:path|url)\b/
      live_helper = ~r/\badmin_live_(?:path|url)\b/

      for {path, content} <- sources,
          path != scope.router,
          lines = String.split(content, "\n"),
          {line, number} <- Enum.with_index(lines, 1),
          (named != [] and line =~ helper) or (line =~ live_helper and names_view?(lines, number, shorts)),
          do: "#{path}:#{number}: #{String.trim(line)} (names a route helper `as:` would rename)"
    end

    # `alias App.Menu.CategoryListLive, as: List` (or an alias of the domain's
    # namespace under another name) hides the view's name from the search
    # above, so any such alias outside the router leaves the scope alone.
    defp renaming_aliases(scope, sources) do
      namespace = scope.routes |> hd() |> Map.fetch!(:module) |> Module.split() |> Enum.drop(-1) |> Enum.join(".")
      pattern = ~r/\balias\s+#{Regex.escape(namespace)}(?:\.[\w.]+)?\s*,\s*as:/

      for {path, content} <- sources,
          path != scope.router,
          [{start, _length}] <- Regex.scan(pattern, content, return: :index),
          number = content |> binary_part(0, start) |> String.split("\n") |> length(),
          line = content |> String.split("\n") |> Enum.at(number - 1) |> String.trim(),
          do: "#{path}:#{number}: #{line} (renames one of the scope's LiveViews)"
    end

    defp names_view?(lines, number, shorts) do
      call = lines |> Enum.slice(number - 1, 4) |> Enum.join(" ")
      Enum.any?(shorts, &(call =~ ~r/\b#{&1}\b/))
    end

    ## Flat routes

    # The generated 0.53 router listed every domain's routes flat in
    # `admin_routes`. When two or more FormLives of a group still share a
    # helper after the plain scopes, each whose routes are adjacent lines of
    # their own (the FormLive's, and its ListLive's) is wrapped in a new
    # `scope "<common path>", App.Domain, as: :domain do`. Lines with other
    # routes between them are left: moving them could change which route
    # matches first.
    defp plan_flat(igniter, pairs, plans, refused, {routers, scopes}, sources) do
      planned = for plan <- plans, form <- plan.forms, do: form

      {plans, refused} =
        pairs
        |> Enum.reject(&(&1.form in planned))
        |> Enum.group_by(&(&1.form |> Module.split() |> List.last()))
        |> Enum.filter(fn {_short, group} -> match?([_, _ | _], group) end)
        |> Enum.flat_map(&elem(&1, 1))
        |> Enum.filter(&match?({:error, _}, find_scope(scopes, &1.form)))
        |> Enum.reduce({plans, refused}, fn pair, {plans, refused} ->
          case plan_flat_pair(igniter, pair, pairs, routers, sources) do
            {:ok, plan} -> {[plan | plans], Map.delete(refused, pair.form)}
            {:error, reasons} -> {plans, Map.put(refused, pair.form, reasons)}
          end
        end)

      {shift_lines(plans), refused}
    end

    defp plan_flat_pair(igniter, pair, pairs, routers, sources) do
      namespace = pair.form |> Module.split() |> Enum.drop(-1)
      modules = [pair.form, Module.concat([pair.base <> "ListLive"])]

      with {:ok, router, routes} <- flat_routes(igniter, routers, modules),
           {:ok, scope} <- flat_scope(router, routes),
           {:ok, schemas} <- schemas(scope, pairs, sources),
           :ok <- blueprints(igniter, schemas),
           :ok <- unreferenced(scope, sources) do
        name = namespace |> List.last() |> Macro.underscore()
        {:ok, Map.merge(scope, %{name: name, schemas: schemas, forms: [pair.form]})}
      end
    end

    # `{zipper, inventory}` of each route to `modules`, when they are
    # adjacent statements of one block outside any scope with `as:`.
    defp flat_routes(igniter, routers, modules) do
      found =
        for router <- routers,
            zipper <- router |> quoted_router(igniter) |> Common.find_all(&live_call?/1),
            [%{module: module} = route] <- [RouteInventory.at(zipper)],
            module in modules,
            do: {router, zipper, route}

      parents =
        found |> Enum.map(fn {_router, zipper, _route} -> zipper |> Zipper.up() |> Zipper.node() end) |> Enum.uniq()

      cond do
        found == [] ->
          {:error, ["its routes were not found"]}

        found |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() > 1 ->
          {:error, ["its routes are in more than one router"]}

        Enum.any?(found, fn {_router, zipper, _route} -> named_ancestor?(zipper) end) ->
          {:error, ["its routes are in a scope that already names its helpers with `as:`"]}

        not match?([{:__block__, _, statements}] when is_list(statements), parents) ->
          {:error, ["its routes are not lines of the same block"]}

        not adjacent?(hd(parents), Enum.map(found, &(&1 |> elem(1) |> Zipper.node()))) ->
          {:error, ["other routes stand between its routes, so moving them could change which route matches"]}

        true ->
          [{router, _zipper, _route} | _] = found
          {:ok, router, Enum.map(found, fn {_router, zipper, route} -> {Zipper.node(zipper), route} end)}
      end
    end

    defp quoted_router(router, igniter),
      do: igniter.rewrite |> Rewrite.source!(router) |> Source.get(:quoted) |> Zipper.zip()

    defp adjacent?({:__block__, _, statements}, nodes) do
      indexes = nodes |> Enum.map(fn node -> Enum.find_index(statements, &(&1 == node)) end) |> Enum.sort()
      nil not in indexes and indexes == Enum.to_list(hd(indexes)..(hd(indexes) + length(indexes) - 1))
    end

    # The scope's path is what the routes' paths share, and its namespace
    # what their modules are written with.
    defp flat_scope(router, routes) do
      moves = Enum.map(routes, fn {node, _route} -> flat_move(node) end)

      with nil <- Enum.find(moves, &match?({:error, _}, &1)),
           moves = Enum.map(moves, &elem(&1, 1)),
           [namespace] <- moves |> Enum.map(& &1.namespace) |> Enum.uniq(),
           [_ | _] = prefix <- common_prefix(Enum.map(moves, & &1.segments)) do
        path = "/" <> Enum.join(prefix, "/")
        moves = Enum.map(moves, &Map.put(&1, :inner, inner_path(&1.segments, length(prefix))))
        code = "scope #{inspect(path)}, #{namespace}"
        {first, _route} = hd(routes)

        {:ok,
         %{
           kind: :flat,
           key: {router, code},
           router: router,
           line: Sourceror.get_line(first),
           code: code,
           routes: Enum.map(routes, &elem(&1, 1)),
           moves: moves
         }}
      else
        {:error, reason} -> {:error, [reason]}
        [] -> {:error, ["its routes share no path"]}
        _namespaces -> {:error, ["its routes do not name their LiveViews with the same namespace"]}
      end
    end

    defp flat_move({:live, _, [{:__block__, _, [path]}, {:__aliases__, _, [_, _ | _] = parts} | rest]})
         when is_binary(path) do
      if Enum.all?(parts, &is_atom/1) and hd(parts) != :"Elixir" do
        {namespace, [short]} = Enum.split(parts, -1)

        {:ok,
         %{
           path: path,
           written: Enum.join(parts, "."),
           namespace: Enum.join(namespace, "."),
           short: to_string(short),
           segments: String.split(path, "/", trim: true),
           rest: Enum.map(rest, &Sourceror.to_string/1)
         }}
      else
        {:error, "a route names its LiveView in a way the task cannot rewrite"}
      end
    end

    defp flat_move(_node), do: {:error, "a route names its LiveView without its domain namespace"}

    defp common_prefix([first | rest]) do
      Enum.reduce(rest, first, fn segments, prefix ->
        prefix |> Enum.zip(segments) |> Enum.take_while(fn {left, right} -> left == right end) |> Enum.map(&elem(&1, 0))
      end)
    end

    defp inner_path(segments, depth) do
      case Enum.drop(segments, depth) do
        [] -> "/"
        rest -> "/" <> Enum.join(rest, "/")
      end
    end

    # Each wrapped group gains a `scope` and an `end` line.
    defp shift_lines(plans) do
      {plans, _shifts} =
        plans
        |> Enum.sort_by(&{&1.router, &1.line})
        |> Enum.map_reduce(%{}, fn plan, shifts ->
          shift = Map.get(shifts, plan.router, 0)
          plan = %{plan | line: plan.line + shift}

          if Map.get(plan, :kind) == :flat,
            do: {plan, Map.put(shifts, plan.router, shift + 2)},
            else: {plan, shifts}
        end)

      plans
    end

    # The routes' lines are rewritten as text, so the comments and blank
    # lines between them, and a comment at the end of a route's line, stay
    # where they were; a comment above the first route stays above the scope.
    defp wrap_flat(content, scope) do
      lines = String.split(content, "\n")

      ranges =
        content
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Common.find_all(&live_call?/1)
        |> Enum.flat_map(fn zipper ->
          node = Zipper.node(zipper)

          case Enum.find(scope.moves, &moved_route?(node, &1)) do
            nil -> []
            move -> [{Sourceror.get_range(node), move}]
          end
        end)
        |> Enum.sort_by(fn {range, _move} -> range.start[:line] end)

      if length(ranges) == length(scope.moves) do
        first = ranges |> Enum.map(fn {range, _move} -> range.start[:line] end) |> Enum.min()
        last = ranges |> Enum.map(fn {range, _move} -> range.end[:line] end) |> Enum.max()
        indent = lines |> Enum.at(first - 1) |> leading_whitespace()

        wrapped =
          ["#{indent}#{scope.code}, as: :#{scope.name} do"] ++
            wrapped_lines(lines, first, last, ranges, indent <> "  ") ++ ["#{indent}end"]

        Enum.join(Enum.take(lines, first - 1) ++ wrapped ++ Enum.drop(lines, last), "\n")
      else
        content
      end
    end

    defp wrapped_lines(lines, first, last, ranges, indent) do
      starts = Map.new(ranges, fn {range, move} -> {range.start[:line], {range, move}} end)

      first
      |> Stream.unfold(fn
        number when number > last ->
          nil

        number ->
          case Map.fetch(starts, number) do
            {:ok, {range, move}} -> {route_line(lines, range, move, indent), range.end[:line] + 1}
            :error -> {kept_line(Enum.at(lines, number - 1), indent), number + 1}
          end
      end)
      |> Enum.to_list()
    end

    defp route_line(lines, range, move, indent) do
      route = Enum.join(["live #{inspect(move.inner)}", move.short | move.rest], ", ")
      # What follows the route on its last line: an end-of-line comment.
      rest = lines |> Enum.at(range.end[:line] - 1) |> String.slice((range.end[:column] - 1)..-1//1)
      indent <> route <> if(rest =~ ~r/^\s*#/, do: rest, else: "")
    end

    defp kept_line(line, indent) do
      if String.trim(line) == "", do: "", else: indent <> String.trim_leading(line)
    end

    defp leading_whitespace(line), do: line |> String.split(~r/\S/, parts: 2) |> hd()

    defp moved_route?(node, move) do
      case node do
        {:live, _, [{:__block__, _, [path]}, {:__aliases__, _, parts} | _]} ->
          path == move.path and Enum.join(parts, ".") == move.written

        _node ->
          false
      end
    end

    ## Rewrite

    defp apply_scope(igniter, %{kind: :flat} = scope) do
      name = Sourceror.parse_string!(":" <> scope.name)

      igniter
      |> Igniter.update_file(scope.router, &Source.update(&1, :content, fn content -> wrap_flat(content, scope) end))
      |> set_router_scopes(scope, name)
    end

    defp apply_scope(igniter, scope) do
      name = Sourceror.parse_string!(":" <> scope.name)

      igniter
      |> Igniter.update_elixir_file(scope.router, fn zipper ->
        Common.update_all_matches(zipper, &scope_at?(&1, scope.code), &add_as(&1, name))
      end)
      |> set_router_scopes(scope, name)
    end

    defp set_router_scopes(igniter, scope, name) do
      Enum.reduce(scope.schemas, igniter, fn schema, igniter ->
        ProjectModule.find_and_update_module!(igniter, schema, &set_router_scope(&1, name))
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
