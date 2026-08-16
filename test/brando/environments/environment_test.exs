defmodule Brando.Environments.EnvironmentTest do
  use ExUnit.Case, async: true

  alias Brando.Environments.Environment

  @valid_attrs %{
    site_id: 1,
    name: "Production",
    key: "production",
    live: true,
    domain: "WWW.Example.COM "
  }

  test "the registry schema is permanently public" do
    assert Environment.__schema__(:prefix) == "public"
  end

  test "accepts named environments and normalizes their domain" do
    assert changeset = Environment.changeset(@valid_attrs)
    assert changeset.valid?

    environment = Ecto.Changeset.apply_changes(changeset)
    assert environment.key == "production"
    assert environment.domain == "www.example.com"
  end

  test "rejects unsafe environment keys" do
    changeset = Environment.changeset(%{@valid_attrs | key: "spring_redesign"})

    refute changeset.valid?
    assert changeset.errors[:key]
  end

  test "treats a blank domain as unassigned" do
    changeset = Environment.changeset(%{@valid_attrs | domain: "  "})

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :domain) == nil
  end
end
