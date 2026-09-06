if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Resource.Routes do
    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule

    def validate_public_path(nil), do: :ok

    def validate_public_path(path) do
      if Regex.match?(~r|^/[a-z][a-z0-9_-]*(?:/[a-z][a-z0-9_-]*)*$|, path) &&
           not String.starts_with?(path, "/admin") do
        :ok
      else
        {:error, "--public-route must be a literal path such as /products, outside /admin."}
      end
    end

    def plan(igniter, metadata, options) do
      igniter = admin(igniter, metadata)
      if options[:public_route], do: public(igniter, metadata, options[:public_route]), else: igniter
    end

    defp admin(igniter, m) do
      path = "/#{Macro.underscore(m.naming.domain)}/#{m.naming.plural}"

      routes = [
        {path, m.admin_list, nil},
        {path <> "/create", m.admin_form, :create},
        {path <> "/update/:entry_id", m.admin_form, :update}
      ]

      ProjectModule.find_and_update_module!(igniter, m.project.router, fn zipper ->
        with {:ok, admin} <- CodeFunction.move_to_function_call_in_current_scope(zipper, :admin_routes, [1, 2, 3]),
             {:ok, body} <- Common.move_to_do_block(admin) do
          Enum.reduce_while(routes, {:ok, body}, &add_admin_route/2)
        else
          _ ->
            {:error,
             "Could not find an admin_routes block in #{inspect(m.project.router)}. Run mix brando.install first."}
        end
      end)
    end

    defp add_admin_route({path, module, action}, {:ok, body}) do
      code = "live #{inspect(path)}, #{inspect(module)}" <> if(action, do: ", :#{action}", else: "")

      case ensure_route(body, :live, path, module, action, code) do
        {:ok, body} -> {:cont, {:ok, body}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end

    defp public(igniter, m, path) do
      ProjectModule.find_and_update_module!(igniter, m.project.router, fn zipper ->
        # A separate scope preserves existing Phoenix scope aliases and pipelines.
        code = """
        scope "/" do
          pipe_through :browser
          get #{inspect(path)}, #{inspect(m.controller)}, :index
          get #{inspect(path <> "/:id")}, #{inspect(m.controller)}, :show
        end
        """

        existing =
          Enum.map([{path, :index}, {path <> "/:id", :show}], fn {path, action} ->
            route_state(zipper, :get, path, m.controller, action)
          end)

        cond do
          existing == [:present, :present] ->
            {:ok, zipper}

          existing == [:missing, :missing] ->
            insert_public_scope(zipper, code)

          true ->
            {:error, "Public routes at #{path} conflict with existing or partial routes. Integrate them explicitly."}
        end
      end)
    end

    defp insert_public_scope(zipper, code) do
      # Place explicit routes ahead of catch-all scopes, after router imports.
      case CodeFunction.move_to_function_call_in_current_scope(zipper, :scope, [2, 3, 4]) do
        {:ok, scope} -> {:ok, Common.add_code(scope, code, placement: :before)}
        :error -> {:ok, Common.add_code(zipper, code)}
      end
    end

    defp ensure_route(body, verb, path, module, action, code) do
      case route_state(body, verb, path, module, action) do
        :present ->
          {:ok, body}

        :missing ->
          {:ok, Common.add_code(body, code)}

        :conflict ->
          {:error,
           "Route #{path} already exists with a different destination. Review it before generating this resource."}
      end
    end

    defp route_state(body, verb, path, module, action) do
      case CodeFunction.move_to_function_call(body, verb, [2, 3, 4], &CodeFunction.argument_equals?(&1, 0, path)) do
        :error ->
          quoted = body.node |> Sourceror.to_string() |> Code.string_to_quoted!()
          if path in declared_paths(quoted, "", verb), do: :conflict, else: :missing

        {:ok, call} ->
          same? =
            CodeFunction.argument_equals?(call, 1, module) &&
              (is_nil(action) || CodeFunction.argument_equals?(call, 2, action))

          if same?, do: :present, else: :conflict
      end
    end

    defp declared_paths({:scope, _, [path | rest]}, prefix, verb) when is_binary(path) do
      declared_paths(rest, join_path(prefix, path), verb)
    end

    defp declared_paths({verb, _, [path | _]}, prefix, verb) when is_binary(path), do: [join_path(prefix, path)]
    defp declared_paths({_, _, args}, prefix, verb) when is_list(args), do: declared_paths(args, prefix, verb)
    defp declared_paths({:do, body}, prefix, verb), do: declared_paths(body, prefix, verb)

    defp declared_paths(nodes, prefix, verb) when is_list(nodes),
      do: Enum.flat_map(nodes, &declared_paths(&1, prefix, verb))

    defp declared_paths(_, _, _), do: []
    defp join_path(prefix, path), do: "/" <> String.trim(prefix <> "/" <> String.trim_leading(path, "/"), "/")
  end
end
