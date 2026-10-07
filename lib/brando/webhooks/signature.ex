defmodule Brando.Webhooks.Signature do
  @moduledoc ~S"""
  The `Brando-Signature` header on every webhook delivery:

      Brando-Signature: t=1791456000,v1=5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd

  `t` is when the request was signed, in Unix seconds. `v1` is the
  lowercase hex HMAC-SHA256 of `t`, a full stop, and the exact bytes of the
  request body, keyed with the webhook's secret (the whole `whsec_…` string,
  as UTF-8 bytes):

      v1 = hex(hmac_sha256(secret, "#{t}.#{body}"))

  A receiver checks it before trusting the body: recompute `v1` from the raw
  body it received (before any JSON parsing), compare in constant time, and
  reject a `t` too far from its own clock, so a captured request cannot be
  replayed later. `verify/4` does this; see the Webhooks guide for the same
  check in other languages.
  """

  @tolerance 300

  @doc "The signature (hex) of `body` sent at `timestamp` (Unix seconds)."
  @spec sign(String.t(), integer(), iodata()) :: String.t()
  def sign(secret, timestamp, body) when is_binary(secret) and is_integer(timestamp) do
    :hmac
    |> :crypto.mac(:sha256, secret, [Integer.to_string(timestamp), ".", body])
    |> Base.encode16(case: :lower)
  end

  @doc "The `Brando-Signature` header value."
  @spec header(String.t(), integer(), iodata()) :: String.t()
  def header(secret, timestamp, body), do: "t=#{timestamp},v1=#{sign(secret, timestamp, body)}"

  @doc """
  Verifies a `Brando-Signature` header against the raw `body`, as a receiver
  would. Options: `:tolerance` in seconds (default 300) and `:now` (Unix
  seconds).
  """
  @spec verify(String.t() | nil, binary(), String.t(), keyword()) ::
          :ok | {:error, :invalid_header | :timestamp_out_of_tolerance | :signature_mismatch}
  def verify(header, body, secret, opts \\ [])

  def verify(header, body, secret, opts) when is_binary(header) do
    tolerance = Keyword.get(opts, :tolerance, @tolerance)
    now = Keyword.get_lazy(opts, :now, fn -> System.system_time(:second) end)

    with {:ok, timestamp, signatures} <- parse(header) do
      expected = sign(secret, timestamp, body)

      cond do
        abs(now - timestamp) > tolerance -> {:error, :timestamp_out_of_tolerance}
        Enum.any?(signatures, &Plug.Crypto.secure_compare(&1, expected)) -> :ok
        true -> {:error, :signature_mismatch}
      end
    end
  end

  def verify(_header, _body, _secret, _opts), do: {:error, :invalid_header}

  defp parse(header) do
    pairs =
      header
      |> String.split(",")
      |> Enum.map(&String.split(String.trim(&1), "=", parts: 2))

    timestamps = for [key, value] <- pairs, key == "t", do: value
    signatures = for [key, value] <- pairs, key == "v1", do: value

    with [timestamp] <- timestamps,
         {timestamp, ""} <- Integer.parse(timestamp),
         [_ | _] <- signatures do
      {:ok, timestamp, signatures}
    else
      _ -> {:error, :invalid_header}
    end
  end
end
