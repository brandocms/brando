if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Resource.Routes do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.RouteInventory

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

    @doc """
    The CMS site's layout module when `brando.gen.site` has set up the public
    site (its `:brando_site` pipeline and `Web.CMS.Layouts`), or nil.
    """
    def site_layouts(igniter, project, options) do
      layouts = Module.concat(project.web_module, CMS.Layouts)

      with path when is_binary(path) <- options[:public_route],
           {:ok, {igniter, _, router}} <- ProjectModule.find_module(igniter, project.router),
           {:ok, _} <- site_pipeline(router),
           {true, igniter} <- ProjectModule.module_exists(igniter, layouts) do
        {igniter, layouts}
      else
        {:error, %Igniter{} = igniter} -> {igniter, nil}
        {false, igniter} -> {igniter, nil}
        _ -> {igniter, nil}
      end
    end

    defp site_pipeline(router),
      do: CodeFunction.move_to_function_call(router, :pipeline, 2, &CodeFunction.argument_equals?(&1, 0, :brando_site))

    defp public(igniter, m, path) do
      show_path = path <> "/:" <> m.param
      pipelines = if m.site_layouts, do: "[:browser, :brando_site]", else: ":browser"

      ProjectModule.find_and_update_module!(igniter, m.project.router, fn zipper ->
        # A separate scope preserves existing Phoenix scope aliases and pipelines.
        code = """
        scope "/" do
          pipe_through #{pipelines}
          get #{inspect(path)}, #{inspect(m.controller)}, :index
          get #{inspect(show_path)}, #{inspect(m.controller)}, :show
        end
        """

        existing =
          Enum.map([{path, :index}, {show_path, :show}], fn {path, action} ->
            route_state(zipper, :get, path, m.controller, action)
          end)

        cond do
          existing == [:present, :present] ->
            {:ok, zipper}

          existing == [:missing, :missing] ->
            insert_public_scope(zipper, code, m)

          true ->
            {:error, "Public routes at #{path} conflict with existing or partial routes. Integrate them explicitly."}
        end
      end)
    end

    # Explicit routes go ahead of catch-all scopes: with the CMS site, right
    # before the scope holding its catch-all, after the :brando_site pipeline;
    # otherwise before the first route, after router imports.
    defp insert_public_scope(zipper, code, %{site_layouts: nil}), do: RouteInventory.insert_before_routes(zipper, code)

    defp insert_public_scope(zipper, code, m) do
      page_controller = Module.concat(m.project.web_module, CMS.PageController)

      cms_scope? = fn call ->
        CodeFunction.function_call?(call, :scope, :any) &&
          Enum.any?(RouteInventory.at(call), &(&1.module == page_controller && String.contains?(&1.path, "*")))
      end

      case Common.move_to(zipper, cms_scope?) do
        {:ok, scope} -> {:ok, Common.add_code(scope, code, placement: :before)}
        :error -> RouteInventory.insert_before_routes(zipper, code)
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
      routes =
        body
        |> RouteInventory.read()
        |> Enum.filter(fn route ->
          # Explicit generated routes are inserted before catch-alls. Other
          # resource/forward declarations still own their named path segments.
          route.kind in [verb, :live, :get, :match, :resources, :forward, :admin_routes, :unknown] &&
            not String.contains?(route.path, "*") && RouteInventory.covers?(route, path)
        end)

      case routes do
        [] ->
          :missing

        [%{kind: ^verb, path: existing_path, module: ^module, action: ^action}] ->
          if RouteInventory.same_path?(existing_path, path), do: :present, else: :conflict

        _ ->
          :conflict
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.Resource.Routes do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
