defmodule Mix.Tasks.Brando.Doctor do
  @shortdoc "Explains what is misconfigured or out of date"

  @moduledoc """
  Runs Brando's system checks and prints a line per check, with the fix under
  any that fails:

      mix brando.doctor
      mix brando.doctor --verbose
      mix brando.doctor --json
      mix brando.doctor --strict
      mix brando.doctor --offline

  It checks versions, pending migrations, Oban, required configuration, the
  admin's BrandoJS, image configs, module versions, the sitemap and
  robots.txt, the identity behind JSON-LD, alt text, and calls to deprecated
  Brando functions in `lib/`, plus any checks the application registers
  (see `Brando.Doctor`).

  Nothing is changed. The application starts without its web server and with
  Oban's queues stopped, so no job runs while the doctor looks.

    * `--verbose` lists what each check found.
    * `--json` prints the report as JSON, for scripts.
    * `--strict` fails on warnings too.
    * `--offline` does not ask Brando's git remote for its latest commit.

  The header and the Versions check name where Brando came from: a git commit
  and branch, Hex, a local path, or this checkout. For a git branch, the
  doctor runs `git ls-remote` (at most three seconds, and silent when it
  fails) and notes when the branch has moved past the locked commit.

  Exits with status 1 when a check finds an error (or a warning, with
  `--strict`), so CI can run it. See the [System check guide](doctor.md).
  """

  use Mix.Task

  alias Brando.Doctor
  alias Brando.Doctor.Report

  @switches [verbose: :boolean, json: :boolean, strict: :boolean, offline: :boolean]
  @aliases [v: :verbose]

  @impl Mix.Task
  def run(args) do
    {opts, _positional} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    oban = Mix.Brando.start_quietly()
    Gettext.put_locale(Brando.Gettext, "en")

    results = Doctor.run(mode: :mix, oban: oban, locale: "en", source?: true, offline?: opts[:offline] == true)
    versions = Doctor.versions()

    if opts[:json] do
      Mix.shell().info(results |> Report.json(versions) |> Jason.encode!(pretty: true))
    else
      Mix.shell().info(Report.text(results, versions, verbose: opts[:verbose]))
    end

    if Doctor.exit_status(results, opts[:strict] == true) == 1, do: exit({:shutdown, 1})
  end
end
