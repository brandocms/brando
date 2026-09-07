if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Files do
    @doc false
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
          Igniter.create_new_file(igniter, path, contents)
      end
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
