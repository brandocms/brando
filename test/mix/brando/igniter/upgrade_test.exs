defmodule Mix.Brando.Igniter.UpgradeTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.Upgrade

  @legacy_path "lib/mix/brando.upgrade.ex"
  @archive "priv/brando/legacy_tasks/brando.upgrade.ex.disabled"

  @legacy_templates "priv/templates/brando.migrate/legacy_upgrade_tasks"

  defp legacy(version \\ "0.55-dev") do
    File.read!(Application.app_dir(:brando, [@legacy_templates, "brando.upgrade.#{version}.ex"]))
  end

  test "recognized legacy source is archived with its comments before releasing the task name" do
    contents = "# My historical installer\n" <> legacy()

    result =
      IgniterCase.phoenix_project(files: %{@legacy_path => contents})
      |> Igniter.compose_task("brando.upgrade.prepare", [])

    assert result.issues == []
    assert IgniterCase.source(result, @archive) == contents
    Igniter.Test.assert_rms(result, @legacy_path)
    assert result.tasks == []
    applied = IgniterCase.apply_and_reload(result)
    rerun = Igniter.compose_task(applied, "brando.upgrade.prepare", [])
    assert rerun.issues == []
    assert rerun.rms == []
    Igniter.Test.assert_unchanged(rerun)
  end

  test "the task installed by Brando 0.54 is recognized and archived" do
    result =
      IgniterCase.phoenix_project(files: %{@legacy_path => legacy("0.54")})
      |> Igniter.compose_task("brando.upgrade.prepare", [])

    assert result.issues == []
    Igniter.Test.assert_rms(result, @legacy_path)
    assert IgniterCase.source(result, @archive) == legacy("0.54")
  end

  test "the legacy task is found by its content wherever it lives under lib/" do
    path = "lib/legacy_app/tasks/upgrade.ex"

    result =
      IgniterCase.phoenix_project(files: %{path => legacy("0.54")})
      |> Igniter.compose_task("brando.upgrade.prepare", [])

    assert result.issues == []
    Igniter.Test.assert_rms(result, path)
    assert IgniterCase.source(result, @archive) == legacy("0.54")
  end

  test "the installer no longer ships a consumer-owned upgrade task" do
    refute Enum.any?(Mix.Brando.Install.Templates.manifest(), fn {_format, _source, target} ->
             target == "lib/mix/brando.upgrade.ex"
           end)
  end

  test "customized legacy tasks and archive collisions block removal even with yes" do
    for files <- [
          %{@legacy_path => String.replace(legacy(), "def run(_argv) do", "def run(_argv) do\n IO.puts(\"custom\")")},
          %{@legacy_path => legacy(), @archive => "# previous archive"}
        ] do
      result = IgniterCase.phoenix_project(files: files) |> Igniter.compose_task("brando.upgrade.prepare", ["--yes"])
      assert result.issues != []
      assert result.rms == []
      Igniter.Test.assert_unchanged(result, @legacy_path)
    end
  end

  test "framework migration templates have one number each" do
    # A fresh install times each template by its number, so two sharing one
    # are copied with the same version, which Ecto refuses to run.
    numbers =
      [:code.priv_dir(:brando), "templates/brando.upgrade/migrations/brando_*.exs"]
      |> Path.join()
      |> Path.wildcard()
      |> Enum.map(fn path ->
        path |> Path.basename() |> then(&Regex.run(~r/^brando_(\d+)_/, &1, capture: :all_but_first))
      end)

    assert numbers -- Enum.uniq(numbers) == []
  end

  test "framework migration command preserves historical files and does not recreate baseline tables" do
    historical = "priv/repo/migrations/20100101000000_brando_01_set_image_as_jsonb.exs"
    content = "# Historical customized migration\n"

    result =
      IgniterCase.phoenix_project(files: %{historical => content})
      |> Igniter.compose_task("brando.gen.migrations", [])

    assert result.issues == []
    assert result.tasks == []
    Igniter.Test.assert_unchanged(result, historical)
    paths = Map.keys(result.rewrite.sources)
    assert Enum.count(paths, &String.ends_with?(&1, "_brando_01_set_image_as_jsonb.exs")) == 1
    assert Enum.any?(paths, &String.ends_with?(&1, "_brando_170_add_authorization_groups.exs"))
    refute Enum.any?(paths, &String.ends_with?(&1, "_create_users.exs"))
    applied = IgniterCase.apply_and_reload(result)
    rerun = Igniter.compose_task(applied, "brando.gen.migrations", [])
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
  end

  test "framework migration command copies tenant migrations only when tenancy is on" do
    tenant_migration? = fn result ->
      result.rewrite.sources |> Map.keys() |> Enum.any?(&String.starts_with?(&1, "priv/repo/tenant_migrations/"))
    end

    classic = IgniterCase.phoenix_project() |> Igniter.compose_task("brando.gen.migrations", [])
    assert classic.issues == []
    refute tenant_migration?.(classic)

    for mode <- [:none, :single] do
      config = "import Config\nconfig :brando, tenancy_mode: #{inspect(mode)}\n"

      result =
        IgniterCase.phoenix_project(files: %{"config/brando.exs" => config})
        |> Igniter.compose_task("brando.gen.migrations", [])

      assert result.issues == []
      assert tenant_migration?.(result) == (mode == :single)
    end
  end

  # Runs the hook the way mix igniter.upgrade does, through Igniter's dispatcher.
  defp dispatch(from, to) do
    project = IgniterCase.phoenix_project()

    %{project | args: %Igniter.Mix.Task.Args{positional: %{packages: ["brando:#{from}:#{to}"]}, argv_flags: []}}
    |> Igniter.CopiedTasks.do_apply_upgrades()
  end

  # Runs the hook the way mix igniter.upgrade brando does: Igniter.Upgrades
  # parses the lock versions into %Version{} structs (nil FROM for a newly added
  # dependency) and composes the package's upgrade task with them.
  defp upgrade_with_versions(from, to) do
    project = IgniterCase.phoenix_project()
    task = Mix.Task.get("brando.upgrade")

    Igniter.compose_task(project, task, [from && Version.parse!(from), Version.parse!(to)] ++ project.args.argv_flags)
  end

  defp installed_version, do: Application.spec(:brando, :vsn) |> to_string()

  test "version hook composes through Igniter's actual apply-upgrades dispatcher" do
    result = dispatch(installed_version(), installed_version())

    assert result.issues == []
    assert Enum.any?(result.notices, &String.contains?(&1, "already at"))
    Igniter.Test.assert_unchanged(result)
  end

  describe "compare_versions/2" do
    test "a dev prerelease precedes the other prereleases and the release of the same version" do
      assert Upgrade.compare_versions("0.55.0-dev", "0.55.0-beta.0") == :lt
      assert Upgrade.compare_versions("0.55.0-dev", "0.55.0-rc.1") == :lt
      assert Upgrade.compare_versions("0.55.0-dev", "0.55.0") == :lt
      assert Upgrade.compare_versions("0.55.0-beta.0", "0.55.0-dev") == :gt
      assert Upgrade.compare_versions("0.55.0", "0.55.0-dev") == :gt
      assert Upgrade.compare_versions("0.55.0-dev", "0.55.0-dev") == :eq
    end

    test "other versions keep semantic versioning order" do
      assert Upgrade.compare_versions("0.55.0-beta.1", "0.55.0-beta.0") == :gt
      assert Upgrade.compare_versions("0.55.0-beta.0", "0.55.0-beta.0") == :eq
      assert Upgrade.compare_versions("0.56.0-dev", "0.55.0-beta.0") == :gt
      assert Upgrade.compare_versions("0.56.0-dev", "0.55.0") == :gt
      assert Upgrade.compare_versions("0.54.0-beta.0", "0.55.0-dev") == :lt
      assert Upgrade.compare_versions(Version.parse!("0.55.1-dev"), Version.parse!("0.55.0")) == :gt
    end
  end

  test "dev to prerelease and dev to release upgrades pass the dispatcher without a recipe" do
    for to <- ["0.54.0-beta.0", "0.54.0"] do
      result = dispatch("0.54.0-dev", to)

      assert result.issues == []
      assert Enum.any?(result.notices, &String.contains?(&1, "missing framework migrations"))
      refute Enum.any?(result.notices, &String.contains?(&1, "Brando 0.55 source migration prepared"))
    end
  end

  test "a 0.54 prerelease is at or above the oldest supported source and crosses into 0.55 once" do
    result = dispatch("0.54.0-beta.0", installed_version())

    assert result.issues == []
    assert Enum.count(result.notices, &String.contains?(&1, "Brando 0.55 source migration prepared")) == 1
  end

  test "a 0.55 dev source passes the downgrade guard towards a 0.55 prerelease or release" do
    installed = installed_version()

    for to <- ["0.55.0-beta.0", "0.55.0"] do
      result = dispatch("0.55.0-dev", to)

      refute Enum.any?(result.issues, &String.contains?(&1, "downgrades"))

      if Upgrade.compare_versions(to, installed) == :gt do
        # Until the dependency itself is at the target, the hook refuses.
        assert [issue] = result.issues
        assert issue =~ "The loaded Brando version is #{installed}; cannot apply source upgrades for #{to}."
        Igniter.Test.assert_unchanged(result)
      else
        assert result.issues == []
        refute Enum.any?(result.notices, &String.contains?(&1, "Brando 0.55 source migration prepared"))
      end
    end
  end

  test "downgrades between prereleases and versions are rejected" do
    for {from, to} <- [
          {"0.55.0-beta.0", "0.55.0-dev"},
          {"0.55.0", "0.55.0-dev"},
          {"0.55.0-beta.1", "0.55.0-beta.0"},
          {"0.56.0-dev", "0.55.0-beta.0"},
          {"0.56.0-dev", "0.55.0-dev"}
        ] do
      result = dispatch(from, to)

      assert Enum.any?(result.issues, &String.contains?(&1, "downgrades are not supported")), "#{from} -> #{to}"
      assert result.tasks == []
      Igniter.Test.assert_unchanged(result)
    end
  end

  describe "with the Version structs mix igniter.upgrade passes" do
    test "a dev to prerelease or release upgrade of the same version plans without a recipe" do
      for to <- ["0.54.0-beta.0", "0.54.0"] do
        result = upgrade_with_versions("0.54.0-dev", to)

        assert result.issues == []
        assert Enum.any?(result.notices, &String.contains?(&1, "missing framework migrations"))
        refute Enum.any?(result.notices, &String.contains?(&1, "Brando 0.55 source migration prepared"))
      end
    end

    test "a 0.54 source crosses into 0.55 once" do
      result = upgrade_with_versions("0.54.0-beta.0", installed_version())

      assert result.issues == []
      assert Enum.count(result.notices, &String.contains?(&1, "Brando 0.55 source migration prepared")) == 1
    end

    test "downgrades are rejected" do
      for {from, to} <- [{"0.55.0-beta.0", "0.55.0-dev"}, {"0.55.0", "0.55.0-dev"}] do
        result = upgrade_with_versions(from, to)

        assert Enum.any?(result.issues, &String.contains?(&1, "downgrades are not supported")), "#{from} -> #{to}"
        assert result.tasks == []
        Igniter.Test.assert_unchanged(result)
      end
    end

    test "a newly added dependency has no FROM and plans no changes" do
      result = upgrade_with_versions(nil, installed_version())

      assert [issue] = result.issues
      assert issue =~ "Versioned upgrades require FROM TO arguments"
      Igniter.Test.assert_unchanged(result)
    end
  end

  test "invalid versions, unsupported older source and downgrades do not plan changes" do
    for args <- [[], ["invalid", "0.54.0"], ["0.54.0", "0.53.0"], ["0.53.0", "0.54.0-dev"], ["0.54.0-dev", "9.0.0"]] do
      result = IgniterCase.phoenix_project() |> Igniter.compose_task(Mix.Tasks.Brando.Upgrade, args)
      assert result.issues != []
      assert result.tasks == []
      Igniter.Test.assert_unchanged(result)
    end
  end

  test "a 0.54 to 0.55 upgrade composes the brando.migrate55 recipe before planning migrations" do
    installed = Application.spec(:brando, :vsn) |> to_string() |> Version.parse!()
    result = IgniterCase.phoenix_project() |> Igniter.compose_task(Mix.Tasks.Brando.Upgrade, ["0.54.0", "0.55.0-dev"])

    if installed.minor >= 55 do
      assert result.issues == []
      assert Enum.any?(result.notices, &String.contains?(&1, "Brando 0.55 source migration prepared"))
      assert Enum.any?(result.notices, &String.contains?(&1, "missing framework migrations"))
    else
      # Until the dependency itself is 0.55, the hook must refuse rather than
      # apply a recipe for a version that is not loaded.
      assert Enum.any?(result.issues, &String.contains?(&1, "cannot apply source upgrades for 0.55.0-dev"))
      Igniter.Test.assert_unchanged(result)
    end
  end

  test "versioned composition detects a consumer-owned task before planning upgrades" do
    result =
      IgniterCase.phoenix_project(files: %{@legacy_path => legacy()})
      |> Igniter.compose_task(Mix.Tasks.Brando.Upgrade, ["0.54.0-dev", "0.54.0-dev"])

    assert Enum.any?(result.issues, &String.contains?(&1, "brando.upgrade.prepare"))
    Igniter.Test.assert_unchanged(result)
  end
end
