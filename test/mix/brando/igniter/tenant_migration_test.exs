defmodule Mix.Brando.Igniter.TenantMigrationTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase

  test "plans ordered tenant migrations and preserves customized reruns" do
    existing = "priv/repo/tenant_migrations/20990101000000_existing.exs"
    project = IgniterCase.phoenix_project(app: :shop, module: "Acme.Shop", files: %{existing => "# keep\n"})
    result = Igniter.compose_task(project, "brando.gen.tenant_migration", ["add_projects"])
    target = "priv/repo/tenant_migrations/20990101000001_add_projects.exs"
    assert result.issues == []
    assert IgniterCase.source(result, target) =~ "defmodule Acme.Shop.Repo.Migrations.AddProjects"
    assert result.tasks == []
    applied = IgniterCase.apply_and_reload(result)
    rerun = Igniter.compose_task(applied, "brando.gen.tenant_migration", ["add_projects"])
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
  end

  test "supports an explicit path and migration module" do
    result =
      IgniterCase.phoenix_project()
      |> Igniter.compose_task("brando.gen.tenant_migration", [
        "add_projects",
        "--migrations-path",
        "priv/tenants",
        "--migration-module",
        "Studio.Migration"
      ])

    assert result.issues == []
    path = Enum.find(Map.keys(result.rewrite.sources), &String.ends_with?(&1, "_add_projects.exs"))
    assert Path.dirname(path) == "priv/tenants"
    assert IgniterCase.source(result, path) =~ "use Studio.Migration"
  end

  test "invalid and missing names or paths do not prompt or plan changes" do
    for args <- [
          [],
          ["../unsafe"],
          ["BadName"],
          ["safe", "--migrations-path", "../outside"],
          ["safe", "--migrations-path", "priv/*"],
          ["safe", "--migration-module", "invalid"]
        ] do
      result = IgniterCase.phoenix_project() |> Igniter.compose_task("brando.gen.tenant_migration", args)
      assert result.issues != []
      Igniter.Test.assert_unchanged(result)
      refute_received {:mix_shell, :prompt, _}
    end
  end

  test "guidance asks for a missing name and handles closed stdin" do
    send(self(), {:mix_shell_input, :prompt, "add_projects"})
    result = IgniterCase.phoenix_project() |> Igniter.compose_task("brando.gen.tenant_migration", ["--interactive"])
    assert result.issues == []
    assert_received {:mix_shell, :prompt, ["+ Migration name"]}
    send(self(), {:mix_shell_input, :prompt, :eof})
    result = IgniterCase.phoenix_project() |> Igniter.compose_task("brando.gen.tenant_migration", ["--interactive"])
    assert Enum.any?(result.issues, &String.contains?(&1, "Input closed"))
    Igniter.Test.assert_unchanged(result)
  end
end
