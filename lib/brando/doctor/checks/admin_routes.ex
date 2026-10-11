defmodule Brando.Doctor.Checks.AdminRoutes do
  @moduledoc """
  The router helper Blueprints link to their editor with. For every
  application Blueprint with an admin listing or form route, the router
  defines the helper its
  `__admin_route__(:update, [id])` calls: `admin_<singular>_form_path` with
  `:update`, or `admin_<scope>_<singular>_form_path` with
  `router_scope: :<scope>`. Listing rows, search, the dashboard and the
  command palette link through it, and a listing whose rows cannot crashes.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  @impl true
  def id, do: "admin_routes"

  @impl true
  def label, do: dgettext("doctor", "Admin routes")

  @impl true
  def run(_context) do
    router = Brando.router()

    if Code.ensure_loaded?(router) and function_exported?(router, :__routes__, 0) do
      router |> Phoenix.Router.routes() |> missing_routes() |> evaluate()
    else
      skipped(dgettext("doctor", "no router %{router}", router: inspect(router)))
    end
  end

  @doc """
  `[{schema, [{helper, action}]}]`: the helpers each Blueprint with admin
  routes calls that `routes` (`Phoenix.Router.routes/1`) do not define, as
  `{:admin_project_form_path, :update}`.
  """
  def missing_routes(routes) do
    defined = MapSet.new(routes, &{&1.helper, &1.plug_opts})

    routes
    |> Enum.flat_map(&admin_resource/1)
    |> Enum.uniq()
    |> Enum.filter(&application_blueprint?/1)
    |> Enum.map(&{&1, Enum.reject(needed(&1), fn helper -> defined?(defined, helper) end)})
    |> Enum.reject(fn {_schema, missing} -> missing == [] end)
    |> Enum.sort()
  end

  defp admin_resource(%{metadata: %{phoenix_live_view: {view, _action, _opts, _extra}}}) do
    if Code.ensure_loaded?(view) and function_exported?(view, :__authorization_resource__, 0) do
      case view.__authorization_resource__() do
        {kind, schema} when kind in [:form, :listing] and is_atom(schema) -> [schema]
        _other -> []
      end
    else
      []
    end
  end

  defp admin_resource(_route), do: []

  # Brando's own editors (identity, SEO, files) route differently on purpose.
  defp application_blueprint?(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :__admin_route_helper__, 1) and
      schema.__naming__().application != "Brando"
  end

  defp needed(schema), do: [{schema.__admin_route_helper__(:update), :update}]

  defp defined?(defined, {helper, action}) do
    MapSet.member?(defined, {helper |> Atom.to_string() |> String.replace_suffix("_path", ""), action})
  end

  @doc "Turns `missing_routes/1` into a result."
  def evaluate([]), do: ok(dgettext("doctor", "every Blueprint's admin route helpers exist"))

  def evaluate(missing) do
    error(
      dngettext(
        "doctor",
        "%{count} Blueprint links to admin routes the router does not define",
        "%{count} Blueprints link to admin routes the router does not define",
        length(missing)
      ),
      fix:
        dgettext(
          "doctor",
          "route each schema's FormLive as live \"/<plural>/create\", <Name>FormLive, :create and live \"/<plural>/update/:entry_id\", <Name>FormLive, :update (mix brando.migrate54 converts generated Create/Update LiveViews). Schemas sharing a singular need their routes in a scope with as: and the same router_scope on their Blueprints"
        ),
      items:
        Enum.map(missing, fn {schema, helpers} ->
          dgettext("doctor", "%{schema}: %{helpers}",
            schema: inspect(schema),
            helpers: Enum.map_join(helpers, ", ", &format_helper/1)
          )
        end)
    )
  end

  defp format_helper({helper, action}), do: "#{helper} (:#{action})"
end
