if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.PersistIdentifiers do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # A Blueprint persists identifiers unless it says `persist_identifier
    # false`, and Search, the command palette and the dashboard open them in
    # the entry's admin editor. A Blueprint without one, which no route gives
    # the helper its `__admin_route__(:update, [id])` calls, sets it: the
    # helper is `admin_<singular>_form_path`, or
    # `admin_<router_scope>_<singular>_form_path` (`__admin_route_helper__/1`),
    # routed for `:update`, as `mix brando.doctor`'s admin routes check reads
    # it from the compiled router. The router is read from source here, so a
    # Blueprint is changed only when no admin LiveView names it either.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.RouteInventory
    alias Rewrite.Source
    alias Sourceror.Zipper

    @router ~r/use Phoenix\.Router\b|,\s*:router\b/
    @admin_view ~r/use\s+BrandoAdmin\.LiveView\.(?:Listing|Form),\s*schema:\s*(?:Elixir\.)?([A-Z][\w.]*)/

    def update(igniter) do
      igniter = Igniter.include_glob(igniter, "lib/**/*.ex")
      sources = lib_sources(igniter)

      {igniter, blueprints} =
        ProjectModule.find_all_matching_modules(igniter, fn _module, zipper ->
          match?({:ok, _}, Igniter.Code.Module.move_to_use(zipper, Brando.Blueprint))
        end)

      case routes(igniter, sources) do
        {:ok, routes} ->
          {igniter, results} = Enum.reduce(Enum.sort(blueprints), {igniter, []}, &check(&1, &2, routes, sources))
          report(igniter, Enum.reverse(results))

        :error ->
          Igniter.add_warning(igniter, """
          The task could not read the router's admin routes, so it set
          `persist_identifier` on no Blueprint. Add `persist_identifier false` to
          every Blueprint with no admin editor (no `admin_<singular>_form_path`
          route for `:update`): its entries cannot be opened from Search, the
          command palette or the dashboard. `mix brando.doctor` lists the
          Blueprints the router gives no editor.
          """)
      end
    end

    defp lib_sources(igniter) do
      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
      |> Enum.filter(fn {path, _content} -> String.starts_with?(path, "lib/") and Path.extname(path) == ".ex" end)
    end

    ## Routes

    # `{helper, action}` for every `live` route under `admin_routes`, named
    # as Phoenix names them: the scopes' `as:` and the route's own `as:`, or
    # the LiveView's name from its `…Live` segment on.
    defp routes(igniter, sources) do
      routers = for {path, content} <- sources, content =~ @router, content =~ "admin_routes", do: path

      if routers == [] do
        :error
      else
        routes =
          for router <- routers,
              zipper <- router |> quoted(igniter) |> Common.find_all(&CodeFunction.function_call?(&1, :live, [3, 4])),
              route <- live_route(zipper),
              into: MapSet.new(),
              do: route

        {:ok, routes}
      end
    end

    defp quoted(path, igniter), do: igniter.rewrite |> Rewrite.source!(path) |> Source.get(:quoted) |> Zipper.zip()

    defp live_route(zipper) do
      with [%{kind: :live, module: module, action: action}]
           when is_atom(module) and not is_nil(module) and is_atom(action) and not is_nil(action) <-
             RouteInventory.at(zipper),
           {:ok, prefixes} <- prefixes(Zipper.up(zipper), []),
           true <- "admin" in prefixes,
           {:ok, name} <- route_name(zipper, module) do
        [{Enum.join(prefixes ++ [name], "_"), action}]
      else
        _ -> []
      end
    end

    defp prefixes(nil, prefixes), do: {:ok, prefixes}

    defp prefixes(zipper, prefixes) do
      prefix =
        case Zipper.node(zipper) do
          {:admin_routes, _, _} -> "admin"
          {:scope, _, arguments} when is_list(arguments) -> as_option(arguments)
          _node -> nil
        end

      prefixes(Zipper.up(zipper), if(prefix, do: [prefix | prefixes], else: prefixes))
    end

    defp route_name(zipper, module) do
      {:live, _, arguments} = Zipper.node(zipper)

      case as_option(arguments) do
        nil -> inferred_name(module)
        name -> {:ok, name}
      end
    end

    defp as_option(arguments) do
      Enum.find_value(arguments, fn
        options when is_list(options) ->
          Enum.find_value(options, fn
            {{:__block__, _, [:as]}, {:__block__, _, [as]}} when is_atom(as) -> to_string(as)
            _option -> nil
          end)

        _argument ->
          nil
      end)
    end

    # Phoenix.LiveView.Router's name for a route with an action.
    defp inferred_name(module) do
      module
      |> Module.split()
      |> Enum.drop_while(&(not String.ends_with?(&1, "Live")))
      |> Enum.map(&(&1 |> String.replace_suffix("Live", "") |> Macro.underscore()))
      |> Enum.reject(&(&1 == ""))
      |> case do
        [] -> :error
        parts -> {:ok, Enum.join(parts, "_")}
      end
    end

    ## Blueprints

    defp check(module, {igniter, results}, routes, sources) do
      {:ok, {igniter, source, zipper}} = ProjectModule.find_module(igniter, module)
      path = Source.get(source, :path)

      case blueprint(zipper) do
        :skip ->
          {igniter, results}

        {:unknown, reason} ->
          {igniter, [{:unknown, module, path, reason} | results]}

        {:ok, helper} ->
          cond do
            MapSet.member?(routes, {helper, :update}) ->
              {igniter, results}

            admin_view?(module, sources) ->
              {igniter,
               [{:unknown, module, path, "has admin LiveViews but no `#{helper}_path` route for `:update`"} | results]}

            true ->
              {ProjectModule.find_and_update_module!(igniter, module, &persist_false/1),
               [{:changed, module, path, helper} | results]}
          end
      end
    end

    # `{:ok, helper}`, `:skip` for a Blueprint that already decides or never
    # persists, or `{:unknown, reason}`.
    defp blueprint(zipper) do
      {:ok, body} = Common.move_to_do_block(zipper)

      cond do
        call?(body, :persist_identifier, fn _value -> true end) -> :skip
        call?(body, :identifier, &(&1 == false)) -> :skip
        call?(body, :data_layer, &(&1 == :embedded)) -> :skip
        true -> helper(body)
      end
    end

    defp call?(body, name, value?) do
      body
      |> Common.find_all(&CodeFunction.function_call?(&1, name, 1))
      |> Enum.any?(fn call ->
        case Zipper.node(call) do
          {^name, _, [{:__block__, _, [value]}]} -> value?.(value)
          {^name, _, [_value]} -> value?.(:other)
        end
      end)
    end

    defp helper(body) do
      with {:ok, use_zipper} <- Igniter.Code.Module.move_to_use(body, Brando.Blueprint),
           {:ok, options} <- CodeFunction.move_to_nth_argument(use_zipper, 1),
           {:ok, singular} <- literal(options, :singular, &is_binary/1),
           {:ok, scope} <- optional_literal(options, :router_scope) do
        {:ok, Enum.join(["admin", scope, singular, "form"] |> Enum.reject(&is_nil/1), "_")}
      else
        _ -> {:unknown, "its `use Brando.Blueprint` options have no literal `singular` or `router_scope`"}
      end
    end

    defp literal(options, key, valid?) do
      with {:ok, value} <- Igniter.Code.Keyword.get_key(options, key),
           {:__block__, _, [value]} <- Zipper.node(value),
           true <- valid?.(value) do
        {:ok, value}
      else
        _ -> :error
      end
    end

    defp optional_literal(options, key) do
      case Igniter.Code.Keyword.get_key(options, key) do
        :error ->
          {:ok, nil}

        {:ok, _value} ->
          with {:ok, value} <- literal(options, key, &(is_binary(&1) or (is_atom(&1) and not is_nil(&1)))),
               do: {:ok, to_string(value)}
      end
    end

    defp admin_view?(module, sources) do
      Enum.any?(sources, fn {_path, content} ->
        Enum.any?(Regex.scan(@admin_view, content), fn [_, schema] -> schema == inspect(module) end)
      end)
    end

    defp persist_false(body) do
      case Common.move_to(body, &CodeFunction.function_call?(&1, :identifier, 1)) do
        {:ok, identifier} ->
          {:ok, Common.add_code(identifier, "persist_identifier false", placement: :after)}

        :error ->
          with {:ok, use_zipper} <- Igniter.Code.Module.move_to_use(body, Brando.Blueprint),
               do: {:ok, Common.add_code(use_zipper, "persist_identifier false", placement: :after)}
      end
    end

    ## Report

    defp report(igniter, results) do
      changed = for {:changed, module, path, helper} <- results, do: "  #{inspect(module)} (#{path}): no `#{helper}_path`"
      unknown = for {:unknown, module, path, reason} <- results, do: "  #{inspect(module)} (#{path}): #{reason}"

      igniter
      |> notice(changed)
      |> warning(unknown)
    end

    defp notice(igniter, []), do: igniter

    defp notice(igniter, changed) do
      Igniter.add_notice(igniter, """
      These Blueprints have no admin editor, neither an `:update` form route
      nor an admin LiveView, so the task set `persist_identifier false` on them.
      Their entries could not be opened from Search, the command palette or the
      dashboard, which leave them out:

      #{Enum.join(changed, "\n")}
      """)
    end

    defp warning(igniter, []), do: igniter

    defp warning(igniter, unknown) do
      Igniter.add_warning(igniter, """
      Decide whether these Blueprints persist identifiers. Add
      `persist_identifier false` to a Blueprint with no admin editor, or route
      its FormLive for `:update` (`mix brando.doctor` checks the routes):

      #{Enum.join(unknown, "\n")}
      """)
    end
  end
else
  defmodule Mix.Brando.Igniter.PersistIdentifiers do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
