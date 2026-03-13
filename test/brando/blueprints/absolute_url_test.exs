defmodule Brando.Blueprint.AbsoluteURLTest do
  use ExUnit.Case, async: false
  alias Brando.Pages.Page

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
    test "returns :liquid for liquid template absolute urls" do
      assert Page.__absolute_url_type__() == :liquid
      assert Brando.MigrationTest.Project.__absolute_url_type__() == :liquid
    end

    test "returns :i18n for i18n tuple absolute urls" do
      assert Brando.BlueprintTest.Project.__absolute_url_type__() == :i18n
    end
  end

  describe "__absolute_url_template__/0" do
    test "returns the raw liquid template string" do
      assert is_binary(Page.__absolute_url_template__())
    end

    test "returns the args template list for i18n type" do
      assert Brando.BlueprintTest.Project.__absolute_url_template__() ==
               [[:slug], [:creator, :slug], [:properties, :name]]
    end
  end

  describe "__absolute_url_preloads__/0" do
    test "extracts relation preloads from liquid template" do
      assert Brando.MigrationTest.Project.__absolute_url_preloads__() == [:creator, :properties]
    end

    test "extracts relation preloads from i18n args" do
      assert Brando.BlueprintTest.Project.__absolute_url_preloads__() == [:creator, :properties]
    end

    test "returns empty list when no relation preloads needed" do
      assert Page.__absolute_url_preloads__() == []
    end
  end

  describe "__absolute_url__/1" do
    test "generates URL from liquid template" do
      assert Page.__absolute_url__(%Page{language: "no", uri: "om-oss"}) == "/no/om-oss"
      assert Page.__absolute_url__(%Page{language: "en", uri: "about"}) == "/en/about"
    end

    test "handles index pages by stripping uri" do
      assert Page.__absolute_url__(%Page{language: "no", uri: "index"}) == "/no/"
      assert Page.__absolute_url__(%Page{language: "en", uri: "index"}) == "/en/"
    end

    test "respects scope_default_language_routes config" do
      Application.put_env(:brando, :scope_default_language_routes, false)

      assert Page.__absolute_url__(%Page{language: "no", uri: "om-oss"}) == "/no/om-oss"
      assert Page.__absolute_url__(%Page{language: "en", uri: "about"}) == "/about"
      assert Page.__absolute_url__(%Page{language: "no", uri: "index"}) == "/no/"
      assert Page.__absolute_url__(%Page{language: "en", uri: "index"}) == "/"

      Application.put_env(:brando, :scope_default_language_routes, true)
    end

    test "generates URL from i18n route helper" do
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
