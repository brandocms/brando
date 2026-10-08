defmodule Brando.DoctorTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Doctor
  alias Brando.Doctor.Report
  alias Brando.Doctor.Result
  alias Brando.DoctorFixtures.{Fails, Healthy, NeedsSource, Raises, Warns}

  describe "checks/0" do
    test "runs Brando's checks, then the application's, without skipped ones" do
      put_test_env(Brando.Doctor, checks: [Healthy], skip: [Brando.Doctor.Checks.AltText])

      checks = Doctor.checks()
      assert List.last(checks) == Healthy
      assert Brando.Doctor.Checks.Migrations in checks
      refute Brando.Doctor.Checks.AltText in checks
      assert length(checks) == length(Doctor.default_checks())
    end
  end

  describe "run/1" do
    test "fills in each check's id and label, in order" do
      assert [%Result{id: "healthy", label: "Healthy", status: :ok, check: Healthy}, %Result{id: "warns"}] =
               Doctor.run(checks: [Healthy, Warns])
    end

    test "a check that raises is an error, and the others still run" do
      assert [%Result{status: :error, items: ["boom"]}, %Result{status: :ok}] = Doctor.run(checks: [Raises, Healthy])
    end

    test "a module that is not a check is an error" do
      assert [%Result{status: :error, label: "String"}] = Doctor.run(checks: [String])
    end

    test "a check that reads the source tree is skipped in a release, and says so" do
      assert [%Result{status: :skipped, summary: summary}] = Doctor.run(checks: [NeedsSource], source?: false)
      assert summary =~ "release"
      assert [%Result{status: :ok}] = Doctor.run(checks: [NeedsSource], source?: true)
    end

    test "runs in the given locale" do
      [result] = Doctor.run(checks: [Brando.Doctor.Checks.Versions], locale: "no")
      assert result.label == "Versjoner"
      assert result.summary =~ "(denne arbeidskopien)"
    end

    test "Brando's checks run without crashing in a standalone application" do
      results = Doctor.run(mode: :mix)

      assert Enum.map(results, & &1.id) ==
               ~w(versions migrations oban configuration admin_assets image_configs modules sitemap robots json_ld alt_text deprecations)

      refute Enum.any?(results, &(&1.summary in ["could not run", "took too long"])),
             inspect(Enum.filter(results, &(&1.summary in ["could not run", "took too long"])))
    end
  end

  describe "status and exit codes" do
    test "only warnings exit 0, unless strict" do
      results = Doctor.run(checks: [Healthy, Warns])
      assert Doctor.status(results) == :warning
      assert Doctor.exit_status(results) == 0
      assert Doctor.exit_status(results, true) == 1
    end

    test "an error exits 1" do
      results = Doctor.run(checks: [Warns, Fails])
      assert Doctor.status(results) == :error
      assert Doctor.exit_status(results) == 1
    end

    test "skipped checks do not fail" do
      results = Doctor.run(checks: [Healthy, NeedsSource], source?: false)
      assert Doctor.status(results) == :ok
      assert Doctor.exit_status(results, true) == 0
      assert Doctor.counts(results) == %{ok: 1, warning: 0, error: 0, skipped: 1}
    end
  end

  describe "Report" do
    @versions %{brando: "0.55.0-dev", elixir: "1.20.3", otp: "28", phoenix: "1.8.15", live_view: "1.2.12"}

    test "prints a line per check, the fix under a failing one, and a summary" do
      text =
        [Healthy, Warns, Fails]
        |> then(&Doctor.run(checks: &1))
        |> Report.text(@versions)
        |> IO.ANSI.format(false)
        |> IO.iodata_to_binary()

      assert text =~ "Brando 0.55.0-dev · Phoenix 1.8.15 · LiveView 1.2.12"
      assert text =~ ~r/^✓ Healthy\s+all good$/m
      assert text =~ ~r/^! Warns\s+2 things\n\s{29}do the thing$/m
      assert text =~ ~r/^✗ Fails\s+broken\n\s{29}mend it$/m
      assert text =~ "1 warning, 1 error. Details: mix brando.doctor --verbose"
      refute text =~ "one thing"
    end

    test "--verbose lists the items" do
      text =
        [Healthy, Warns]
        |> then(&Doctor.run(checks: &1))
        |> Report.text(@versions, verbose: true)
        |> IO.ANSI.format(false)
        |> IO.iodata_to_binary()

      assert text =~ "· one thing"
      assert text =~ "· a"
      refute text =~ "Details:"
    end

    test "the header names where Brando came from" do
      source = %{type: :git, url: "https://x/brando.git", commit: "12c2289e98fa", branch: "main", tag: nil, ref: nil}

      assert Report.header(Map.put(@versions, :brando_source, source)) ==
               "Brando 0.55.0-dev (git 12c2289, branch main) · Phoenix 1.8.15 · LiveView 1.2.12"

      assert %{"versions" => %{"brando_source" => %{"type" => "git", "commit" => "12c2289e98fa", "branch" => "main"}}} =
               Report.json([], Map.put(@versions, :brando_source, source))
    end

    test "all passing" do
      text = [Healthy] |> then(&Doctor.run(checks: &1)) |> Report.text(@versions) |> IO.ANSI.format(false)
      assert IO.iodata_to_binary(text) =~ "All checks passed."
    end

    test "json has the versions, counts and every check" do
      json = [Healthy, Warns] |> then(&Doctor.run(checks: &1)) |> Report.json(@versions)

      assert %{
               "status" => "warning",
               "versions" => %{"brando" => "0.55.0-dev", "live_view" => "1.2.12"},
               "counts" => %{"ok" => 1, "warning" => 1, "error" => 0, "skipped" => 0},
               "checks" => [
                 %{"id" => "healthy", "label" => "Healthy", "status" => "ok", "summary" => "all good", "fix" => nil},
                 %{"id" => "warns", "status" => "warning", "fix" => "do the thing", "items" => ["a", "b"]}
               ]
             } = json

      assert {:ok, _} = Jason.encode(json)
    end
  end
end
