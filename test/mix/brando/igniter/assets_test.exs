defmodule Mix.Brando.Igniter.AssetsTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Install.Templates
  alias Mix.Tasks.Brando.Assets.Copy

  test "binary copies are scheduled, preserve bytes on disk, and never replace a changed target" do
    igniter = IgniterCase.phoenix_project() |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Backend, [])
    assert igniter.issues == []

    {"brando.assets.copy", [target, digest]} =
      Enum.find(igniter.tasks, fn {_, [target, _]} -> String.ends_with?(target, "Mono.woff2") end)

    refute Rewrite.has_source?(igniter.rewrite, target)
    refute Map.has_key?(igniter.assigns.test_files, target)

    directory = Path.join(System.tmp_dir!(), "brando-binary-assets-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)

    try do
      File.cd!(directory, fn ->
        # Inspecting/cancelling the plan did not copy anything. Only acceptance
        # runs this task; the digest and target are checked again at that boundary.
        refute File.exists?(target)
        Copy.run([target, digest])
        assert File.read!(target) == Templates.contents(:copy, target)
        Copy.run([target, digest])
        assert File.read!(target) == Templates.contents(:copy, target)
        File.write!(target, "custom font")
        assert_raise Mix.Error, ~r/refusing to overwrite/, fn -> Copy.run([target, digest]) end
        assert File.read!(target) == "custom font"
        assert Path.wildcard(target <> ".brando-*") == []
      end)
    after
      File.rm_rf!(directory)
    end
  end

  test "the copier rejects an unknown path or stale source digest" do
    assert_raise Mix.Error, ~r/Unknown Brando binary asset/, fn -> Copy.run(["../outside.woff2", "unused"]) end

    assert_raise Mix.Error, ~r/changed since planning/, fn ->
      Copy.run(["assets/backend/public/fonts/Mono.woff2", "stale"])
    end
  end

  test "asset generators preserve custom package scripts and Yalc dependency selections" do
    package =
      ~s({"scripts":{"dev":"vite --host"},"dependencies":{"@brandocms/brandojs":"link:../../../assets","custom-library":"^1.0"}})

    igniter = IgniterCase.phoenix_project(files: %{"assets/backend/package.json" => package})
    plan = Igniter.compose_task(igniter, Mix.Tasks.Brando.Gen.Backend, [])
    assert plan.issues == []
    package = plan |> IgniterCase.source("assets/backend/package.json") |> Jason.decode!()
    assert package["scripts"]["dev"] == "vite --host"
    assert package["scripts"]["build"] == "vite build"
    assert package["dependencies"]["@brandocms/brandojs"] == "link:../../../assets"
    assert package["dependencies"]["custom-library"] == "^1.0"
    assert package["devDependencies"]["vite"]
    assert Enum.all?(plan.tasks, fn {task, _args} -> task == "brando.assets.copy" end)
  end
end
