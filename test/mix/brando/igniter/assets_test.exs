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

  defp generate_backend(igniter, version) do
    igniter |> Igniter.assign(:brando_version, version) |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Backend, [])
  end

  test "a generated admin takes BrandoJS from Brando's spec: npm for a release, Yalc for a -dev version" do
    project = IgniterCase.phoenix_project(without: ["assets/backend/package.json"])
    template = Templates.contents(:copy, "assets/backend/package.json")
    # The template pins Brando's version; only the BrandoJS spec differs from it.
    assert Jason.decode!(template)["dependencies"]["@brandocms/brandojs"] == Brando.version()

    for {version, spec} <- [{"0.55.0", "0.55.0"}, {"0.56.0-dev", "file:.yalc/@brandocms/brandojs"}] do
      plan = generate_backend(project, version)
      assert plan.issues == []
      package = plan |> IgniterCase.source("assets/backend/package.json") |> Jason.decode!()

      assert package["dependencies"]["@brandocms/brandojs"] == spec
      assert package == template |> Jason.decode!() |> put_in(["dependencies", "@brandocms/brandojs"], spec)
    end

    # Without an assigned version the generator pairs with this Brando.
    plan = Igniter.compose_task(project, Mix.Tasks.Brando.Gen.Backend, [])
    package = plan |> IgniterCase.source("assets/backend/package.json") |> Jason.decode!()
    assert package["dependencies"]["@brandocms/brandojs"] == Mix.Brando.BrandoJS.spec()
  end

  test "generating into an existing admin keeps its BrandoJS source, in the section that declares it" do
    yalc = ~s({"dependencies":{"@brandocms/brandojs":"file:.yalc/@brandocms/brandojs"}})
    plan = IgniterCase.phoenix_project(files: %{"assets/backend/package.json" => yalc}) |> generate_backend("0.55.0")
    package = plan |> IgniterCase.source("assets/backend/package.json") |> Jason.decode!()
    assert package["dependencies"]["@brandocms/brandojs"] == "file:.yalc/@brandocms/brandojs"

    dev = ~s({"devDependencies":{"@brandocms/brandojs":"link:../../brando/assets"}})
    plan = IgniterCase.phoenix_project(files: %{"assets/backend/package.json" => dev}) |> generate_backend("0.55.0")
    package = plan |> IgniterCase.source("assets/backend/package.json") |> Jason.decode!()
    assert package["devDependencies"]["@brandocms/brandojs"] == "link:../../brando/assets"
    refute Map.has_key?(package["dependencies"], "@brandocms/brandojs")
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

    defp upgrade(files, version \\ nil) do
      igniter = IgniterCase.phoenix_project(files: files)
      igniter = if version, do: Igniter.assign(igniter, :brando_version, version), else: igniter
      Igniter.compose_task(igniter, Mix.Tasks.Brando.Gen.Backend, ["--upgrade"])
    end

    defp upgraded_package(plan), do: plan |> IgniterCase.source("assets/backend/package.json") |> Jason.decode!()

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
      assert package["pnpm"]["overrides"] == wanted["pnpm"]["overrides"]

      assert package["dependencies"]["@brandocms/brandojs"] == "file:.yalc/@brandocms/brandojs"
      assert package["dependencies"]["site-widget"] == "^2.0.0"
      assert package["scripts"]["dev"] == "vite --host"

      # The legacy EuropaCSS PostCSS build gives way to the native compiler's Vite plugin.
      refute Map.has_key?(package["devDependencies"], "@brandocms/europacss")
      refute Map.has_key?(package["devDependencies"], "autoprefixer")

      # Both EuropaCSS packages at the template's exact npm version, the CLI
      # for `pnpm exec europa`.
      for name <- ~w(@brandocms/europacss-cli @brandocms/vite-plugin-europacss) do
        assert package["devDependencies"][name] == wanted["devDependencies"][name]
        assert package["devDependencies"][name] =~ ~r/^\d+\.\d+\.\d+/
      end

      assert IgniterCase.source(plan, "assets/backend/vite.config.js") == template("assets/backend/vite.config.js")
      Igniter.Test.assert_rms(plan, ["assets/backend/svelte.config.cjs", "assets/backend/yarn.lock"])

      # Files the old backend lacked are created, the EuropaCSS config among them.
      assert IgniterCase.source(plan, "assets/backend/europa.json5") == template("assets/backend/europa.json5")
      # Its stylesheet keeps importing BrandoJS's: the Vite plugin resolves package imports.
      Igniter.Test.assert_unchanged(plan, "assets/backend/css/app.css")
    end

    test "an npm BrandoJS pin moves to Brando's spec, a local source stays" do
      npm = String.replace(@old_package, "file:.yalc/@brandocms/brandojs", "0.54.0")

      assert upgraded_package(upgrade(old_backend(%{"assets/backend/package.json" => npm}), "0.55.0"))["dependencies"][
               "@brandocms/brandojs"
             ] == "0.55.0"

      dev = upgrade(old_backend(%{"assets/backend/package.json" => npm}), "0.56.0-dev")
      assert upgraded_package(dev)["dependencies"]["@brandocms/brandojs"] == "file:.yalc/@brandocms/brandojs"

      for spec <- ["file:.yalc/@brandocms/brandojs", "link:../../../brando/assets"] do
        local = String.replace(@old_package, "file:.yalc/@brandocms/brandojs", spec)
        plan = upgrade(old_backend(%{"assets/backend/package.json" => local}), "0.55.0")
        assert upgraded_package(plan)["dependencies"]["@brandocms/brandojs"] == spec
        assert Enum.any?(plan.notices, &(&1 =~ "mix brando.assets.setup --npm" and &1 =~ spec))

        plan = upgrade(old_backend(%{"assets/backend/package.json" => local}), "0.56.0-dev")
        refute Enum.any?(plan.notices, &(&1 =~ "mix brando.assets.setup --npm"))
      end
    end

    test "BrandoJS in devDependencies stays there: a local source is kept, an npm pin moves to Brando's spec" do
      package = fn spec -> ~s({"devDependencies": {"@brandocms/brandojs": "#{spec}", "vite": "^5.0.0"}}) end

      plan = upgrade(old_backend(%{"assets/backend/package.json" => package.("link:../../brando/assets")}), "0.55.0")
      upgraded = upgraded_package(plan)
      assert upgraded["devDependencies"]["@brandocms/brandojs"] == "link:../../brando/assets"
      refute Map.has_key?(upgraded["dependencies"], "@brandocms/brandojs")
      assert upgraded["dependencies"]["@brandocms/jupiter"]

      upgraded = upgraded_package(upgrade(old_backend(%{"assets/backend/package.json" => package.("0.54.0")}), "0.55.0"))
      assert upgraded["devDependencies"]["@brandocms/brandojs"] == "0.55.0"
      refute Map.has_key?(upgraded["dependencies"], "@brandocms/brandojs")
    end

    test "an admin without BrandoJS gets it in dependencies" do
      upgraded =
        upgraded_package(upgrade(old_backend(%{"assets/backend/package.json" => ~s({"name": "backend"})}), "0.55.0"))

      assert upgraded["dependencies"]["@brandocms/brandojs"] == "0.55.0"
      refute Map.has_key?(upgraded["devDependencies"], "@brandocms/brandojs")
    end

    test "removes an earlier template's legacy EuropaCSS configs and keeps a site's own with a notice" do
      earlier_postcss =
        "module.exports = {\n  plugins: [\n    require('@brandocms/europacss'),\n    require('autoprefixer')()\n  ]\n}\n"

      for postcss <- [earlier_postcss, File.read!("test/fixtures/legacy_europa/postcss.config.cjs")] do
        plan =
          upgrade(
            old_backend(%{
              "assets/backend/postcss.config.cjs" => postcss,
              "assets/backend/europa.config.cjs" => "module.exports = require('@brandocms/brandojs/europa.config.js')\n"
            })
          )

        Igniter.Test.assert_rms(plan, [
          "assets/backend/postcss.config.cjs",
          "assets/backend/europa.config.cjs",
          "assets/backend/svelte.config.cjs",
          "assets/backend/yarn.lock"
        ])
      end

      own_postcss = "module.exports = { plugins: [require('@brandocms/europacss'), require('postcss-nested')] }\n"

      own_europa =
        "const base = require('@brandocms/brandojs/europa.config.js')\nmodule.exports = { ...base, theme: { ...base.theme } }\n"

      plan =
        upgrade(
          old_backend(%{
            "assets/backend/postcss.config.cjs" => own_postcss,
            "assets/backend/europa.config.cjs" => own_europa
          })
        )

      Igniter.Test.assert_unchanged(plan, ["assets/backend/postcss.config.cjs", "assets/backend/europa.config.cjs"])
      assert Enum.any?(plan.notices, &(&1 =~ "assets/backend/postcss.config.cjs is not one Brando's templates wrote"))
      assert Enum.any?(plan.notices, &(&1 =~ "europa migrate-config europa.config.cjs"))
    end

    test "points out legacy at-rules in the site's admin CSS" do
      css = ".panels {\n  @row 2;\n}\n@import 'some-package/style.css';\n.row {\n  @row;\n}\n"
      plan = upgrade(old_backend(%{"assets/backend/css/app.css" => css}))

      assert Enum.any?(plan.notices, &(&1 =~ "assets/backend/css/app.css (lines 2, 6) uses `@row`"))
      refute Enum.any?(plan.notices, &(&1 =~ "lines 4"))
      Igniter.Test.assert_unchanged(plan, "assets/backend/css/app.css")
    end

    test "the E2E admin builds with the template's EuropaCSS config and stylesheet" do
      assert File.read!("e2e/assets/backend/europa.json5") == template("assets/backend/europa.json5")
      assert File.read!("e2e/assets/backend/css/app.css") == template("assets/backend/css/app.css")
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

    test "moves an old Dockerfile frontend to docker/dockerfile:1, which skips the optional .yalc COPY's empty match" do
      assert template("Dockerfile") |> String.split("\n") |> hd() == "# syntax=docker/dockerfile:1"
      assert old_backend()["Dockerfile"] =~ ~r/\A# syntax = docker\/dockerfile:1.0-experimental\n/

      plan = upgrade(old_backend())
      dockerfile = IgniterCase.source(plan, "Dockerfile")
      assert dockerfile =~ ~r/\A# syntax=docker\/dockerfile:1\n\n# ---/
      assert Enum.any?(plan.notices, &(&1 =~ "declared docker/dockerfile:1.0-experimental"))

      for old <-
            ~w(docker/dockerfile:1.0 docker/dockerfile:1.1.7 docker/dockerfile:1.1-experimental docker/dockerfile:experimental) do
        current = String.replace(old_backend()["Dockerfile"], "docker/dockerfile:1.0-experimental", old)
        dockerfile = IgniterCase.source(upgrade(old_backend(%{"Dockerfile" => current})), "Dockerfile")
        assert dockerfile =~ ~r/\A# syntax=docker\/dockerfile:1\n/, old
      end
    end

    test "adds a syntax directive the Dockerfile lacks, after any other directive" do
      [_syntax | rest] = String.split(old_backend()["Dockerfile"], "\n")
      plan = upgrade(old_backend(%{"Dockerfile" => Enum.join(rest, "\n")}))
      assert IgniterCase.source(plan, "Dockerfile") =~ ~r/\A# syntax=docker\/dockerfile:1\n\n# ---/
      assert Enum.any?(plan.notices, &(&1 =~ "had no syntax directive"))

      # A blank line would end the directives, leaving the escape one a comment.
      plan = upgrade(old_backend(%{"Dockerfile" => Enum.join(["# escape=`" | rest], "\n")}))
      assert IgniterCase.source(plan, "Dockerfile") =~ ~r/\A# syntax=docker\/dockerfile:1\n# escape=`\n\n# ---/
    end

    test "keeps a current or custom Dockerfile frontend, with a notice for a custom one" do
      for kept <- ~w(docker/dockerfile:1 docker/dockerfile:1.10 docker/dockerfile:1.7-labs) do
        current = String.replace(old_backend()["Dockerfile"], "docker/dockerfile:1.0-experimental", kept)
        plan = upgrade(old_backend(%{"Dockerfile" => current}))
        assert IgniterCase.source(plan, "Dockerfile") =~ "# syntax = #{kept}\n"
        refute Enum.any?(plan.notices, &(&1 =~ "syntax")), kept
      end

      current =
        String.replace(old_backend()["Dockerfile"], "docker/dockerfile:1.0-experimental", "example.com/frontend:2")

      plan = upgrade(old_backend(%{"Dockerfile" => current}))
      assert IgniterCase.source(plan, "Dockerfile") =~ "# syntax = example.com/frontend:2\n"
      assert Enum.any?(plan.notices, &(&1 =~ "Dockerfile frontend example.com/frontend:2, which this task keeps"))
    end

    test "says the assets_frontend stage keeps its Node image when there is no frontend package to check" do
      [notice] = upgrade(old_backend()).notices |> Enum.filter(&(&1 =~ "assets_frontend"))
      assert notice =~ "still builds on node:18"
      assert notice =~ "which builds on node:24"
      assert notice =~ "There is no assets/frontend/package.json"

      {_, stage, _} = Mix.Brando.Igniter.Assets.dockerfile_stage(template("Dockerfile"), "assets_frontend")
      current = old_backend()["Dockerfile"]
      {before, _old, rest} = Mix.Brando.Igniter.Assets.dockerfile_stage(current, "assets_frontend")
      plan = upgrade(old_backend(%{"Dockerfile" => Enum.join(before ++ stage ++ rest, "\n")}))
      refute Enum.any?(plan.notices, &(&1 =~ "assets_frontend"))
    end

    test "runs Igniter's deps.get without Hex's package listing" do
      parent = self()
      System.delete_env("MIX_QUIET")

      Mix.Brando.Igniter.Assets.without_hex_listing(fn -> send(parent, {:quiet, System.get_env("MIX_QUIET")}) end)

      assert_received {:quiet, "1"}
      assert System.get_env("MIX_QUIET") == nil
    end

    test "is idempotent" do
      plan = upgrade(old_backend())
      rerun = plan |> IgniterCase.apply_and_reload() |> Igniter.compose_task(Mix.Tasks.Brando.Gen.Backend, ["--upgrade"])

      assert rerun.issues == []
      assert rerun.rms == []

      Igniter.Test.assert_unchanged(rerun, [
        "assets/backend/package.json",
        "assets/backend/vite.config.js",
        "assets/backend/europa.json5",
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
