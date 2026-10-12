defmodule Mix.Tasks.Brando.Entries.Resave do
  use Mix.Task

  alias IO.ANSI

  @shortdoc "Re-save all entries"

  @moduledoc """
  Re-save all entries

      mix brando.entries.resave
      mix brando.entries.resave --yes

  Re-save entries for specific blueprint

      mix brando.entries.resave MyApp.Projects.Project

  Options:

    * `--yes` (or `--force`) - Skip the confirmation prompt. Without it and
      without a terminal to answer on, the task does nothing and exits
      non-zero.

  """
  @spec run(any) :: no_return
  def run(args) do
    {opts, rest} =
      Mix.Brando.parse_options!("brando.entries.resave", args, [yes: :boolean, force: :boolean],
        aliases: [y: :yes],
        max_positional: 1
      )

    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    ------------------------------
    % Brando Resave Entries
    ------------------------------
    """)

    case rest do
      [] -> resave_all(opts)
      [blueprint_binary] -> resave_one(blueprint_binary)
    end
  end

  defp resave_all(opts) do
    blueprints =
      ([Brando.Pages.Fragment] ++
         Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page])
      |> Enum.reject(&embedded?/1)

    Mix.shell().info([:yellow, "\n==> Blueprint schemas that will be resaved:\n\n"])

    for blueprint <- blueprints do
      Mix.shell().info([:green, "    * #{inspect(blueprint, pretty: true)}"])
    end

    if Mix.Brando.confirm?("\n\nProceed?", opts) do
      for blueprint <- blueprints, blueprint.__has_identifier__() do
        resave_entries(blueprint)
      end

      report_stale_config_targets()
      Mix.shell().info([:green, "\n==> Done.\n"])
    else
      Mix.shell().info("Nothing was done.")
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
      report_stale_config_targets()
      Mix.shell().info([:green, "\n==> Done.\n"])
    end
  end

  # Rendering falls back to the default image config for images whose
  # config target no longer resolves; one line per target says how many.
  defp report_stale_config_targets do
    stale = Brando.Images.Processing.stale_config_targets()

    if stale != %{} do
      Mix.shell().info([:yellow, "\n==> Images with a config target that no longer resolves:\n"])

      for {target, count} <- Enum.sort(stale) do
        Mix.shell().info("    * " <> Brando.Images.ConfigResolver.stale_target_message(target, count))
      end
    end
  end

  # Embedded Blueprints live inside their parent's column: no table, no
  # `list_<plural>/1` on any context. Walking them raises UndefinedFunctionError.
  defp embedded?(blueprint_module), do: Brando.Blueprint.embedded?(blueprint_module)

  defp resave_entries(blueprint_module) do
    context = blueprint_module.__modules__().context
    singular = blueprint_module.__naming__().singular
    plural = blueprint_module.__naming__().plural
    preloads = Brando.Blueprint.preloads_for(blueprint_module)
    {:ok, entries} = apply(context, :"list_#{plural}", [%{order: "asc id", preload: preloads}])

    Mix.shell().info([:green, "\n==> Resaving #{singular} entries\n"])

    for entry <- entries do
      title = blueprint_module.__identifier__(entry, skip_cover: true).title

      # IO.ANSI.format/1 drops the colours when stdout is not a terminal.
      IO.write(
        ANSI.format([
          "* [",
          :blue,
          "#{singular}",
          :reset,
          ":",
          :blue,
          "#{entry.id}",
          :reset,
          "] → ",
          :blue,
          title,
          :reset,
          " ... "
        ])
      )

      changeset =
        entry
        |> Ecto.Changeset.change()
        |> Brando.Content.Blocks.render_all_block_fields_and_add_to_changeset(blueprint_module, entry)
        |> Ecto.Changeset.force_change(:updated_at, entry.updated_at)

      case Brando.Repo.update(changeset, force: true) do
        {:ok, _} ->
          IO.write(ANSI.format([:green, "done!\n"]))

        {:error, _} ->
          IO.write(ANSI.format([:red, "failed!\n"]))
      end
    end
  end
end
