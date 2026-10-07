defmodule E2eProject.DoctorTest do
  # `mix brando.doctor` in a real application: the e2e project's own lib/,
  # assets/backend, migrations, router and configuration.
  use E2eProjectWeb.ConnCase, async: false

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp doctor(args) do
    status =
      try do
        Mix.Tasks.Brando.Doctor.run(args)
        0
      catch
        :exit, {:shutdown, 1} -> 1
      end

    assert_received {:mix_shell, :info, [output]}
    {output, status}
  end

  test "runs every check against the project and reports in JSON" do
    {json, status} = doctor(["--json"])
    report = Jason.decode!(json)
    checks = Map.new(report["checks"], &{&1["id"], &1})

    assert Map.keys(checks) |> Enum.sort() ==
             Enum.sort(~w(versions migrations oban configuration admin_assets image_configs modules sitemap robots json_ld alt_text deprecations))

    refute Enum.any?(report["checks"], &(&1["summary"] == "could not run")), json

    # Read from the project's source tree
    assert %{"status" => "ok", "summary" => "linked to ../../../assets, brandojs " <> _} = checks["admin_assets"]
    assert %{"status" => "ok", "summary" => "none in lib/"} = checks["deprecations"]
    # The router has page_routes(); the monolithic test migration has run
    assert %{"status" => "ok"} = checks["robots"]
    assert %{"status" => "ok"} = checks["migrations"]

    assert status == if(report["status"] == "error", do: 1, else: 0)
    assert report["versions"]["brando"] == Brando.version()
  end

  test "prints a line per check" do
    {text, _status} = doctor(["--verbose"])

    assert text =~ "Brando #{Brando.version()} · Phoenix"
    assert text =~ ~r/^✓ Admin assets\s+linked to/m
    assert text =~ ~r/^. Sitemap\s+/m
  end
end
