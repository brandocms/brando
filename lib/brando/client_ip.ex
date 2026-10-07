defmodule Brando.ClientIP do
  @moduledoc """
  The address a request really came from, behind a reverse proxy.

  Behind Traefik, nginx or a load balancer, every request arrives from the
  proxy, so `conn.remote_ip` is the proxy's address and limits per IP address
  (`Brando.Users.Throttle`) would count every visitor together. The proxy
  says who the visitor was in `X-Forwarded-For`; anyone can send that header
  too, so it is only believed when the request comes from a trusted proxy:

      config :brando, :trusted_proxies, ["127.0.0.1/32", "::1/128", "10.0.0.0/8"]

  Each entry is an address or a CIDR range, IPv4 or IPv6. The default trusts
  only the loopback addresses (`127.0.0.0/8` and `::1`), which is what a
  proxy on the same server — Florist's Traefik or nginx — connects from. Set
  `[]` to never believe the header.

  The client is the right-most address in `X-Forwarded-For` that is not a
  trusted proxy: each trusted proxy appends the address it got the request
  from, so everything left of the first untrusted address could have been
  made up by the client.
  """

  import Bitwise

  @default_trusted ["127.0.0.0/8", "::1/128"]

  @type address :: :inet.ip_address()

  @doc "The client's address for `conn`."
  @spec from_conn(Plug.Conn.t()) :: address() | nil
  def from_conn(%Plug.Conn{} = conn) do
    resolve(conn.remote_ip, Plug.Conn.get_req_header(conn, "x-forwarded-for"))
  end

  @doc """
  The client's address for a LiveView socket, from its connect info: its
  `:peer_data`, and its `:x_headers` (`X-Forwarded-For`). The endpoint's
  socket must give both:

      socket "/live", Phoenix.LiveView.Socket,
        websocket: [connect_info: [:peer_data, :x_headers, :user_agent, session: @session_options]]
  """
  @spec from_connect_info(map()) :: address() | nil
  def from_connect_info(info) when is_map(info) do
    forwarded = for {"x-forwarded-for", value} <- info[:x_headers] || [], do: value
    resolve(get_in(info, [:peer_data, :address]), forwarded)
  end

  @doc """
  The client's address, given the address the request came from (`peer`) and
  the values of its `X-Forwarded-For` headers.
  """
  @spec resolve(address() | nil, [String.t()]) :: address() | nil
  def resolve(peer, forwarded) do
    peer = normalize(peer)

    if peer && trusted?(peer) do
      forwarded
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&parse/1)
      |> Enum.reverse()
      |> first_untrusted(peer)
    else
      peer
    end
  end

  # Right to left: the first address that is not a trusted proxy. An entry
  # that is not an address stops the walk at the last trusted hop.
  defp first_untrusted([], last), do: last
  defp first_untrusted([nil | _], last), do: last

  defp first_untrusted([address | rest], _last) do
    if trusted?(address), do: first_untrusted(rest, address), else: address
  end

  defp parse(value) do
    value = value |> String.trim() |> String.trim_leading("[") |> String.replace(~r/\](:\d+)?$/, "")

    case :inet.parse_strict_address(String.to_charlist(value)) do
      {:ok, address} -> normalize(address)
      {:error, _} -> nil
    end
  end

  # An IPv4 address carried in IPv6 (::ffff:a.b.c.d) is the IPv4 address
  defp normalize({0, 0, 0, 0, 0, 0xFFFF, high, low}), do: {high >>> 8, high &&& 255, low >>> 8, low &&& 255}
  defp normalize(address), do: address

  @doc "Whether `address` is one of the trusted proxies."
  @spec trusted?(address()) :: boolean()
  def trusted?(address), do: Enum.any?(trusted_ranges(), &in_range?(address, &1))

  defp trusted_ranges do
    (Brando.config(:trusted_proxies) || @default_trusted)
    |> Enum.flat_map(fn entry ->
      case parse_range(entry) do
        {:ok, range} -> [range]
        :error -> []
      end
    end)
  end

  @doc ~S'Parses `"10.0.0.0/8"` or `"10.1.2.3"` into `{address, prefix_length}`.'
  @spec parse_range(String.t()) :: {:ok, {address(), non_neg_integer()}} | :error
  def parse_range(entry) when is_binary(entry) do
    {address, prefix} =
      case String.split(entry, "/", parts: 2) do
        [address, prefix] -> {address, Integer.parse(prefix)}
        [address] -> {address, nil}
      end

    with {:ok, address} <- :inet.parse_strict_address(String.to_charlist(String.trim(address))),
         bits = bit_size(to_bits(address)),
         {:ok, prefix} <- prefix_length(prefix, bits) do
      {:ok, {address, prefix}}
    else
      _ -> :error
    end
  end

  def parse_range(_), do: :error

  defp prefix_length(nil, bits), do: {:ok, bits}
  defp prefix_length({prefix, ""}, bits) when prefix >= 0 and prefix <= bits, do: {:ok, prefix}
  defp prefix_length(_, _bits), do: :error

  defp in_range?(address, {network, prefix}) do
    address = to_bits(address)
    network = to_bits(network)
    shift = bit_size(address) - prefix

    bit_size(address) == bit_size(network) and
      :binary.decode_unsigned(address) >>> shift == :binary.decode_unsigned(network) >>> shift
  end

  defp to_bits({a, b, c, d}), do: <<a::8, b::8, c::8, d::8>>

  defp to_bits({a, b, c, d, e, f, g, h}),
    do: <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>
end
