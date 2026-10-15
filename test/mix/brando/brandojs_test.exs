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

  test "Yalc specs take the package from the admin's .yalc copy" do
    assert BrandoJS.yalc?("file:.yalc/@brandocms/brandojs")
    assert BrandoJS.yalc?("link:.yalc/@brandocms/brandojs")
    refute BrandoJS.yalc?("link:../../brando/assets")
    refute BrandoJS.yalc?("0.55.0")
    refute BrandoJS.yalc?(nil)
  end

  test "dependency reads dependencies, then devDependencies" do
    assert BrandoJS.dependency(%{"dependencies" => %{"@brandocms/brandojs" => "0.55.0"}}) == "0.55.0"
    assert BrandoJS.dependency(%{"devDependencies" => %{"@brandocms/brandojs" => "link:x"}}) == "link:x"
    assert BrandoJS.dependency(%{}) == nil
  end

  test "local_dependency finds a local spec in either section" do
    package = %{
      "dependencies" => %{"@brandocms/brandojs" => "0.54.0"},
      "devDependencies" => %{"@brandocms/brandojs" => "link:x"}
    }

    assert BrandoJS.local_dependency(package) == "link:x"
    assert BrandoJS.local_dependency(%{"dependencies" => %{"@brandocms/brandojs" => "0.54.0"}}) == nil
    assert BrandoJS.sections(package) == ["dependencies", "devDependencies"]
  end

  test "put_spec replaces only the BrandoJS value and keeps the rest of the text" do
    json =
      ~s({\n  "dependencies": {\n    "@brandocms/brandojs": "file:.yalc/@brandocms/brandojs",\n    "x": "1"\n  }\n}\n)

    assert BrandoJS.put_spec(json, "0.55.0") ==
             ~s({\n  "dependencies": {\n    "@brandocms/brandojs": "0.55.0",\n    "x": "1"\n  }\n}\n)
  end

  test "put_spec rewrites the entry in the section that has it, not an override naming the package" do
    json = ~s({
      "pnpm": {"overrides": {"@brandocms/brandojs": "link:../x"}},
      "devDependencies": {"@brandocms/brandojs": "file:.yalc/@brandocms/brandojs"}
    })

    package = json |> BrandoJS.put_spec("0.55.0") |> Jason.decode!()
    assert package["devDependencies"]["@brandocms/brandojs"] == "0.55.0"
    assert package["pnpm"]["overrides"]["@brandocms/brandojs"] == "link:../x"
    refute Map.has_key?(package, "dependencies")
  end

  test "put_spec adds BrandoJS to dependencies when package.json has none" do
    assert ~s({"name": "backend"}) |> BrandoJS.put_spec("0.55.0") |> Jason.decode!() ==
             %{"name" => "backend", "dependencies" => %{"@brandocms/brandojs" => "0.55.0"}}

    package = ~s({"dependencies": {"x": "1"}}) |> BrandoJS.put_spec("0.55.0") |> Jason.decode!()
    assert package["dependencies"] == %{"x" => "1", "@brandocms/brandojs" => "0.55.0"}
  end
end
