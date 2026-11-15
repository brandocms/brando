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

  An entry with no host, such as `agency.example` without `//`, raises
  `ArgumentError`, as it does in Phoenix's list.
  """

  alias Brando.Tenant.Cache
  alias Brando.Tenant.InstallationHosts

  @spec allowed?(URI.t(), [String.t()]) :: boolean()
  def allowed?(uri, origins \\ [])

  def allowed?(uri, origins) do
    origins = Enum.map(origins, &parse_origin/1)

    case uri do
      %URI{host: host} when is_binary(host) and host != "" ->
        host = host |> String.trim() |> String.downcase()

        InstallationHosts.member?(host) or Cache.get_env_by_domain(host) != nil or
          Enum.any?(origins, &origin_matches?(%{uri | host: host}, &1))

      _uri ->
        false
    end
  end

  defp parse_origin(origin) do
    case URI.parse(origin) do
      %URI{host: host} = parsed when is_binary(host) and host != "" ->
        %{parsed | host: String.downcase(host)}

      _no_host ->
        raise ArgumentError,
              "invalid origin for Brando.Tenant.Origins: #{inspect(origin)}. Expected an origin with a host, " <>
                "such as \"//example.com\", \"//*.example.com\" or \"https://example.com:8443\""
    end
  end

  # As Phoenix compares an entry of a `check_origin` list
  defp origin_matches?(uri, %URI{scheme: scheme, host: allowed_host, port: port}) do
    (is_nil(scheme) or scheme == uri.scheme) and (is_nil(port) or port == uri.port) and
      host_matches?(uri.host, allowed_host)
  end

  defp host_matches?(host, "*." <> allowed), do: host == allowed or String.ends_with?(host, "." <> allowed)
  defp host_matches?(host, allowed), do: host == allowed
end
