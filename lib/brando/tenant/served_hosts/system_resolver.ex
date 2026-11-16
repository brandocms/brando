defmodule Brando.Tenant.ServedHosts.SystemResolver do
  @moduledoc """
  A resolver for `Brando.Tenant.ServedHosts` that asks the operating system,
  as other programs on the server do: the host's IPv4 and IPv6 addresses, one
  family after the other, through the `getaddrs` function of Erlang's `:inet`
  module. It reads `/etc/hosts` and the platform's resolver configuration,
  which the default resolver, `Brando.Tenant.ServedHosts.DNS`, does not.
  Choose it for an installation whose hosts resolve only through those:

      config :brando, Brando.Tenant.ServedHosts,
        file: "/srv/my_app/shared/served_hosts",
        resolver: Brando.Tenant.ServedHosts.SystemResolver

  Its weakness: it cannot tell a family that has no records from one that
  could not be read. `:inet` reports every failure of its last lookup method
  as `:nxdomain`, a timeout or a refused query included, so a family whose
  lookup failed counts as one with no records: a host whose IPv4 lookup
  answers this server's address while its IPv6 lookup times out is admitted,
  although its IPv6 record may point at another server, where a certificate
  authority that prefers IPv6 then fails the proxy's certificate request.
  Each family is asked to answer within three seconds, which the operating
  system's resolver (the default lookup method on Unix) does not heed: the
  `:lookup_timeout` of `Brando.Tenant.ServedHosts` is what bounds a lookup.
  Only an error `:inet` passes on (an invalid name) fails the whole lookup.
  """

  @behaviour Brando.Tenant.ServedHosts.Resolver

  @timeout :timer.seconds(3)

  @impl true
  def lookup(host) when is_binary(host) do
    host = String.to_charlist(host)

    Enum.reduce_while([:inet, :inet6], {:ok, []}, fn family, {:ok, found} ->
      case :inet.getaddrs(host, family, @timeout) do
        {:ok, addresses} -> {:cont, {:ok, found ++ addresses}}
        {:error, :nxdomain} -> {:cont, {:ok, found}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, []} -> {:error, :nxdomain}
      result -> result
    end
  end
end
