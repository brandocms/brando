defmodule Mix.Brando.BrandoJSTest do
  use ExUnit.Case, async: true

  alias Mix.Brando.BrandoJS

  test "a release pairs with the npm release of its version, a -dev version with a Yalc copy" do
    assert BrandoJS.spec("0.55.0") == "0.55.0"
    assert BrandoJS.spec("0.55.0-beta.0") == "0.55.0-beta.0"
    assert BrandoJS.spec("0.55.0-dev") == "file:.yalc/@brandocms/brandojs"
    assert BrandoJS.spec("0.56.0-dev.1") == "file:.yalc/@brandocms/brandojs"
  end

  test "development versions" do
    assert BrandoJS.development?("0.55.0-dev")
    refute BrandoJS.development?("0.55.0-beta.0")
    refute BrandoJS.development?("0.55.0")
    refute BrandoJS.development?("not a version")
  end

  test "local sources are file: and link: specs" do
    assert BrandoJS.local?("file:.yalc/@brandocms/brandojs")
    assert BrandoJS.local?("link:../../brando/assets")
    refute BrandoJS.local?("0.55.0")
    refute BrandoJS.local?(nil)
  end

  test "dependency reads dependencies, then devDependencies" do
    assert BrandoJS.dependency(%{"dependencies" => %{"@brandocms/brandojs" => "0.55.0"}}) == "0.55.0"
    assert BrandoJS.dependency(%{"devDependencies" => %{"@brandocms/brandojs" => "link:x"}}) == "link:x"
    assert BrandoJS.dependency(%{}) == nil
  end

  test "put_spec replaces only the BrandoJS value and keeps the rest of the text" do
    json =
      ~s({\n  "dependencies": {\n    "@brandocms/brandojs": "file:.yalc/@brandocms/brandojs",\n    "x": "1"\n  }\n}\n)

    assert BrandoJS.put_spec(json, "0.55.0") ==
             ~s({\n  "dependencies": {\n    "@brandocms/brandojs": "0.55.0",\n    "x": "1"\n  }\n}\n)
  end
end
