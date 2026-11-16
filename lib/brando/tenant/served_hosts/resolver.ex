defmodule Brando.Tenant.ServedHosts.Resolver do
  @moduledoc """
  Looks up a host for `Brando.Tenant.ServedHosts`: every address it resolves
  to, IPv4 and IPv6 together.

    * `{:ok, addresses}`: both families were read, and these are all the
      host's addresses. An empty list means it has none.
    * `{:incomplete, addresses, families}`: the families in `families`
      (`:inet`, `:inet6`) could not be read, as when their query timed out or
      the name server failed; `addresses` are those of the families that
      were. The host is not admitted on the strength of the families read,
      and is looked up again at the next check.
    * `{:error, :nxdomain}`: the host has no addresses.
    * `{:error, reason}`: the lookup failed, and could not tell whether the
      host resolves.

  The host is admitted only on `{:ok, addresses}`, when every one of them is
  this server's. The admin shows **Does not resolve** for a host with no
  addresses, and **Could not look it up** for a lookup that failed or was
  incomplete.

  Set with `config :brando, Brando.Tenant.ServedHosts, resolver: MyResolver`.
  Brando has two: `Brando.Tenant.ServedHosts.DNS` (the default) and
  `Brando.Tenant.ServedHosts.SystemResolver`.
  """

  @type family :: :inet | :inet6

  @callback lookup(host :: String.t()) ::
              {:ok, [:inet.ip_address()]}
              | {:incomplete, [:inet.ip_address()], [family(), ...]}
              | {:error, term()}
end
