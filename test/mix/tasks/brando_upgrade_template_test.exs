defmodule Mix.Tasks.Brando.UpgradeTemplateTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @template_path "priv/templates/brando.install/lib/mix/brando.upgrade.ex"

  setup_all do
    Code.compile_file(@template_path)

    on_exit(fn ->
      :code.purge(Mix.Tasks.Brando.Upgrade)
      :code.delete(Mix.Tasks.Brando.Upgrade)
    end)
  end

  test "copies every missing migration with monotonic versions and is idempotent" do
    tmp_dir = Path.join(System.tmp_dir!(), "brando-upgrade-#{System.unique_integer([:positive])}")
    migrations_dir = Path.join(tmp_dir, "priv/repo/migrations")
    File.mkdir_p!(migrations_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    template_names =
      :brando
      |> Application.app_dir(["priv", "templates", "brando.upgrade", "migrations", "*.exs"])
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)

    [already_installed | _] = template_names
    future_version = DateTime.utc_now() |> DateTime.add(1_000) |> Calendar.strftime("%Y%m%d%H%M%S")
    File.write!(Path.join(migrations_dir, "#{future_version}_#{already_installed}"), "# installed\n")

    run_upgrade(tmp_dir)

    first_run_files = migration_files(migrations_dir)
    assert length(first_run_files) == length(template_names)
    assert Enum.uniq(migration_versions(first_run_files)) == migration_versions(first_run_files)
    assert Enum.sort(migration_versions(first_run_files)) == migration_versions(first_run_files)

    run_upgrade(tmp_dir)
    assert migration_files(migrations_dir) == first_run_files
  end

  defp run_upgrade(tmp_dir) do
    capture_io(fn ->
      File.cd!(tmp_dir, fn -> apply(Mix.Tasks.Brando.Upgrade, :run, [[]]) end)
    end)
  end

  defp migration_files(migrations_dir) do
    migrations_dir
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp migration_versions(files) do
    Enum.map(files, fn filename ->
      filename
      |> String.split("_", parts: 2)
      |> hd()
      |> String.to_integer()
    end)
  end
end
