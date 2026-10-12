if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.VideoMarkup do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Finds the application's own front-end scripts that read a file video's
    # `data-src` from the `<video>` element, as Brando's markup before 0.55 put
    # it there. Warning only: the right fix depends on the script.

    @extensions ~w(.js .mjs .svelte .ts)
    # Dependencies, build output, vendored copies, and Brando's own admin.
    @skipped_directories ~w(node_modules dist build vendor .yalc)
    @limit 50

    @data_src_read ~r/getAttribute\(\s*(['"`])data-src\1\s*\)|\.dataset\.src\b/

    @doc """
    Warns about lines under `assets/` (except `assets/backend`) that read
    `data-src` in a script that also handles videos.
    """
    def warn_video_data_src_reads(igniter) do
      findings =
        for {path, content} <- igniter |> asset_scripts() |> Enum.sort(),
            content =~ ~r/video/i,
            {line, number} <- content |> String.split("\n") |> Enum.with_index(1),
            single_read?(line),
            do: "#{path}:#{number}: #{String.trim(line)}"

      case findings do
        [] -> igniter
        findings -> Igniter.add_warning(igniter, warning(findings))
      end
    end

    # A line that reads it twice, or from the closest wrapper, already falls back.
    defp single_read?(line) do
      length(Regex.scan(@data_src_read, line)) == 1 and not String.contains?(line, "closest(")
    end

    defp warning(findings) do
      shown = Enum.take(findings, @limit)
      more = length(findings) - length(shown)

      """
      These front-end scripts read `data-src`, and handle videos:

      #{Enum.map_join(shown, "\n", &("  " <> &1))}#{if more > 0, do: "\n  … and #{more} more", else: ""}

      Since 0.55 a file video's `data-src` sits on the `[data-smart-video]`
      wrapper. The `<video>` inside carries `data-src` only when the video
      preloads, and `src` otherwise, so code that reads `data-src` from the
      `<video>` gets `null` (a video with `src="null"` does not play). Read it
      from the wrapper, `el.closest('[data-smart-video]').dataset.src`, or fall
      back to it. File videos converted from the old block editor stay muted,
      as the old markup always rendered them.
      """
    end

    defp asset_scripts(igniter) do
      if igniter.assigns[:test_mode?] do
        for {path, content} <- Map.get(igniter.assigns, :test_files, %{}), asset_script?(path), do: {path, content}
      else
        for path <- walk("assets"), asset_script?(path), {:ok, content} <- [File.read(path)], do: {path, content}
      end
    end

    defp asset_script?(path) do
      segments = Path.split(path)

      match?(["assets" | _], segments) and not match?(["assets", "backend" | _], segments) and
        Path.extname(path) in @extensions and not String.ends_with?(path, ".min.js") and
        not Enum.any?(segments, &skipped_directory?/1)
    end

    defp skipped_directory?(segment), do: segment in @skipped_directories or String.starts_with?(segment, ".")

    defp walk(directory) do
      case File.ls(directory) do
        {:ok, names} -> Enum.flat_map(names, &walk_entry(Path.join(directory, &1), &1))
        {:error, _reason} -> []
      end
    end

    defp walk_entry(path, name) do
      cond do
        File.dir?(path) and not skipped_directory?(name) and path != "assets/backend" -> walk(path)
        File.regular?(path) -> [path]
        true -> []
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.VideoMarkup do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
