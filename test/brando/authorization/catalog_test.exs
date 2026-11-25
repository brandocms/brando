defmodule Brando.Authorization.CatalogTest do
  use ExUnit.Case, async: true
  alias Brando.Authorization.Catalog

  test "registered capabilities have unique keys" do
    assert [_ | _] = Catalog.all()
  end

  # As guides/authorization.md describes the presets
  test "Editor publishes entries and a static site's builds; configuring publishing is Admin's" do
    page = Catalog.get(:publish, Brando.Pages.Page).resource
    editor = Catalog.preset_permissions(:editor, :site)
    admin = Catalog.preset_permissions(:admin, :site)

    assert "#{page}.publish" in editor
    assert "#{page}.schedule" in editor

    assert editor |> Enum.filter(&String.starts_with?(&1, "brando.publishing.")) |> Enum.sort() ==
             ["brando.publishing.build", "brando.publishing.deploy", "brando.publishing.read"]

    for action <- ~w(read build deploy schedule configure), do: assert("brando.publishing.#{action}" in admin)
  end

  test "configuring publishing is an action of its own, which no other implies" do
    configure = Catalog.get(:configure, :publishing)

    assert configure.key == "brando.publishing.configure"
    assert configure.implied_by == []
    assert configure.delegable
  end

  test "duplicate capability keys report the resources instead of dropping one" do
    permissions = [
      %{key: "example.pages.read", subject: FirstResource},
      %{key: "example.pages.read", subject: SecondResource}
    ]

    assert_raise ArgumentError, ~r/duplicate authorization key.*example.pages.read/, fn ->
      Catalog.validate!(permissions)
    end
  end

  test "authorization metadata rejects malformed sections and policies at compilation" do
    for {options, error} <- [
          {[section: 12], ~r/section must be/},
          {[section: "  "], ~r/section must be/},
          {[policy: "Policy"], ~r/policy must be/},
          {[policy: nil], ~r/policy must be/}
        ] do
      assert_raise ArgumentError, error, fn ->
        Code.compile_quoted(
          quote do
            defmodule Brando.InvalidAuthorizationMetadata do
              require Brando.Blueprint
              Brando.Blueprint.authorization(unquote(options))
            end
          end
        )
      end
    end
  end
end
