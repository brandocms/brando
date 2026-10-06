defmodule Mix.Tasks.Brando.Migrations.Check do
  @shortdoc "Lists pending Brando migrations that differ from their templates"

  @moduledoc """
  Lists copies of Brando's upgrade migrations that have not run yet and no
  longer match Brando's templates (see `Brando.Migration.TemplateDrift`):

      mix brando.migrations.check
      mix brando.migrations.check --update

  Run it against a copy of the production database before replaying an
  upgrade. `--update` replaces each outdated copy with its template; review
  the diff, since a copy may have been edited on purpose. A renumbered copy
  is only listed: delete it once `mix brando.gen.migrations` has copied the
  template under its new number.

  Exits with status 1 while anything is left to act on.
  """

  use Mix.Task

  alias Brando.Migration.TemplateDrift

  @switches [update: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _positional} = OptionParser.parse!(args, strict: @switches)
    Mix.Task.run("app.config")

    findings =
      Enum.flat_map(Mix.Ecto.parse_repo([]), fn repo ->
        # The source tree, not the copy under _build, so --update edits the
        # files that get committed
        directory = Path.join(Mix.EctoSQL.source_repo_priv(repo), "migrations")
        {:ok, findings, _apps} = Ecto.Migrator.with_repo(repo, &TemplateDrift.pending(&1, directory))
        findings
      end)

    remaining =
      if opts[:update] do
        Enum.reject(findings, &update/1)
      else
        Enum.each(findings, &report/1)
        findings
      end

    cond do
      findings == [] ->
        Mix.shell().info("No pending Brando migration differs from its template.")

      remaining == [] ->
        Mix.shell().info("\nUpdated #{length(findings)} migration(s). Review the diff before committing.")

      true ->
        if !opts[:update],
          do: Mix.shell().info("\nRun with --update to replace the outdated copies with their templates.")

        exit({:shutdown, 1})
    end
  end

  defp update({:outdated, path, _template} = finding) do
    TemplateDrift.update!(finding)
    Mix.shell().info([:green, "* updated ", :reset, Path.relative_to_cwd(path)])
    true
  end

  defp update(finding) do
    report(finding)
    false
  end

  defp report({:outdated, path, template}) do
    Mix.shell().info([
      :yellow,
      "* outdated ",
      :reset,
      "#{Path.relative_to_cwd(path)} differs from #{Path.basename(template)}"
    ])
  end

  defp report({:renumbered, path, template}) do
    Mix.shell().info([
      :yellow,
      "* renumbered ",
      :reset,
      "#{Path.relative_to_cwd(path)} is now #{Path.basename(template)}; delete it once that is copied"
    ])
  end
end
