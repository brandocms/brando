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

  test "a domain is a bare host" do
    for host <- ["www.example.com", "a-b.example.com", "xn--bcher-kva.example", "intranet", "1.example.com"] do
      assert Environment.changeset(%{@valid_attrs | domain: host}).valid?, host
    end

    for host <- [
          "https://www.example.com",
          "//www.example.com",
          "www.example.com/",
          "www.example.com/path",
          "www.example.com:4000",
          "www.example.com.",
          "www.example.com..",
          ".example.com",
          "www..example.com",
          "www example.com",
          "www\n.example.com",
          "user@www.example.com",
          "-www.example.com",
          "www-.example.com",
          "*.example.com",
          "b\u00FCcher.example",
          "[::1]",
          String.duplicate("a", 64) <> ".example.com",
          String.duplicate("a.", 127) <> "aa"
        ] do
      changeset = Environment.changeset(%{@valid_attrs | domain: host})
      refute changeset.valid?, inspect(host)
      assert changeset.errors[:domain], inspect(host)
    end
  end

  test "a domain is checked only when it changes, so a stored spelling keeps working" do
    for stored <- ["www.example.com.", "https://www.example.com", "WWW.Example.COM"] do
      environment = %Environment{site_id: 1, name: "Production", key: "production", domain: stored}

      assert Environment.changeset(environment, %{live: true}).valid?
      assert Environment.changeset(environment, %{domain: stored}).valid?
    end
  end
end
