defmodule Brando.Tenant.ServedHosts.DNS do
  @moduledoc """
  The default resolver for `Brando.Tenant.ServedHosts`: the host's IPv4 (`A`)
  and IPv6 (`AAAA`) records, one family after the other, asked of the name
  servers through Erlang's `:inet_res`, and a `CNAME` chain followed to its
  addresses.

  It tells a family with no records from one that could not be read:

    * a name the name server says does not exist, or that has no record of
      the family, has none of that family;
    * a query that times out, a name server that fails or refuses it, an
      answer that cannot be decoded or that comes with its truncation flag
      set (records may have been cut off), a `CNAME` chain longer than eight
      queries, or no name server to ask, leaves the family unread.

  A host with an unread family answers
  `{:incomplete, addresses, families, reasons}` (see
  `Brando.Tenant.ServedHosts.Resolver`), with both families unread too, and
  is not admitted on the strength of the other family. A host with no
  records of either family does not resolve.

  Each query gives each name server a second to answer, then two on a
  second try. One family, the queries for a `CNAME`'s target included, takes
  at most four seconds, so a host takes at most eight, within the default
  `:lookup_timeout` of `Brando.Tenant.ServedHosts`. A `:lookup_timeout` below
  that cuts the lookup short, and the host counts as not looked up.

  Name servers that do not answer use up that budget. Each query asks the
  name servers in their configured order and gives a dead one a second
  before moving on, so with the first two of three dead each query spends two
  seconds before the third answers. A host behind a `CNAME` with no record of
  a family needs two queries for that family, and the second one reaches the
  four-second limit: the family times out, and the host is not admitted
  while those name servers stay dead. The admin shows such a family's lookup
  as timed out; remove or fix the dead name servers in the resolver
  configuration.

  `:inet_res` asks the name servers of the system's resolver configuration
  (`/etc/resolv.conf` on Unix) itself. It does not read `/etc/hosts`, nor
  platform-specific resolver configuration (`nsswitch.conf`, the per-domain
  resolvers of macOS, mDNS). An installation whose hosts resolve only through
  those sets `resolver: Brando.Tenant.ServedHosts.SystemResolver`, which asks
  the operating system, at the cost of counting a family whose lookup timed
  out as one with no records.
  """

  @behaviour Brando.Tenant.ServedHosts.Resolver

  # The longest one family takes, its queries for a CNAME's targets included
  @family_timeout :timer.seconds(4)
  # `:inet_res`'s per-query timeout: the first try waits half of it (it is
  # divided by the tries), the second all of it
  @query_timeout :timer.seconds(2)
  @tries 2
  # Queries per family: the name's, then one for each CNAME target a name
  # server's answer did not resolve
  @max_queries 8

  @families [inet: :a, inet6: :aaaa]

  @impl true
  def lookup(host), do: lookup(host, &:inet_res.resolve/5)

  @doc false
  # `resolve` stands in for `:inet_res.resolve/5`, so tests ask no name server
  def lookup(host, resolve) when is_binary(host) and is_function(resolve, 5) do
    name = host |> String.trim_trailing(".") |> String.downcase()

    @families
    |> Enum.map(fn {family, type} -> {family, read_family(name, type, resolve)} end)
    |> combine()
  end

  defp combine(read) do
    addresses = for {_family, {:ok, addresses}} <- read, address <- addresses, do: address
    unread = for {family, {:error, reason}} <- read, do: {family, reason(reason)}

    cond do
      unread == [] and addresses == [] -> {:error, :nxdomain}
      unread == [] -> {:ok, addresses}
      true -> {:incomplete, addresses, Keyword.keys(unread), Map.new(unread)}
    end
  end

  # What the admin and the log say of an unread family
  defp reason(:timeout), do: :timeout
  defp reason(:servfail), do: :server_failure
  defp reason(:refused), do: :refused
  defp reason(:truncated), do: :truncated
  defp reason(:no_name_servers), do: :no_name_servers
  defp reason(_other), do: :other

  defp read_family(name, type, resolve) do
    deadline = System.monotonic_time(:millisecond) + @family_timeout
    query(name, type, resolve, deadline, [name], @max_queries)
  end

  defp query(_name, _type, _resolve, _deadline, _seen, 0), do: {:error, :cname_chain_too_long}

  defp query(name, type, resolve, deadline, seen, queries) do
    case deadline - System.monotonic_time(:millisecond) do
      left when left > 0 ->
        name
        |> String.to_charlist()
        |> resolve.(:in, type, [timeout: @query_timeout, retry: @tries, nxdomain_reply: true], left)
        |> answer(name, type, fn target, seen -> query(target, type, resolve, deadline, seen, queries - 1) end, seen)

      _spent ->
        {:error, :timeout}
    end
  end

  # NOERROR with the truncation flag still set, which `:inet_res` returns as
  # an answer when the reply over TCP carries it too: records may be missing
  defp answer({:ok, message}, name, type, query_target, seen) do
    if truncated?(message),
      do: {:error, :truncated},
      else: records(message, name, type, query_target, seen)
  end

  # NXDOMAIN, which `nxdomain_reply: true` returns with the name server's
  # message: the name, or the end of its CNAME chain, does not exist
  defp answer({:error, {:nxdomain, _message}}, _name, _type, _query_target, _seen), do: {:ok, []}

  # Without a name server to ask, `:inet_res` answers a bare `:nxdomain`
  defp answer({:error, :nxdomain}, _name, _type, _query_target, _seen), do: {:error, :no_name_servers}

  # SERVFAIL, REFUSED, a format error, a code it does not know: the name
  # server's failure, with its message
  defp answer({:error, {reason, _message}}, _name, _type, _query_target, _seen), do: {:error, reason}

  # A timeout, an answer that cannot be decoded, a network error
  defp answer({:error, reason}, _name, _type, _query_target, _seen), do: {:error, reason}

  defp answer(other, _name, _type, _query_target, _seen), do: {:error, {:unexpected, other}}

  defp truncated?(message), do: :inet_dns.header(:inet_dns.msg(message, :header), :tc) == true

  # NOERROR: the records of the type, for the name or the end of its CNAME
  # chain; none at all is a name with no record of the type
  defp records(message, name, type, query_target, seen) do
    records =
      for record <- :inet_dns.msg(message, :anlist),
          :inet_dns.rr(record, :class) == :in,
          record_type = :inet_dns.rr(record, :type),
          record_type in [type, :cname],
          do: {domain(:inet_dns.rr(record, :domain)), record_type, :inet_dns.rr(record, :data)}

    case follow(records, name, type, name, seen) do
      {:target, target, seen} -> query_target.(target, seen)
      found -> found
    end
  end

  # The type's records of `name`, or of the name its CNAME points at. A target
  # the answer holds nothing for is asked about on its own; a chain that
  # comes back to a name it passed has no addresses.
  defp follow(records, name, type, queried, seen) do
    case for({^name, ^type, address} <- records, do: address) do
      [_ | _] = addresses -> {:ok, addresses}
      [] -> follow_cname(records, name, type, queried, seen)
    end
  end

  defp follow_cname(records, name, type, queried, seen) do
    case for({^name, :cname, target} <- records, do: domain(target)) do
      [] when name == queried -> {:ok, []}
      [] -> {:target, name, seen}
      [target] -> if target in seen, do: {:ok, []}, else: follow(records, target, type, queried, [target | seen])
      [_, _ | _] -> {:error, :several_cnames}
    end
  end

  defp domain(name), do: name |> to_string() |> String.trim_trailing(".") |> String.downcase()
end
