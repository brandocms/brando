defmodule Mix.Tasks.Brando.Assets.SetupTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Brando.Assets.Setup

  @yalc "file:.yalc/@brandocms/brandojs"

  describe "source/3" do
    test "without options, the admin keeps the source its package.json names" do
      assert Setup.source([], "0.55.0", "0.55.0") == :npm
      assert Setup.source([], @yalc, "0.55.0") == {:local, :dependency}
      assert Setup.source([], "link:../../brando/assets", "0.55.0") == {:local, :dependency}
      assert Setup.source([], nil, "0.55.0") == {:local, :dependency}
    end

    test "--local and --source switch to a Yalc copy" do
      assert Setup.source([local: true], "0.55.0", "0.55.0") == {:local, :dependency}
      assert Setup.source([source: "../brando/assets"], "0.55.0", "0.55.0") == {:local, "../brando/assets"}
    end

    test "--npm switches to npm, which a development version does not have" do
      assert Setup.source([npm: true], @yalc, "0.55.0-beta.0") == :npm

      assert_raise Mix.Error, ~r/development version and has no npm release/, fn ->
        Setup.source([npm: true], @yalc, "0.55.0-dev")
      end
    end

    test "only one source at a time" do
      assert_raise Mix.Error, ~r/Choose one of/, fn -> Setup.source([npm: true, local: true], @yalc, "0.55.0") end
    end
  end

  describe "remove_yalc_copy/1" do
    setup do
      backend = Path.join(System.tmp_dir!(), "brando-assets-setup-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(backend, ".yalc/@brandocms/brandojs"))
      File.write!(Path.join(backend, ".yalc/@brandocms/brandojs/package.json"), "{}")
      on_exit(fn -> File.rm_rf!(backend) end)
      %{backend: backend}
    end

    test "removes BrandoJS's copy, the emptied directories and the lock", %{backend: backend} do
      lock = %{"version" => "v1", "packages" => %{"@brandocms/brandojs" => %{"signature" => "x", "file" => true}}}
      File.write!(Path.join(backend, "yalc.lock"), Jason.encode!(lock))

      Setup.remove_yalc_copy(backend)

      refute File.exists?(Path.join(backend, ".yalc"))
      refute File.exists?(Path.join(backend, "yalc.lock"))
    end

    test "leaves other packages Yalc holds", %{backend: backend} do
      File.mkdir_p!(Path.join(backend, ".yalc/@brandocms/jupiter"))

      lock = %{
        "version" => "v1",
        "packages" => %{"@brandocms/brandojs" => %{"file" => true}, "@brandocms/jupiter" => %{"file" => true}}
      }

      File.write!(Path.join(backend, "yalc.lock"), Jason.encode!(lock))

      Setup.remove_yalc_copy(backend)

      refute File.exists?(Path.join(backend, ".yalc/@brandocms/brandojs"))
      assert File.dir?(Path.join(backend, ".yalc/@brandocms/jupiter"))
      packages = backend |> Path.join("yalc.lock") |> File.read!() |> Jason.decode!() |> Map.fetch!("packages")
      assert Map.keys(packages) == ["@brandocms/jupiter"]
    end
  end
end
