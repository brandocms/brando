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
  def serves_admin?(%Plug.Conn{host: host}), do: serves_admin_on?(host)

  @doc """
  Whether the admin answers on `host`, as `serves_admin?/1` decides for a
  conn. The router matches routes with it (`Brando.Router.admin_routes/3`):
  on a host where it does not, the routes `admin_routes/3` and
  `Brando.Router.mcp_routes/0` mount are left out of the match, the
  application's own routes keeping their order, so an admin or MCP path
  answers as a path that does not exist there, for a request and for
  `Phoenix.Router.route_info/4` alike.
  """
  @spec serves_admin_on?(String.t() | nil) :: boolean()
  def serves_admin_on?(host), do: Tenant.mode() != :multi or admin_host?(host)

  @doc """
  The endpoint's host, in lower case and without a trailing dot, or nil. An
  endpoint that has not started answers nothing, so its configuration is
  read instead.
  """
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
end
