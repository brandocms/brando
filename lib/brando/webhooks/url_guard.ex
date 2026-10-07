defmodule Brando.Webhooks.URLGuard do
  @moduledoc """
  Decides whether a webhook may call a URL, and which address to connect to.

  A webhook URL must be `https` (or `http` with the localhost override
  below), have a host and no credentials, and every address its host
  resolves to must be public. Refused:

    * IPv4: `0.0.0.0/8` (including `0.0.0.0`), `10.0.0.0/8`, `100.64.0.0/10`
      (CGNAT), `127.0.0.0/8` (loopback), `169.254.0.0/16` (link-local),
      `172.16.0.0/12`, `192.0.0.0/24`, `192.0.2.0/24`, `192.168.0.0/16`,
      `198.18.0.0/15`, `198.51.100.0/24`, `203.0.113.0/24`, `224.0.0.0/4`
      (multicast) and `240.0.0.0/4` (reserved, including broadcast);
    * IPv6: `::` and `::1`, `fe80::/10` (link-local), `fec0::/10`,
      `fc00::/7` (unique local), `ff00::/8` (multicast), `100::/64`,
      `2001:db8::/32`, and IPv4 addresses inside IPv6 (`::ffff:0:0/96`,
      `::/96`, `64:ff9b::/96`, `2002::/16`) by the IPv4 rules.

  The check runs when a webhook is saved and again before every delivery,
  and the delivery connects to the address that was checked, with the host
  name kept for TLS (SNI and certificate) and the `Host` header. A host that
  resolves to a public address when saved and a private one later (DNS
  rebinding) is refused at delivery.

  ## Localhost in development

      config :brando, Brando.Webhooks, allow_localhost: true

  allows `http` and loopback addresses (`127.0.0.0/8`, `::1`), for a
  receiver on the developer's own machine. Other private ranges stay
  refused. Never set it in production.
  """

  import Bitwise

  @type target :: %{
          scheme: :http | :https,
          host: String.t(),
          port: :inet.port_number(),
          path: String.t(),
          address: :inet.ip_address()
        }

  @doc "Whether the development override for localhost is on."
  @spec allow_localhost?() :: boolean()
  def allow_localhost?, do: Keyword.get(Brando.config(Brando.Webhooks) || [], :allow_localhost, false) == true

  @doc """
  Checks `url` without resolving its host: scheme, host and credentials.
  Returns the parsed URI.
  """
  @spec validate(String.t()) :: {:ok, URI.t()} | {:error, atom()}
  def validate(url) when is_binary(url) do
    with {:ok, uri} <- parse(url),
         :ok <- check_scheme(uri),
         :ok <- check_userinfo(uri) do
      {:ok, uri}
    end
  end

  def validate(_), do: {:error, :invalid_url}

  @doc """
  Checks `url` and resolves its host. Returns where to connect: the first
  resolved address, when every address the host has is allowed.

  Options: `:resolver`, a function from a host name (charlist) to
  `{:ok, [address]}` or `{:error, reason}`, used in tests.
  """
  @spec resolve(String.t(), keyword()) :: {:ok, target()} | {:error, atom()}
  def resolve(url, opts \\ []) do
    with {:ok, uri} <- validate(url),
         {:ok, addresses} <- addresses(uri.host, opts),
         :ok <- check_addresses(addresses) do
      {:ok,
       %{
         scheme: String.to_existing_atom(uri.scheme),
         host: uri.host,
         port: uri.port,
         path: path(uri),
         address: hd(addresses)
       }}
    end
  end

  defp parse(url) do
    case URI.new(String.trim(url)) do
      {:ok, %URI{scheme: scheme, host: host} = uri} when is_binary(scheme) and is_binary(host) and host != "" ->
        {:ok, %{uri | scheme: String.downcase(scheme), host: host |> String.trim_trailing(".") |> String.downcase()}}

      _ ->
        {:error, :invalid_url}
    end
  end

  defp check_scheme(%URI{scheme: "https"}), do: :ok

  defp check_scheme(%URI{scheme: "http"}),
    do: if(allow_localhost?(), do: :ok, else: {:error, :https_required})

  defp check_scheme(_uri), do: {:error, :scheme_not_allowed}

  defp check_userinfo(%URI{userinfo: nil}), do: :ok
  defp check_userinfo(_uri), do: {:error, :credentials_in_url}

  defp path(%URI{path: path, query: query}) do
    path = if path in [nil, ""], do: "/", else: path
    if query in [nil, ""], do: path, else: path <> "?" <> query
  end

  defp addresses(host, opts) do
    host = String.trim_leading(host, "[") |> String.trim_trailing("]")

    case :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, address} -> {:ok, [address]}
      {:error, _} -> lookup(String.to_charlist(host), opts)
    end
  end

  defp lookup(host, opts) do
    resolver = Keyword.get(opts, :resolver) || configured_resolver() || (&system_resolver/1)

    case resolver.(host) do
      {:ok, [_ | _] = addresses} -> {:ok, addresses}
      _ -> {:error, :unresolvable}
    end
  end

  defp configured_resolver do
    case Keyword.get(Brando.config(Brando.Webhooks) || [], :resolver) do
      {module, function} -> &apply(module, function, [&1])
      fun when is_function(fun, 1) -> fun
      _ -> nil
    end
  end

  @doc false
  # Every IPv4 and IPv6 address of `host`.
  def system_resolver(host) do
    v4 =
      case :inet.getaddrs(host, :inet),
        do: (
          {:ok, list} -> list
          _ -> []
        )

    v6 =
      case :inet.getaddrs(host, :inet6),
        do: (
          {:ok, list} -> list
          _ -> []
        )

    case v4 ++ v6 do
      [] -> {:error, :nxdomain}
      addresses -> {:ok, Enum.uniq(addresses)}
    end
  end

  defp check_addresses(addresses) do
    if Enum.any?(addresses, &(blocked?(&1) and not local_override?(&1))),
      do: {:error, :private_address},
      else: :ok
  end

  defp local_override?(address), do: allow_localhost?() and loopback?(address)

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false

  # {network, prefix length}
  @blocked_v4 [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 0, 2, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  @blocked_v6 [
    # unspecified and loopback
    {{0, 0, 0, 0, 0, 0, 0, 0}, 127},
    # discard-only
    {{0x0100, 0, 0, 0, 0, 0, 0, 0}, 64},
    # documentation
    {{0x2001, 0x0DB8, 0, 0, 0, 0, 0, 0}, 32},
    # unique local
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    # link-local and the old site-local
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFEC0, 0, 0, 0, 0, 0, 0, 0}, 10},
    # multicast
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  @doc "Whether webhooks must not connect to `address`, an IPv4 or IPv6 tuple."
  @spec blocked?(:inet.ip_address()) :: boolean()
  def blocked?({_, _, _, _} = address), do: Enum.any?(@blocked_v4, &in_network?(address, &1, 8))

  def blocked?({_, _, _, _, _, _, _, _} = address) do
    case embedded_v4(address) do
      nil -> Enum.any?(@blocked_v6, &in_network?(address, &1, 16))
      v4 -> blocked?(v4)
    end
  end

  def blocked?(_), do: true

  # IPv4 inside IPv6: mapped (::ffff:a.b.c.d), compatible (::a.b.c.d), NAT64
  # (64:ff9b::a.b.c.d) and 6to4 (2002:aabb:ccdd::)
  defp embedded_v4({0, 0, 0, 0, 0, 0xFFFF, g, h}), do: v4(g, h)
  defp embedded_v4({0, 0, 0, 0, 0, 0, g, h}) when g != 0 or h > 1, do: v4(g, h)
  defp embedded_v4({0x64, 0xFF9B, 0, 0, 0, 0, g, h}), do: v4(g, h)
  defp embedded_v4({0x2002, g, h, _, _, _, _, _}), do: v4(g, h)
  defp embedded_v4(_address), do: nil

  defp in_network?(address, {network, length}, bits) do
    size = tuple_size(address) * bits
    shift = size - length
    to_integer(address, bits) >>> shift == to_integer(network, bits) >>> shift
  end

  defp to_integer(address, bits) do
    address |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> (acc <<< bits) + part end)
  end

  defp v4(g, h), do: {g >>> 8, g &&& 0xFF, h >>> 8, h &&& 0xFF}
end
