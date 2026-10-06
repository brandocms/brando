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

  describe "brando.gen.backend --upgrade" do
    # A 0.54 site's admin, as smartwatt had it: yarn, Vite 5, Svelte 4.
    @old_package ~s({
      "name": "backend",
      "version": "0.0.0",
      "type": "module",
      "scripts": {"dev": "vite --host", "build": "vite build", "serve": "vite preview"},
      "dependencies": {
        "@brandocms/brandojs": "file:.yalc/@brandocms/brandojs",
        "@brandocms/jupiter": "^3.47.0",
        "site-widget": "^2.0.0"
      },
      "devDependencies": {
        "@brandocms/europacss": "^0.13.1",
        "@sveltejs/vite-plugin-svelte": "3.0.2",
        "autoprefixer": "^10.4.19",
        "svelte": "^4.2.12",
        "svelte-preprocess": "^5.1.3",
        "vite": "^5.2.7"
      }
    })

    @custom_css "/* the site's own admin styles */\n@import '@brandocms/brandojs/css/app.css';\n"

    defp old_backend(extra \\ %{}) do
      %{
        "assets/backend/package.json" => @old_package,
        "assets/backend/vite.config.js" => "export default { build: { rollupOptions: {} } }\n",
        "assets/backend/svelte.config.cjs" => "module.exports = {}\n",
        "assets/backend/yarn.lock" => "# yarn lockfile v1\n",
        "assets/backend/css/app.css" => @custom_css,
        "Dockerfile" => File.read!("test/fixtures/backend_054/Dockerfile")
      }
      |> Map.merge(extra)
    end

    defp upgrade(files) do
      IgniterCase.phoenix_project(files: files) |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Backend, ["--upgrade"])
    end

    defp template(path), do: Templates.contents(:copy, path)

    test "moves package versions, Vite config and lockfile to the template and keeps the site's own" do
      plan = upgrade(old_backend())
      assert plan.issues == []

      source = IgniterCase.source(plan, "assets/backend/package.json")
      package = Jason.decode!(source)
      wanted = template("assets/backend/package.json") |> Jason.decode!()

      # The file's own key order is kept, and new keys follow the template's.
      keys = Jason.decode!(source, objects: :ordered_objects).values |> Enum.map(&elem(&1, 0))
      assert Enum.take(keys, 6) == ~w(name version type scripts dependencies devDependencies)
      assert Enum.drop(keys, 6) == ~w(pnpm engines packageManager)

      # Nested objects keep their order too.
      ordered = Jason.decode!(source, objects: :ordered_objects)
      assert Enum.map(ordered["scripts"].values, &elem(&1, 0)) == ~w(dev build serve)

      assert Enum.map(ordered["dependencies"].values, &elem(&1, 0)) ==
               ~w(@brandocms/brandojs @brandocms/jupiter site-widget)

      assert package["devDependencies"]["vite"] == wanted["devDependencies"]["vite"]
      assert package["devDependencies"]["svelte"] == wanted["devDependencies"]["svelte"]
      assert package["dependencies"]["@brandocms/jupiter"] == wanted["dependencies"]["@brandocms/jupiter"]
      refute Map.has_key?(package["devDependencies"], "svelte-preprocess")
      assert package["packageManager"] == wanted["packageManager"]
      assert package["engines"] == wanted["engines"]
      assert package["pnpm"]["onlyBuiltDependencies"] == wanted["pnpm"]["onlyBuiltDependencies"]

      assert package["dependencies"]["@brandocms/brandojs"] == "file:.yalc/@brandocms/brandojs"
      assert package["dependencies"]["site-widget"] == "^2.0.0"
      assert package["scripts"]["dev"] == "vite --host"

      assert IgniterCase.source(plan, "assets/backend/vite.config.js") == template("assets/backend/vite.config.js")
      Igniter.Test.assert_rms(plan, ["assets/backend/svelte.config.cjs", "assets/backend/yarn.lock"])
      Igniter.Test.assert_unchanged(plan, "assets/backend/css/app.css")

      # Files the old backend lacked are created.
      assert IgniterCase.source(plan, "assets/backend/css/blocks.css") == template("assets/backend/css/blocks.css")
    end

    test "replaces the Dockerfile's yarn assets_backend stage with the template's pnpm stage" do
      plan = upgrade(old_backend())
      dockerfile = IgniterCase.source(plan, "Dockerfile")

      {_, wanted, _} = Mix.Brando.Igniter.Assets.dockerfile_stage(template("Dockerfile"), "assets_backend")
      {_, stage, _} = Mix.Brando.Igniter.Assets.dockerfile_stage(dockerfile, "assets_backend")
      assert stage == wanted
      refute Enum.join(stage, "\n") =~ "yarn"

      # The other stages are the site's, untouched.
      assert dockerfile =~ "FROM --platform=linux/amd64 twined/fehn:3.9 as deps"
      assert dockerfile =~ "COPY assets/frontend/package.json assets/frontend/yarn.lock ./"
      assert dockerfile =~ "RUN yarn build"
    end

    test "is idempotent" do
      plan = upgrade(old_backend())
      rerun = plan |> IgniterCase.apply_and_reload() |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Backend, ["--upgrade"])

      assert rerun.issues == []
      assert rerun.rms == []

      Igniter.Test.assert_unchanged(rerun, [
        "assets/backend/package.json",
        "assets/backend/vite.config.js",
        "assets/backend/css/app.css",
        "Dockerfile"
      ])
    end
  end

  test "brando.assets.setup --backend-only does not require a frontend" do
    directory = Path.join(System.tmp_dir!(), "brando-backend-only-#{System.unique_integer([:positive])}")
    source = Path.join(directory, "brandojs")

    try do
      File.mkdir_p!(Path.join(directory, "assets/backend"))
      File.mkdir_p!(source)
      File.write!(Path.join(directory, "assets/backend/package.json"), "{}")
      File.write!(Path.join(source, "package.json"), ~s({"name": "@brandocms/brandojs"}))

      File.cd!(directory, fn ->
        assert_raise Mix.Error, ~r{assets/frontend/package.json}, fn ->
          Mix.Tasks.Brando.Assets.Setup.run(["--source", source, "--no-build"])
        end

        # Past the package checks it stops at the first tool missing from PATH.
        path = System.get_env("PATH")
        System.put_env("PATH", "")

        try do
          assert_raise Mix.Error, ~r/is required by mix brando.assets.setup/, fn ->
            Mix.Tasks.Brando.Assets.Setup.run(["--source", source, "--no-build", "--backend-only"])
          end
        after
          System.put_env("PATH", path)
        end
      end)
    after
      File.rm_rf!(directory)
    end
  end

  # A stylesheet the installer copies but whose `@import` it does not is only
  # found once a generated site runs `vite build`, which is the consumer smoke
  # in CI rather than anything here. `includes/common.css` and
  # `includes/footer.css` were missing for exactly that reason.
  test "every @import in a copied stylesheet is itself copied" do
    targets = MapSet.new(Templates.manifest(), fn {_format, _source, target} -> target end)

    for {format, source, target} <- Templates.manifest(),
        Path.extname(target) == ".css",
        imported <- imports(Templates.contents(format, source)) do
      resolved = target |> Path.dirname() |> Path.join(imported) |> Path.expand("/") |> Path.relative_to("/")

      assert MapSet.member?(targets, resolved),
             "#{target} imports #{imported}, which the install manifest does not copy"
    end
  end

  defp imports(contents) do
    ~r/@import\s+['"]([^'"]+)['"]/
    |> Regex.scan(contents)
    |> Enum.map(fn [_, path] -> path end)
  end
end
