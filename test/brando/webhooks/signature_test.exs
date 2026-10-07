defmodule Brando.Webhooks.SignatureTest do
  use ExUnit.Case, async: true

  alias Brando.Webhooks.Signature

  @secret "whsec_test_secret"
  @body ~s({"event":"entry.published","entry":{"id":1}})

  test "HMAC-SHA256 over the timestamp, a full stop and the exact body" do
    expected = :crypto.mac(:hmac, :sha256, @secret, "1791456000." <> @body) |> Base.encode16(case: :lower)
    assert Signature.sign(@secret, 1_791_456_000, @body) == expected
    assert Signature.header(@secret, 1_791_456_000, @body) == "t=1791456000,v1=" <> expected
  end

  # What a receiver does, written out the way the guide shows it, without
  # Brando's code: parse the header, recompute over the raw body, compare in
  # constant time, and refuse old timestamps.
  defp receiver_accepts?(header, raw_body, secret, now) do
    parts = header |> String.split(",") |> Map.new(&List.to_tuple(String.split(&1, "=", parts: 2)))
    timestamp = String.to_integer(parts["t"])
    expected = :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{raw_body}") |> Base.encode16(case: :lower)
    abs(now - timestamp) <= 300 and Plug.Crypto.secure_compare(expected, parts["v1"])
  end

  test "a receiver verifies what Brando signs" do
    now = System.system_time(:second)
    header = Signature.header(@secret, now, @body)

    assert receiver_accepts?(header, @body, @secret, now)
    assert Signature.verify(header, @body, @secret) == :ok
  end

  test "a changed body, another secret or a replayed request fail" do
    now = System.system_time(:second)
    header = Signature.header(@secret, now, @body)

    refute receiver_accepts?(header, @body <> " ", @secret, now)
    refute receiver_accepts?(header, @body, "whsec_other", now)
    assert Signature.verify(header, String.replace(@body, "1", "2"), @secret) == {:error, :signature_mismatch}
    assert Signature.verify(header, @body, "whsec_other") == {:error, :signature_mismatch}

    # Six minutes later the same request is a replay
    refute receiver_accepts?(header, @body, @secret, now + 360)
    assert Signature.verify(header, @body, @secret, now: now + 360) == {:error, :timestamp_out_of_tolerance}
    assert Signature.verify(header, @body, @secret, now: now + 360, tolerance: 600) == :ok
  end

  test "the timestamp is covered: moving it breaks the signature" do
    now = System.system_time(:second)
    "t=" <> rest = Signature.header(@secret, now, @body)
    [_t, v1] = String.split(rest, ",")
    forged = "t=#{now + 1},#{v1}"
    assert Signature.verify(forged, @body, @secret, now: now) == {:error, :signature_mismatch}
  end

  test "malformed headers" do
    assert Signature.verify(nil, @body, @secret) == {:error, :invalid_header}
    assert Signature.verify("v1=abc", @body, @secret) == {:error, :invalid_header}
    assert Signature.verify("t=abc,v1=abc", @body, @secret) == {:error, :invalid_header}
    assert Signature.verify("t=1", @body, @secret) == {:error, :invalid_header}
  end
end
