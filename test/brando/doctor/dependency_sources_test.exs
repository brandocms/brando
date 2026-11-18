defmodule Brando.Doctor.DependencySourcesTest do
  use ExUnit.Case, async: true

  alias Brando.Doctor.Checks.DependencySources
  alias Brando.Doctor.Context
  alias Brando.Doctor.Result

  @git %{
    type: :git,
    url: "https://github.com/brandocms/brando.git",
    commit: "12c2289e98fa",
    branch: "main",
    tag: nil,
    ref: nil
  }
  @path %{type: :path, path: "../brando"}

  @tag :tmp_dir
  test "lists the @brandocms packages each asset project takes from a path or a Yalc copy", %{tmp_dir: root} do
    write_package(root, "assets/backend", %{
      "dependencies" => %{"@brandocms/brandojs" => "link:../../brando/assets", "vue" => "file:../vue"},
      "devDependencies" => %{"@brandocms/europacss-cli" => "0.55.0"}
    })

    write_package(root, "assets/frontend", %{"dependencies" => %{"@brandocms/jupiter" => "file:.yalc/@brandocms/jupiter"}})

    write_package(root, "assets/sites/acme", %{"devDependencies" => %{"@brandocms/jupiter" => "portal:/home/me/jupiter"}})

    assert DependencySources.local_packages(root) == [
             %{dir: "assets/backend", name: "@brandocms/brandojs", spec: "link:../../brando/assets", kind: :path},
             %{dir: "assets/frontend", name: "@brandocms/jupiter", spec: "file:.yalc/@brandocms/jupiter", kind: :yalc},
             %{dir: "assets/sites/acme", name: "@brandocms/jupiter", spec: "portal:/home/me/jupiter", kind: :path}
           ]
  end

  @tag :tmp_dir
  test "an asset project without a package.json, or with an unreadable one, lists nothing", %{tmp_dir: root} do
    File.mkdir_p!(Path.join(root, "assets/backend"))
    File.write!(Path.join(root, "assets/backend/package.json"), "{not json")
    assert DependencySources.local_packages(root) == []
  end

  test "Brando from git or Hex with npm packages is fine" do
    assert %Result{status: :ok} = DependencySources.evaluate(@git, [], prod?: false, dev?: false)

    assert %Result{status: :ok} =
             DependencySources.evaluate(%{type: :hex, version: "0.55.0"}, [], prod?: true, dev?: false)

    assert %Result{status: :ok} = DependencySources.evaluate(%{type: :checkout}, [], prod?: false, dev?: true)
  end

  test "Brando as a path dependency warns, and is an error in production" do
    assert %Result{status: :warning, summary: summary, fix: fix, items: items} =
             DependencySources.evaluate(@path, [], prod?: false, dev?: true)

    assert summary =~ "brando"
    assert Enum.any?(items, &(&1 =~ "../brando"))
    assert fix =~ "mix.exs"

    assert %Result{status: :error} = DependencySources.evaluate(@path, [], prod?: true, dev?: true)
  end

  test "an @brandocms package from a path outside the project warns, and is an error in production" do
    package = %{dir: "assets/backend", name: "@brandocms/brandojs", spec: "link:../../brando/assets", kind: :path}

    assert %Result{status: :warning, items: [item]} =
             DependencySources.evaluate(@git, [package], prod?: false, dev?: true)

    assert item =~ "assets/backend"
    assert item =~ "link:../../brando/assets"

    assert %Result{status: :error} = DependencySources.evaluate(@git, [package], prod?: true, dev?: true)
  end

  test "a Yalc copy warns only when Brando has an npm release to switch to, and is never an error" do
    package = %{dir: "assets/backend", name: "@brandocms/brandojs", spec: "file:.yalc/@brandocms/brandojs", kind: :yalc}

    # A -dev Brando has no npm release: the installer sets the admin up with a Yalc copy
    assert %Result{status: :ok, items: [item]} = DependencySources.evaluate(@git, [package], prod?: true, dev?: true)
    assert item =~ ".yalc"

    assert %Result{status: :warning, fix: fix} = DependencySources.evaluate(@git, [package], prod?: false, dev?: false)
    assert fix =~ "mix brando.assets.setup --npm"
    assert %Result{status: :warning} = DependencySources.evaluate(@git, [package], prod?: true, dev?: false)
  end

  test "a path source and a Yalc copy together are an error in production" do
    yalc = %{dir: "assets/frontend", name: "@brandocms/jupiter", spec: "file:.yalc/@brandocms/jupiter", kind: :yalc}
    assert %Result{status: :error, items: items} = DependencySources.evaluate(@path, [yalc], prod?: true, dev?: false)
    assert length(items) == 2
  end

  @tag :tmp_dir
  test "run/1 reads the project's asset projects, and skips them without the source", %{tmp_dir: root} do
    write_package(root, "assets/backend", %{"dependencies" => %{"@brandocms/brandojs" => "link:../../brando/assets"}})

    # Brando's own tests run from its checkout
    assert %Result{status: :warning} = DependencySources.run(Context.new(root: root, source?: true, locale: "en"))
    assert %Result{status: :ok} = DependencySources.run(Context.new(root: root, source?: false, locale: "en"))
  end

  test "is one of Brando's checks" do
    assert DependencySources in Brando.Doctor.default_checks()
  end

  defp write_package(root, dir, json) do
    File.mkdir_p!(Path.join(root, dir))
    File.write!(Path.join([root, dir, "package.json"]), Jason.encode!(json))
  end
end
