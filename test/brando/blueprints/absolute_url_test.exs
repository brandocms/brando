defmodule Brando.Blueprint.AbsoluteURLTest do
  use ExUnit.Case, async: false

  alias Brando.Pages.Page

  setup do
    scope_default_language_routes = Application.fetch_env!(:brando, :scope_default_language_routes)

    on_exit(fn ->
      Application.put_env(:brando, :scope_default_language_routes, scope_default_language_routes)
    end)
  end

  describe "__has_absolute_url__/0" do
    test "returns true for schemas with absolute_url defined" do
      assert Page.__has_absolute_url__() == true
      assert Brando.BlueprintTest.Project.__has_absolute_url__() == true
      assert Brando.MigrationTest.Project.__has_absolute_url__() == true
    end

    test "returns false for schemas without absolute_url" do
      assert Brando.Content.Var.__has_absolute_url__() == false
    end
  end

  describe "__absolute_url_type__/0" do
    test "returns :heex for all converted templates" do
      assert Page.__absolute_url_type__() == :heex
      assert Brando.MigrationTest.Project.__absolute_url_type__() == :heex
      assert Brando.BlueprintTest.Project.__absolute_url_type__() == :heex
    end
  end

  describe "__absolute_url_template__/0" do
    test "returns the raw HEEx template string for page" do
      assert is_binary(Page.__absolute_url_template__())
    end

    test "returns the raw HEEx template string for BlueprintTest.Project" do
      assert is_binary(Brando.BlueprintTest.Project.__absolute_url_template__())
    end
  end

  describe "__absolute_url_preloads__/0" do
    test "extracts relation preloads from HEEx template" do
      assert Brando.MigrationTest.Project.__absolute_url_preloads__() == [:creator, :properties]
    end

    test "extracts relation preloads from HEEx with route_i18n" do
      assert Brando.BlueprintTest.Project.__absolute_url_preloads__() == [:creator, :properties]
    end

    test "returns empty list when no relation preloads needed" do
      assert Page.__absolute_url_preloads__() == []
    end
  end

  defmodule OnlyByFunction do
    use Phoenix.Component
    import Brando.Blueprint.AbsoluteURL

    absolute_url ~H"/things/{@entry.slug}", only: &(&1.external_url in [nil, ""])
  end

  describe "absolute_url only:" do
    test "an entry outside the map has no URL on this site" do
      assert Page.__absolute_url__(%Page{language: "no", uri: "om-oss", has_url: true}) == "/no/om-oss"
      assert Page.__absolute_url__(%Page{language: "no", uri: "om-oss", has_url: false}) == nil
      assert Page.__has_url__(%Page{has_url: true})
      refute Page.__has_url__(%Page{has_url: false})
    end

    test "the map doubles as the list query filter" do
      assert Page.__url_filter__() == %{has_url: true}
    end

    test "without only: every entry has a URL; without absolute_url none does" do
      assert Brando.BlueprintTest.Project.__has_url__(%{})
      assert Brando.BlueprintTest.Project.__url_filter__() == nil
      refute Brando.Content.Var.__has_url__(%{})
    end

    test "a function answers per entry and gives no filter" do
      assert OnlyByFunction.__absolute_url__(%{slug: "a", external_url: nil}) == "/things/a"
      assert OnlyByFunction.__absolute_url__(%{slug: "a", external_url: "https://example.com"}) == nil
      assert OnlyByFunction.__url_filter__() == nil
    end

    test "only: is the one option" do
      assert_raise Brando.Exception.BlueprintError, ~r/only:/, fn ->
        Code.compile_string("""
        defmodule Brando.Blueprint.AbsoluteURLTest.BadOption do
          import Brando.Blueprint.AbsoluteURL
          absolute_url "/x", where: %{a: 1}
        end
        """)
      end
    end
  end

  describe "__absolute_url__/1" do
    test "generates URL from HEEx template with route_i18n for pages" do
      assert Page.__absolute_url__(%Page{language: "no", uri: "om-oss"}) == "/no/om-oss"
      assert Page.__absolute_url__(%Page{language: "en", uri: "about"}) == "/en/about"
    end

    test "handles index pages" do
      assert Page.__absolute_url__(%Page{language: "no", uri: "index"}) == "/no/"
      assert Page.__absolute_url__(%Page{language: "en", uri: "index"}) == "/en/"
    end

    test "respects scope_default_language_routes config" do
      Application.put_env(:brando, :scope_default_language_routes, false)

      assert Page.__absolute_url__(%Page{language: "no", uri: "om-oss"}) == "/no/om-oss"
      assert Page.__absolute_url__(%Page{language: "en", uri: "about"}) == "/about"
      assert Page.__absolute_url__(%Page{language: "no", uri: "index"}) == "/no/"
      assert Page.__absolute_url__(%Page{language: "en", uri: "index"}) == "/"
    end

    test "generates URL from HEEx route_i18n helper" do
      project = %Brando.BlueprintTest.Project{
        slug: "my-project",
        language: :en,
        creator: %{slug: "john-doe"},
        properties: %{name: "my-project"}
      }

      assert Brando.BlueprintTest.Project.__absolute_url__(project) ==
               "/en/project/my-project/john-doe/my-project"
    end
  end
end
