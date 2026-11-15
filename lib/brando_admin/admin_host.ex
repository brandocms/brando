defmodule BrandoAdmin.AdminHost do
  @moduledoc """
  Where the admin answers. With `tenancy_mode: :multi` that is the endpoint's
  host only (`Brando.endpoint().host()`, what `PHX_HOST` sets): every route
  `Brando.Router.admin_routes/3` and `Brando.Router.mcp_routes/0` mount
  answers on another host as if it did not exist there, and the admin socket
  takes connections from the endpoint's host only (`check_origin/1`). With
  `:none` and `:single` the admin answers on every host, as the site's host
  and the admin's are normally the same.

  Deciding reads the tenancy mode and the endpoint's configuration, never the
  database.
  """

  alias Brando.Tenant

  # The paths `Brando.Router.mcp_routes/0` mounts, as decoded path segments
  @mcp_prefixes [
    ["mcp"],
    [".well-known", "oauth-protected-resource", "mcp"],
    [".well-known", "oauth-authorization-server", "mcp"],
    ["admin", "mcp"]
  ]

  @doc """
  For the admin socket's `check_origin`, so that it takes connections from
  the endpoint's host only, whatever the endpoint's own `check_origin`
  accepts for the site's pages:

      socket "/admin/socket", BrandoAdmin.AdminSocket,
        websocket: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}],
        longpoll: [check_origin: {BrandoAdmin.AdminHost, :check_origin, []}]

  An origin with no host is refused.
  """
  @spec check_origin(URI.t()) :: boolean()
  def check_origin(%URI{host: host}) when is_binary(host), do: admin_host?(host)
  def check_origin(_origin), do: false

  @doc """
  Whether `host` is the endpoint's, where the admin answers in `:multi`.
  Letter case and a trailing dot do not matter.
  """
  @spec admin_host?(String.t() | nil) :: boolean()
  def admin_host?(host) when is_binary(host) do
    case endpoint_host() do
      nil -> false
      endpoint_host -> normalize(host) == endpoint_host
    end
  end

  def admin_host?(_host), do: false

  @doc """
  Whether the admin answers on `conn`'s host: always with `:none` and
  `:single`, on the endpoint's host only with `:multi`.
  """
  @spec serves_admin?(Plug.Conn.t()) :: boolean()
  def serves_admin?(%Plug.Conn{host: host}), do: Tenant.mode() != :multi or admin_host?(host)

  @doc false
  # The endpoint's host, normalized. An endpoint that has not started answers
  # nothing, so its configuration is read instead.
  @spec endpoint_host() :: String.t() | nil
  def endpoint_host do
    normalize(Brando.endpoint().host())
  rescue
    _ -> configured_endpoint_host()
  end

  defp configured_endpoint_host do
    endpoint = Brando.endpoint()
    config = Application.get_env(Application.get_application(endpoint) || Brando.config(:otp_app), endpoint, [])
    normalize(config[:url][:host])
  rescue
    _ -> nil
  end

  defp normalize(host) when is_binary(host), do: host |> String.trim() |> String.downcase() |> String.trim_trailing(".")
  defp normalize(_host), do: nil

  @doc false
  # Called from the `call/2` that `Brando.Router.admin_routes/3` gives the
  # router, before it matches a route: the admin or MCP path prefix `conn` is
  # for when its host does not serve the admin, or nil. Such a request goes to
  # `dispatch_without/3`.
  @spec refused_prefix(Plug.Conn.t(), module()) :: [String.t()] | nil
  def refused_prefix(%Plug.Conn{path_info: path_info, host: host}, router) do
    if Tenant.mode() == :multi do
      prefixes = [router.__brando_admin_path__() | mcp_prefixes(router)]
      prefix = Enum.find(prefixes, &(&1 != [] and starts_with?(path_info, &1)))
      if prefix && not admin_host?(host), do: prefix
    end
  end

  defp mcp_prefixes(router) do
    if function_exported?(router, :__brando_mcp_routes__, 0), do: @mcp_prefixes, else: []
  end

  # The router matches decoded segments, so `/%61dmin` is `/admin` to it
  defp starts_with?(_path_info, []), do: true

  defp starts_with?([segment | path_info], [expected | prefix]),
    do: URI.decode(segment) == expected and starts_with?(path_info, prefix)

  defp starts_with?([], _prefix), do: false

  @doc false
  # Sends `conn` to the route it would match if the routes under `prefix` did
  # not exist, with its pipelines, so it answers as a path that does not exist
  # on its host: the site's catch-all and its 404 page on a site's host, the
  # plain 404 on a host bound to nothing, or the router's own
  # `Phoenix.Router.NoRouteError` when nothing else matches. The prefix's
  # segments are replaced with values no route's literal segment can match,
  # so only a route with parameters there matches; its parameters then get
  # the real segments back.
  @spec dispatch_without(Plug.Conn.t(), module(), [String.t()]) :: Plug.Conn.t()
  def dispatch_without(conn, router, prefix) do
    decoded = Enum.map(conn.path_info, &URI.decode/1)
    placeholders = Enum.map(1..length(prefix)//1, &"\0brando-admin-host-#{&1}")
    probe = placeholders ++ Enum.drop(decoded, length(prefix))
    restore = placeholders |> Enum.zip(Enum.take(decoded, length(prefix))) |> Map.new()

    case router.__match_route__(conn.method, probe, conn.host) do
      {metadata, prepare, pipeline, plug_opts} ->
        metadata = Map.update!(metadata, :path_params, &restore_params(&1, restore))
        Phoenix.Router.__call__(conn, metadata, prepare, pipeline, plug_opts)

      :error ->
        raise Phoenix.Router.NoRouteError, conn: conn, router: router
    end
  end

  defp restore_params(params, restore) do
    Map.new(params, fn
      {key, value} when is_list(value) -> {key, Enum.map(value, &Map.get(restore, &1, &1))}
      {key, value} -> {key, Map.get(restore, value, value)}
    end)
  end
end
