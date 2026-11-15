defmodule Brando.Tenant.Origins do
  @moduledoc """
  A `check_origin` for the endpoint of a multi-site installation, whose sites
  are added in the admin after the endpoint's configuration was written:

      config :my_app, MyAppWeb.Endpoint,
        check_origin: {Brando.Tenant.Origins, :allowed?, []}

  A socket's origin is accepted when its host is one the installation itself
  uses (`Brando.Tenant.InstallationHosts`: the endpoint's, its static, media
  and CDN hosts) or an active site's environment's domain, read from
  `Brando.Tenant.Cache`. A redirect host is not accepted: nothing is served
  on it.

  Further origins, in the forms Phoenix's `check_origin` list takes (`//host`,
  `//*.host`, `https://host:8443`), are passed as the argument:

      check_origin: {Brando.Tenant.Origins, :allowed?, [["//*.agency.example"]]}
  """

  alias Brando.Tenant.Cache
  alias Brando.Tenant.InstallationHosts

  @spec allowed?(URI.t(), [String.t()]) :: boolean()
  def allowed?(uri, origins \\ [])

  def allowed?(%URI{host: host} = uri, origins) when is_binary(host) and host != "" do
    host = host |> String.trim() |> String.downcase()

    InstallationHosts.member?(host) or Cache.get_env_by_domain(host) != nil or
      Enum.any?(origins, &origin_matches?(%{uri | host: host}, &1))
  end

  def allowed?(_uri, _origins), do: false

  # As Phoenix compares an entry of a `check_origin` list
  defp origin_matches?(uri, origin) do
    %URI{scheme: scheme, host: allowed_host, port: port} = URI.parse(origin)

    (is_nil(scheme) or scheme == uri.scheme) and (is_nil(port) or port == uri.port) and
      host_matches?(uri.host, allowed_host && String.downcase(allowed_host))
  end

  defp host_matches?(_host, nil), do: true
  defp host_matches?(host, "*." <> allowed), do: host == allowed or String.ends_with?(host, "." <> allowed)
  defp host_matches?(host, allowed), do: host == allowed
end
