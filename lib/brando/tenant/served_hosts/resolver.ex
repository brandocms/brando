defmodule Brando.Tenant.ServedHosts.Resolver do
  @moduledoc """
  Looks up a host for `Brando.Tenant.ServedHosts`: every address it resolves
  to, IPv4 and IPv6 together. An error means the host did not resolve, or the
  lookup could not tell; either way the host is not admitted.

  Tests replace it with `config :brando, Brando.Tenant.ServedHosts, resolver: MyResolver`.
  """

  @callback lookup(host :: String.t()) :: {:ok, [:inet.ip_address()]} | {:error, term()}
end
