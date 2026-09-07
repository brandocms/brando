defmodule Mix.Brando.Igniter.UpgradeTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase

  @legacy_path "lib/mix/brando.upgrade.ex"
  @archive "priv/brando/legacy_tasks/brando.upgrade.ex.disabled"

  defp legacy, do: File.read!(Application.app_dir(:brando, "priv/templates/brando.install/lib/mix/brando.upgrade.ex"))

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

  test "version hook composes through Igniter's actual apply-upgrades dispatcher" do
    version = Application.spec(:brando, :vsn) |> to_string()
    project = IgniterCase.phoenix_project()

    result =
      %{project | args: %Igniter.Mix.Task.Args{positional: %{packages: ["brando:#{version}:#{version}"]}, argv_flags: []}}
      |> Igniter.CopiedTasks.do_apply_upgrades()

    assert result.issues == []
    assert Enum.any?(result.notices, &String.contains?(&1, "already at"))
    Igniter.Test.assert_unchanged(result)
  end

  test "invalid versions, unsupported older source and downgrades do not plan changes" do
    for args <- [[], ["invalid", "0.54.0"], ["0.54.0", "0.53.0"], ["0.53.0", "0.54.0-dev"], ["0.54.0-dev", "9.0.0"]] do
      result = IgniterCase.phoenix_project() |> Igniter.compose_task(Mix.Tasks.Brando.Upgrade, args)
      assert result.issues != []
      assert result.tasks == []
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
