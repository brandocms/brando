defmodule Brando.Tenant.ServedHosts.Resolver do
  @moduledoc """
  Looks up a host for `Brando.Tenant.ServedHosts`: every address it resolves
  to, IPv4 and IPv6 together.

    * `{:ok, addresses}`: both families were read, and these are all the
      host's addresses. An empty list means it has none.
    * `{:incomplete, addresses, families, reasons}`: the families in
      `families` (`:inet`, `:inet6`) could not be read, as when their query
      timed out or the name server failed; `addresses` are those of the
      families that were. `reasons` maps each unread family to why, one of
      `t:reason/0`. The three-element form,
      `{:incomplete, addresses, families}`, leaves the reasons out. The host
      is not admitted on the strength of the families read, and is looked up
      again at the next check.
    * `{:error, :nxdomain}`: the host has no addresses.
    * `{:error, reason}`: the lookup failed, and could not tell whether the
      host resolves; a `reason` that is one of `t:reason/0` is shown for both
      families.

  The host is admitted only on `{:ok, addresses}`, when every one of them is
  this server's. The admin shows **Does not resolve** for a host with no
  addresses, and **Could not look it up** for a lookup that failed or was
  incomplete, with the family and the reason. A family with no reason, or
  with one that is not a `t:reason/0`, counts as `:other`.

  Set with `config :brando, Brando.Tenant.ServedHosts, resolver: MyResolver`.
  Brando has two: `Brando.Tenant.ServedHosts.DNS` (the default) and
  `Brando.Tenant.ServedHosts.SystemResolver`.
  """

  @type family :: :inet | :inet6

  @typedoc """
  Why a family could not be read: its query timed out (`:timeout`), the name
  server reported a failure (`:server_failure`) or refused the query
  (`:refused`), its answer was cut short (`:truncated`), no name server is
  configured (`:no_name_servers`), or another error (`:other`).
  """
  @type reason :: :timeout | :server_failure | :refused | :truncated | :no_name_servers | :other

  @callback lookup(host :: String.t()) ::
              {:ok, [:inet.ip_address()]}
              | {:incomplete, [:inet.ip_address()], [family(), ...]}
              | {:incomplete, [:inet.ip_address()], [family(), ...], %{optional(family()) => reason()}}
              | {:error, term()}

  @doc false
  # Every `t:reason/0`
  def reasons, do: [:timeout, :server_failure, :refused, :truncated, :no_name_servers, :other]
end
