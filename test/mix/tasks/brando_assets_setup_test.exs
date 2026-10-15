defmodule Mix.Tasks.Brando.Assets.SetupTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Brando.Assets.Setup

  @yalc "file:.yalc/@brandocms/brandojs"

  describe "source/3" do
    test "without options, the admin keeps the source its package.json names" do
      assert Setup.source([], "0.55.0", "0.55.0") == :npm
      assert Setup.source([], @yalc, "0.55.0") == {:yalc, :dependency}
      assert Setup.source([], "link:.yalc/@brandocms/brandojs", "0.55.0") == {:yalc, :dependency}
    end

    test "without options, a linked checkout stays linked rather than becoming a Yalc copy" do
      assert Setup.source([], "link:../../brando/assets", "0.55.0") == {:linked, "../../brando/assets"}
      assert Setup.source([], "file:../brando/assets", "0.55.0-dev") == {:linked, "../brando/assets"}
    end

    test "without options and without BrandoJS, the admin gets what a generated one has" do
      assert Setup.source([], nil, "0.55.0") == {:npm, :switch}
      assert Setup.source([], nil, "0.55.0-dev") == {:yalc, :dependency}
    end

    test "--local and --source switch to a Yalc copy" do
      assert Setup.source([local: true], "0.55.0", "0.55.0") == {:yalc, :dependency}
      assert Setup.source([local: true], "link:../brando/assets", "0.55.0") == {:yalc, :dependency}
      assert Setup.source([source: "../brando/assets"], "0.55.0", "0.55.0") == {:yalc, "../brando/assets"}
    end

    test "--npm switches to npm, which a development version does not have" do
      assert Setup.source([npm: true], @yalc, "0.55.0-beta.0") == {:npm, :switch}

      assert_raise Mix.Error, ~r/development version and has no npm release/, fn ->
        Setup.source([npm: true], @yalc, "0.55.0-dev")
      end
    end

    test "only one source at a time" do
      assert_raise Mix.Error, ~r/Choose one of/, fn -> Setup.source([npm: true, local: true], @yalc, "0.55.0") end
    end
  end

  test "Yalc is needed only for a Yalc copy" do
    assert Setup.required_tools({:yalc, :dependency}) == ["node", "pnpm", "yalc"]
    assert Setup.required_tools({:linked, "/x"}) == ["node", "pnpm"]
    assert Setup.required_tools({:npm, :switch}) == ["node", "pnpm"]
    assert Setup.required_tools(:npm) == ["node", "pnpm"]
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

defmodule Mix.Tasks.Brando.Assets.SetupRunTest do
  # Changes the working directory and PATH, which are global to the VM.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Brando.Assets.Setup

  setup do
    directory = Path.join(System.tmp_dir!(), "brando-assets-setup-run-#{System.unique_integer([:positive])}")
    package = ~s({"dependencies": {"@brandocms/brandojs": "link:../../brandojs"}}\n)
    File.mkdir_p!(Path.join(directory, "assets/backend"))
    File.write!(Path.join(directory, "assets/backend/package.json"), package)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory, package: package}
  end

  defp setup!(directory, argv \\ ["--backend-only", "--no-build"]) do
    path = System.get_env("PATH")
    System.put_env("PATH", "")

    try do
      File.cd!(directory, fn -> Setup.run(argv) end)
    after
      System.put_env("PATH", path)
    end
  end

  test "a linked checkout must be the BrandoJS package", %{directory: directory} do
    assert_raise Mix.Error, ~r{Missing .*/brandojs/package.json\. .*takes it from link:\.\./\.\./brandojs}, fn ->
      setup!(directory)
    end

    File.mkdir_p!(Path.join(directory, "brandojs"))
    File.write!(Path.join(directory, "brandojs/package.json"), ~s({"name": "other"}))

    assert_raise Mix.Error, ~r/is not the @brandocms\/brandojs package directory/, fn -> setup!(directory) end
  end

  test "a linked checkout is kept as it is, and a missing tool stops setup before anything changes",
       %{directory: directory, package: package} do
    File.mkdir_p!(Path.join(directory, "brandojs"))
    File.write!(Path.join(directory, "brandojs/package.json"), ~s({"name": "@brandocms/brandojs"}))

    assert_raise Mix.Error, ~r/node is required by mix brando.assets.setup/, fn -> setup!(directory) end
    assert File.read!(Path.join(directory, "assets/backend/package.json")) == package
    refute File.exists?(Path.join(directory, "assets/backend/.yalc"))
  end
end
