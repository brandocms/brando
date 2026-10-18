defmodule Brando.EuropaCSSTest do
  use ExUnit.Case, async: true

  alias Brando.EuropaCSS

  test "the pins are the backend template's, exact npm versions" do
    template =
      "priv/templates/brando.install/assets/backend/package.json"
      |> File.read!()
      |> Jason.decode!()

    pins = EuropaCSS.pins()
    assert Map.keys(pins) == ~w(@brandocms/europacss-cli @brandocms/vite-plugin-europacss)

    for {name, version} <- pins do
      assert template["devDependencies"][name] == version
      assert version =~ ~r/^\d+\.\d+\.\d+(-[\w.]+)?$/
    end
  end

  test "the frontend template pins the same versions as the backend template" do
    frontend =
      "priv/templates/brando.install/assets/frontend/package.json"
      |> File.read!()
      |> Jason.decode!()

    assert Map.take(frontend["devDependencies"], Map.keys(EuropaCSS.pins())) == EuropaCSS.pins()
    assert EuropaCSS.package_problems(frontend) == []
  end

  test "the E2E backend builds with the pinned packages" do
    package = "e2e/assets/backend/package.json" |> File.read!() |> Jason.decode!()
    assert EuropaCSS.package_problems(package) == []
  end

  test "a backend from before the native compiler lists the legacy plugin and both packages" do
    package = %{"devDependencies" => %{"@brandocms/europacss" => "^0.13.1", "autoprefixer" => "^10.4.0"}}

    assert EuropaCSS.package_problems(package) == [
             {:legacy, "@brandocms/europacss", "^0.13.1"},
             {:missing, "@brandocms/vite-plugin-europacss"},
             {:missing, "@brandocms/europacss-cli"}
           ]
  end

  test "the plugin's earlier name is legacy as well" do
    package = %{"devDependencies" => %{"@univers-agency/europacss" => "^0.2.3"}}
    assert [{:legacy, "@univers-agency/europacss", "^0.2.3"} | _] = EuropaCSS.package_problems(package)
  end

  test "Yalc copies, paths and other versions" do
    package = %{
      "dependencies" => %{"@brandocms/europacss-cli" => "^0.1.0"},
      "devDependencies" => %{"@brandocms/vite-plugin-europacss" => "link:../../europacss/packages/vite"}
    }

    assert EuropaCSS.package_problems(package) == [
             {:local, "@brandocms/vite-plugin-europacss", "link:../../europacss/packages/vite"},
             {:version, "@brandocms/europacss-cli", "^0.1.0"}
           ]
  end
end
