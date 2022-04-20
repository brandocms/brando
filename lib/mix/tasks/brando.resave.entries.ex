defmodule Mix.Tasks.Brando.Resave.Entries do
  use Mix.Task

  @shortdoc "Re-save all entries"

  @moduledoc """
  Re-save all entries

      mix brando.resave.entries

  Re-save entries for specific blueprint

      mix brando.resave.entries MyApp.Projects.Project

  """
  @spec run(any) :: no_return
  def run([]) do
    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    ------------------------------
    % Brando Resave Entries
    ------------------------------
    """)

    blueprints = Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page, Brando.Pages.Fragment]

    for blueprint <- blueprints do
      resave_entries(blueprint)
    end

    Mix.shell().info([:green, "\n==> Done.\n"])
  end

  def run([blueprint_binary]) do
    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    ------------------------------
    % Brando Resave Entries
    ------------------------------
    """)

    blueprint = Module.concat([blueprint_binary])
    resave_entries(blueprint)
    Mix.shell().info([:green, "\n==> Done.\n"])
  end

  defp resave_entries(blueprint) do
    context = blueprint.__modules__().context
    singular = blueprint.__naming__().singular
    plural = blueprint.__naming__().plural
    {:ok, entries} = apply(context, :"list_#{plural}", [%{order: "asc id"}])

    Mix.shell().info([:green, "\n==> Resaving #{singular} entries\n"])

    for entry <- entries do
      IO.write([
        "* [#{singular}:#{entry.id}] → #{blueprint.__identifier__(entry).title} ... "
      ])

      changeset = Ecto.Changeset.change(entry)

      case Brando.repo().update(changeset, force: true) do
        {:ok, _} ->
          IO.write([IO.ANSI.green(), "done!\n", IO.ANSI.reset()])

        {:error, _} ->
          IO.write([IO.ANSI.red(), "failed!\n", IO.ANSI.reset()])
      end
    end
  end
end
