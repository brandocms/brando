if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.EntriesReads do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Since 0.54 an `:entries` relation (`relation :related_entries, :entries`)
    # holds join rows, each with the picked entry's identifier, where it held
    # the identifiers. Code that read `& &1.entry_id` off it gets a KeyError.
    # Which entries a site loads, and how, is its own, so this lists the reads.

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Mix.Brando.Igniter.TemplateCode
    alias Rewrite.Source
    alias Sourceror.Zipper

    @extensions ~w(.ex .heex .eex .leex)
    @limit 50

    @doc """
    Warns, with file and line, about each read of an `:entries` relation of
    the application's Blueprints in Elixir code, except on lines that already
    go through `.identifier`.
    """
    def warn(igniter) do
      {igniter, names} = relation_names(igniter)

      case names do
        [] ->
          igniter

        names ->
          igniter = Igniter.include_glob(igniter, "lib/**/*.{ex,heex,eex,leex}")

          read =
            ~r/(?<![\w.:"'\/@])@?[a-z_]\w*(?:\.[a-z_]\w*)*\.(?:#{Enum.map_join(names, "|", &Regex.escape/1)})(?![\w(?:])/

          igniter
          |> findings(read)
          |> case do
            [] -> igniter
            findings -> Igniter.add_warning(igniter, warning(names, findings))
          end
      end
    end

    defp relation_names(igniter) do
      {igniter, blueprints} = SourceUpgrade.find_blueprints(igniter)

      Enum.reduce(blueprints, {igniter, []}, fn module, {igniter, names} ->
        {:ok, {igniter, _source, zipper}} = ProjectModule.find_module(igniter, module)

        found =
          for relation <- Common.find_all(Zipper.subtree(zipper), &CodeFunction.function_call?(&1, :relation, [2, 3])),
              {:relation, _, [name, type | _]} <- [relation |> Common.maybe_move_to_single_child_block() |> Zipper.node()],
              literal(type) == :entries,
              name = literal(name),
              is_atom(name) and not is_nil(name),
              do: Atom.to_string(name)

        {igniter, Enum.uniq(names ++ found)}
      end)
    end

    defp findings(igniter, read) do
      for source <- Rewrite.sources(igniter.rewrite),
          path = Source.get(source, :path),
          String.starts_with?(path, "lib/") and Path.extname(path) in @extensions,
          content = Source.get(source, :content),
          code? = TemplateCode.code?(content, path),
          {line, number, offset} <- lines(content),
          not String.contains?(line, ".identifier"),
          Enum.any?(Regex.scan(read, line, return: :index), fn [{start, _length}] -> code?.(offset + start) end) do
        "#{path}:#{number}: #{String.trim(line)}"
      end
      |> Enum.sort()
    end

    # `{line, number, offset}` for each line of `content`.
    defp lines(content) do
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map_reduce(0, fn {line, number}, offset -> {{line, number, offset}, offset + byte_size(line) + 1} end)
      |> elem(0)
    end

    defp warning(names, findings) do
      shown = Enum.take(findings, @limit)
      more = length(findings) - length(shown)
      relations = Enum.map_join(names, ", ", &"`#{&1}`")

      """
      These lines read an `:entries` relation (#{relations}). Since 0.54 it
      holds join rows, each with the picked entry's identifier and its
      `sequence`, not the identifiers, so `& &1.entry_id` fails with a
      KeyError:

      #{Enum.map_join(shown, "\n", &("  " <> &1))}#{if more > 0, do: "\n  … and #{more} more", else: ""}

      Preload the identifiers through the join rows, then read them there:

          project = Brando.Repo.preload(project, related_entries: :identifier)
          ids = Enum.map(project.related_entries, & &1.identifier.entry_id)

      The rows come in the order the editor picked them. A list query on
      `ids` returns entries in its own order; sort them by `ids` to keep the
      editor's, or load them with
      `Brando.Content.get_entries_from_identifiers(identifiers, %{preload: […]})`.
      """
    end

    defp literal({:__block__, _meta, [value]}), do: value
    defp literal(value), do: value
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.EntriesReads do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
