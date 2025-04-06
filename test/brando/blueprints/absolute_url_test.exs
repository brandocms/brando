defmodule Brando.Blueprint.AbsoluteURLTest do
  use ExUnit.Case
  alias Brando.Pages.Page

  test "__absolute_url_preloads__" do
    assert Brando.BlueprintTest.Project.__absolute_url_preloads__() == [:creator, :properties]
    assert Brando.MigrationTest.Project.__absolute_url_preloads__() == [:creator, :properties]
    assert Brando.Pages.Page.__absolute_url_preloads__() == []
  end

  test "__absolute_url__" do
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

    Application.put_env(:brando, :scope_default_language_routes, true)
  end
end
