if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Files do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    @doc """
    Plans a new owned file, preserving an existing equivalent file on reruns.

    Different contents are a blocking issue, including with --yes. Shared files
    must instead be patched through Igniter's AST helpers. Both pending files
    from composed tasks and files already on disk participate in the check.
    """
    def create(igniter, path, contents) do
      cond do
        not String.valid?(contents) or String.contains?(contents, <<0>>) ->
          Igniter.add_issue(
            igniter,
            "#{path} is binary. Igniter's text writer cannot safely write binary assets; use the deferred asset copier."
          )

        Path.type(path) != :relative or ".." in Path.split(path) ->
          Igniter.add_issue(igniter, "Generated file paths must stay inside the project: #{path}")

        Igniter.exists?(igniter, path) ->
          igniter = Igniter.include_existing_file(igniter, path)
          current = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

          if equivalent?(path, current, contents) do
            igniter
          else
            Igniter.add_issue(
              igniter,
              "#{path} already contains different content. Review or move it before generating this file."
            )
          end

        true ->
          create_new(igniter, path, contents)
      end
    end

    # Igniter formats each new Elixir file inside a snapshot of the project's
    # evaluated config, which costs more than the formatting itself: an install
    # creates hundreds of files. Only formatter plugins can read that config, so
    # a file whose formatter has none is formatted directly, with the same
    # formatter Igniter would use. `Igniter.format/2` with no paths does the
    # rest of Igniter's preparation (reading the config and formatter files).
    defp create_new(igniter, path, contents) do
      with true <- Path.extname(path) in Rewrite.Source.Ex.extensions(),
           false <- Map.get(igniter.assigns, :brando_format_each_file, false),
           igniter = Igniter.format(igniter, []),
           {:ok, formatted} <- format_without_plugins(igniter, path, contents) do
        Igniter.create_new_file(igniter, path, formatted, format?: false)
      else
        _ -> Igniter.create_new_file(igniter, path, contents)
      end
    end

    defp format_without_plugins(igniter, path, contents) do
      dot_formatter = Rewrite.dot_formatter(igniter.rewrite)

      if plugins?(dot_formatter_for_file(dot_formatter, path)) do
        :plugins
      else
        with {:ok, source} <- path |> source(contents) |> Rewrite.Source.format(dot_formatter: dot_formatter) do
          {:ok, Rewrite.Source.get(source, :content)}
        end
      end
    end

    defp source(path, contents), do: Rewrite.Source.Ex.from_string(contents, path: path)

    defp plugins?(dot_formatter), do: Enum.any?(List.wrap(dot_formatter.plugins) ++ List.wrap(dot_formatter.sigils))

    # The nearest formatter in the tree whose directory contains the file, as
    # Rewrite.DotFormatter picks it.
    defp dot_formatter_for_file(dot_formatter, path) do
      Enum.find_value(List.wrap(dot_formatter.subs), dot_formatter, fn %{path: sub_path} = sub ->
        size = byte_size(sub_path)

        case path do
          <<^sub_path::binary-size(^size), separator, _::binary>> when separator in [?/, ?\\] ->
            dot_formatter_for_file(sub, path)

          _ ->
            nil
        end
      end)
    end

    defp equivalent?(_path, contents, contents), do: true

    defp equivalent?(path, current, contents) do
      if Path.extname(path) in [".ex", ".exs"] do
        with {:ok, left} <- Sourceror.parse_string(current),
             {:ok, right} <- Sourceror.parse_string(contents) do
          Sourceror.strip_meta(left) == Sourceror.strip_meta(right)
        else
          _ -> false
        end
      else
        String.trim_trailing(current) == String.trim_trailing(contents)
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.Files do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
