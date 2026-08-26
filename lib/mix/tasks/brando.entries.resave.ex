defmodule Mix.Tasks.Brando.Entries.Resave do
  use Mix.Task

  @shortdoc "Re-save all entries"

  @moduledoc """
  Re-save all entries

      mix brando.entries.resave
      mix brando.entries.resave --force

  Re-save entries for specific blueprint

      mix brando.entries.resave MyApp.Projects.Project

  Options:

    * `--force` - Skip confirmation prompt

  """
  @spec run(any) :: no_return
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [force: :boolean])
    force? = Keyword.get(opts, :force, false)

    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    ------------------------------
    % Brando Resave Entries
    ------------------------------
    """)

    case rest do
      [] -> resave_all(force?)
      [blueprint_binary] -> resave_one(blueprint_binary)
    end
  end

  defp resave_all(force?) do
    blueprints =
      ([Brando.Pages.Fragment] ++
         Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page])
      |> Enum.reject(&embedded?/1)

    Mix.shell().info([:yellow, "\n==> Blueprint schemas that will be resaved:\n\n"])

    for blueprint <- blueprints do
      Mix.shell().info([:green, "    * #{inspect(blueprint, pretty: true)}"])
    end

    if force? or Mix.shell().yes?("\n\nProceed?") do
      for blueprint <- blueprints do
        if blueprint.__has_identifier__() do
          resave_entries(blueprint)
        end
      end

      Mix.shell().info([:green, "\n==> Done.\n"])
    end
  end

  defp resave_one(blueprint_binary) do
    blueprint_module = Module.concat([blueprint_binary])

    if embedded?(blueprint_module) do
      Mix.raise("""
      #{inspect(blueprint_module)} declares `data_layer :embedded`.

      Embedded Blueprints have no table and no context list function of their own —
      they are re-saved with the entry that embeds them.\
      """)
    end

    if blueprint_module.__has_identifier__() do
      resave_entries(blueprint_module)
      Mix.shell().info([:green, "\n==> Done.\n"])
    end
  end

  # Embedded Blueprints live inside their parent's column: no table, no
  # `list_<plural>/1` on any context. Walking them raises UndefinedFunctionError.
  defp embedded?(blueprint_module) do
    function_exported?(blueprint_module, :__data_layer__, 0) and
      blueprint_module.__data_layer__() == :embedded
  end

  defp resave_entries(blueprint_module) do
    context = blueprint_module.__modules__().context
    singular = blueprint_module.__naming__().singular
    plural = blueprint_module.__naming__().plural
    preloads = Brando.Blueprint.preloads_for(blueprint_module)
    {:ok, entries} = apply(context, :"list_#{plural}", [%{order: "asc id", preload: preloads}])

    Mix.shell().info([:green, "\n==> Resaving #{singular} entries\n"])

    for entry <- entries do
      title = blueprint_module.__identifier__(entry, skip_cover: true).title

      IO.write([
        "* [",
        IO.ANSI.blue(),
        "#{singular}",
        IO.ANSI.reset(),
        ":",
        IO.ANSI.blue(),
        "#{entry.id}",
        IO.ANSI.reset(),
        "] → ",
        IO.ANSI.blue(),
        title,
        IO.ANSI.reset(),
        " ... "
      ])

      changeset =
        entry
        |> Ecto.Changeset.change()
        |> Brando.Content.Blocks.render_all_block_fields_and_add_to_changeset(blueprint_module, entry)
        |> Ecto.Changeset.force_change(:updated_at, entry.updated_at)

      case Brando.Repo.update(changeset, force: true) do
        {:ok, _} ->
          IO.write([IO.ANSI.green(), "done!\n", IO.ANSI.reset()])

        {:error, _} ->
          IO.write([IO.ANSI.red(), "failed!\n", IO.ANSI.reset()])
      end
    end
  end
end
