defmodule Brando.Authorization.CatalogTest do
  use ExUnit.Case, async: true
  alias Brando.Authorization.Catalog

  test "registered capabilities have unique keys" do
    assert [_ | _] = Catalog.all()
  end

  # As guides/authorization.md describes the presets
  test "Editor publishes and schedules entries; builds and deployments are Admin's" do
    page = Catalog.get(:publish, Brando.Pages.Page).resource
    editor = Catalog.preset_permissions(:editor, :site)
    admin = Catalog.preset_permissions(:admin, :site)

    assert "#{page}.publish" in editor
    assert "#{page}.schedule" in editor
    refute Enum.any?(editor, &String.starts_with?(&1, "brando.publishing."))
    assert "brando.publishing.deploy" in admin
    assert "brando.publishing.build" in admin
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
