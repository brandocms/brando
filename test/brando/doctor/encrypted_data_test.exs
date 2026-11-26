defmodule Brando.Doctor.EncryptedDataTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Crypto.Marker
  alias Brando.Doctor.Checks.EncryptedData
  alias Brando.Doctor.Result
  alias Brando.Test.ForeignSecret

  defp marker!(readable?, host, attrs \\ []) do
    value =
      if readable?,
        do: Brando.Crypto.encrypt("brando", "brando.crypto_marker"),
        else: ForeignSecret.encrypt("brando", "brando.crypto_marker")

    Repo.insert!(struct(%Marker{id: 1, value: value, host: host}, attrs))
  end

  defp snapshot, do: {Repo.all(Marker), Repo.all(Brando.Webhooks.Webhook)}

  test "the marker this secret wrote is fine" do
    marker!(true, Marker.host())
    assert %Result{status: :ok} = EncryptedData.run(nil)
  end

  test "without a marker and nothing unreadable, fine until the next start writes it" do
    ForeignSecret.webhook!(nil, true)
    assert %Result{status: :ok} = EncryptedData.run(nil)
  end

  test "without a marker, values another secret wrote are an error that counts them" do
    ForeignSecret.two_factor!(Brando.Factory.insert(:random_user), false)
    ForeignSecret.route!(nil, :slack, false)

    assert %Result{status: :error, items: [_users, _routes], link: {"/admin/config/encrypted-data", _}} =
             EncryptedData.run(nil)

    assert EncryptedData.cause(Marker.state()) == :unknown
  end

  test "a foreign marker this host wrote: the secret changed here" do
    marker!(false, Marker.host())

    assert %Result{status: :error, fix: fix} = EncryptedData.run(nil)
    assert fix == EncryptedData.fix(:changed_here)
    assert EncryptedData.cause(Marker.state()) == :changed_here
  end

  test "a foreign marker from another host, before or after the start recorded the move" do
    marker!(false, "prod.example.com")
    assert EncryptedData.cause(Marker.state()) == {:moved, "prod.example.com"}
    assert %Result{status: :error, fix: fix} = EncryptedData.run(nil)
    assert fix =~ "prod.example.com"

    Repo.update_all(Marker, set: [host: Marker.host(), moved_from: "prod.example.com", moved_key: "foreign"])
    assert EncryptedData.cause(Marker.state()) == {:moved, "prod.example.com"}

    # A move whose secret was readable, then a secret changed here
    Repo.update_all(Marker, set: [moved_key: "ours"])
    assert EncryptedData.cause(Marker.state()) == :changed_here
  end

  test "before the migration, skipped" do
    Repo.query!("DROP TABLE public.crypto_marker")
    assert %Result{status: :skipped} = EncryptedData.run(nil)
  end

  test "reads only: a run changes nothing" do
    ForeignSecret.webhook!(nil, false)
    before = snapshot()
    EncryptedData.run(nil)
    assert snapshot() == before

    marker!(false, "prod.example.com")
    before = snapshot()
    EncryptedData.run(nil)
    assert snapshot() == before
  end

  test "is one of Brando's checks" do
    assert EncryptedData in Brando.Doctor.default_checks()
  end
end
