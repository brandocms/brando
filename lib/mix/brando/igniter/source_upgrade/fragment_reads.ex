if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.FragmentReads do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # A fragment's `html` became `rendered_blocks` in 0.54. Templates mostly
    # read fragments out of the map `Brando.Pages.get_fragments/1` returns,
    # which `Brando.Plug.Fragment` assigns (`@partials["footer"].html`), so
    # the schema-template rewrite, which matches `entry.html`, never sees them.
    #
    # A map read is rewritten when the map is known to hold fragments: an
    # assign that `plug Brando.Plug.Fragment, as: …` names, or that a module
    # assigns from a variable `get_fragments` bound; or that variable, in the
    # module that binds it. Other `…].html` reads are listed.

    alias Mix.Brando.Igniter.TemplateCode
    alias Rewrite.Source

    @extensions ~w(.ex .heex .eex .leex)
    @limit 50

    @plug_as ~r/\bplug[\s(]+(?:Brando\.)?Plug\.Fragment\b[^\n]*?\bas:\s*:(\w+)/
    @bound_ok ~r/\{:ok,\s*([a-z_]\w*)\}\s*(?:<-|=)[^\n]*\bget_fragments\(/
    @bound ~r/(?<![\w.:])([a-z_]\w*)\s*=\s*(?:[A-Z][\w.]*\.)?get_fragments\(/
    @map_read ~r/\]\.html(?![\w(?])/

    @doc """
    Rewrites fragment map reads of `html` to `rendered_blocks`, notes them
    with file and line, and lists the other map reads of `html`.
    """
    def rewrite(igniter) do
      igniter = Igniter.include_glob(igniter, "lib/**/*.{ex,heex,eex,leex}")
      sources = sources(igniter)
      assigns = fragment_assigns(sources)

      {igniter, rewritten} =
        Enum.reduce(sources, {igniter, []}, fn {path, content}, {igniter, rewritten} ->
          names = Enum.uniq(Enum.map(assigns, &"@#{&1}") ++ bound_variables(content))
          {updated, lines} = rewrite_reads(content, path, names)

          if lines == [] do
            {igniter, rewritten}
          else
            igniter = Igniter.update_file(igniter, path, &Source.update(&1, :content, updated))
            text = String.split(updated, "\n")
            {igniter, rewritten ++ Enum.map(lines, &"#{path}:#{&1}: #{text |> Enum.at(&1 - 1) |> String.trim()}")}
          end
        end)

      remaining =
        for {path, content} <- sources(igniter),
            code? = TemplateCode.code?(content, path),
            {line, number, offset} <- lines(content),
            Regex.scan(@map_read, line, return: :index) |> Enum.any?(fn [{start, _}] -> code?.(offset + start) end),
            do: "#{path}:#{number}: #{String.trim(line)}"

      igniter
      |> notice(rewritten)
      |> warning(remaining)
    end

    defp sources(igniter) do
      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
      |> Enum.filter(fn {path, _content} -> String.starts_with?(path, "lib/") and Path.extname(path) in @extensions end)
      |> Enum.sort()
    end

    # The assigns that hold a fragments map anywhere in the application.
    defp fragment_assigns(sources) do
      Enum.flat_map(sources, fn {_path, content} ->
        plugged = for [_, name] <- Regex.scan(@plug_as, content), do: name

        assigned =
          for variable <- bound_variables(content),
              pattern =
                ~r/assign\(\s*(?:[a-z_]\w*\s*,\s*)?:([a-z_]\w*)\s*,\s*#{variable}(?![\w.\[])|\b([a-z_]\w*):\s*#{variable}(?![\w.\[])/,
              match <- Regex.scan(pattern, content),
              name = match |> Enum.drop(1) |> Enum.find(&(&1 != "")),
              do: name

        plugged ++ assigned
      end)
      |> Enum.uniq()
    end

    defp bound_variables(content) do
      for regex <- [@bound_ok, @bound], [_, variable] <- Regex.scan(regex, content), uniq: true, do: variable
    end

    # `{content, [line]}`: the content with each `<name>[…].html` read in code
    # pointed at `rendered_blocks`, and the lines it changed.
    defp rewrite_reads(_content, _path, []), do: {nil, []}

    defp rewrite_reads(content, path, names) do
      code? = TemplateCode.code?(content, path)
      alternatives = Enum.map_join(names, "|", &Regex.escape/1)
      read = ~r/(?<![\w.@])(?:#{alternatives})\[[^\[\]\n]*\]\.(html)(?![\w(?])/

      reads =
        read
        |> Regex.scan(content, return: :index)
        |> Enum.filter(fn [{start, _length} | _] -> code?.(start) end)

      updated =
        reads
        |> Enum.reverse()
        |> Enum.reduce(content, fn [_read, {start, length}], content ->
          binary_part(content, 0, start) <>
            "rendered_blocks" <> binary_part(content, start + length, byte_size(content) - start - length)
        end)

      lines =
        reads
        |> Enum.map(fn [{start, _length} | _] -> line_number(content, start) end)
        |> Enum.uniq()

      {updated, lines}
    end

    defp line_number(content, offset), do: content |> binary_part(0, offset) |> String.split("\n") |> length()

    # `{line, number, offset}` for each line of `content`.
    defp lines(content) do
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map_reduce(0, fn {line, number}, offset -> {{line, number, offset}, offset + byte_size(line) + 1} end)
      |> elem(0)
    end

    defp notice(igniter, []), do: igniter

    defp notice(igniter, rewritten) do
      Igniter.add_notice(igniter, """
      A fragment's `html` is `rendered_blocks` since 0.54. These reads of
      fragments from a `get_fragments` map (`Brando.Plug.Fragment` assigns
      one) now read `rendered_blocks`:

      #{format(rewritten)}
      """)
    end

    defp warning(igniter, []), do: igniter

    defp warning(igniter, remaining) do
      Igniter.add_warning(igniter, """
      These lines read `html` from a value in a map. If the map holds page
      fragments (from `Brando.Pages.get_fragments/1`), read `rendered_blocks`
      instead: a fragment has no `html` since 0.54, and the page fails with a
      KeyError. The task could not tell where the map comes from:

      #{format(remaining)}
      """)
    end

    defp format(findings) do
      shown = Enum.take(findings, @limit)
      more = length(findings) - length(shown)
      Enum.map_join(shown, "\n", &("  " <> &1)) <> if(more > 0, do: "\n  … and #{more} more", else: "")
    end
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.FragmentReads do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
