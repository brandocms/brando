defmodule Brando.Tenant.ServedHosts.DNS do
  @moduledoc """
  The system resolver for `Brando.Tenant.ServedHosts`: the host's IPv4 and
  IPv6 addresses, one family after the other, through the `getaddrs`
  function of Erlang's `:inet` module, with a timeout.
  Each is asked to answer within three seconds, which the operating system's
  resolver (the default lookup method on Unix) does not heed: the
  `:lookup_timeout` of `Brando.Tenant.ServedHosts` is what bounds a lookup.

  A family with no records counts as none. `:inet` reports every failure of
  its last lookup method as `:nxdomain`, a timeout or a refused query
  included, so a family that could not be read counts as one with no
  records: a host whose IPv4 lookup answers and whose IPv6 lookup times out
  resolves to its IPv4 addresses alone. Only an error `:inet` passes on (an
  invalid name) fails the whole lookup.
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
