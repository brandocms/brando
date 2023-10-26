defmodule Brando.Blueprint.AbsoluteURLTest do
  use ExUnit.Case
  alias Brando.Pages.Page

  test "extract_preloads_from_absolute_url" do
    assert Brando.Blueprint.AbsoluteURL.extract_preloads_from_absolute_url(
             Brando.BlueprintTest.Project
           ) == [:creator, :properties]

    assert Brando.Blueprint.AbsoluteURL.extract_preloads_from_absolute_url(
             Brando.MigrationTest.Project
           ) == [:creator, :properties]

    assert Brando.Blueprint.AbsoluteURL.extract_preloads_from_absolute_url(Brando.Pages.Page) ==
             []

    # test absolute url for index
    assert Page.__absolute_url__(%Page{language: "no", uri: "om-oss"}) == "/no/om-oss"
    assert Page.__absolute_url__(%Page{language: "en", uri: "about"}) == "/en/about"
    assert Page.__absolute_url__(%Page{language: "no", uri: "index"}) == "/no/"
    assert Page.__absolute_url__(%Page{language: "en", uri: "index"}) == "/en/"

    Application.put_env(:brando, :scope_default_language_routes, false)

    assert Page.__absolute_url__(%Page{language: "no", uri: "om-oss"}) == "/no/om-oss"
    assert Page.__absolute_url__(%Page{language: "en", uri: "about"}) == "/about"
    assert Page.__absolute_url__(%Page{language: "no", uri: "index"}) == "/no/"
    assert Page.__absolute_url__(%Page{language: "en", uri: "index"}) == "/"
  end
end
