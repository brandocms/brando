defmodule Brando.Tenant.ServedHosts.DNS do
  @moduledoc """
  The system resolver for `Brando.Tenant.ServedHosts`: the host's IPv4 and
  IPv6 addresses, each family looked up with a three-second timeout.

  A family with no records counts as none. A family whose lookup fails any
  other way (a timeout, a refused query) fails the whole lookup: a record
  that could not be read may point elsewhere.
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
