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
    # A map read is rewritten when the map is known to hold fragments: a
    # variable `get_fragments` bound, in the function that binds it, or an
    # assign that `plug Brando.Plug.Fragment, as: …` names or a function
    # assigns from such a variable, and that nothing assigns anything else.
    # Other `…].html` reads are listed.

    alias Mix.Brando.Igniter.SourceUpgrade.FragmentSources
    alias Mix.Brando.Igniter.TemplateCode
    alias Rewrite.Source

    @extensions ~w(.ex .heex .eex .leex)
    @limit 50

    @plug_as ~r/\bplug[\s(]+(?:Brando\.)?Plug\.Fragment\b[^\n]*?\bas:\s*:(\w+)/
    # A map read of `html`, from the start of the expression, where the
    # Elixir code check looks for code in a module; templates also get the
    # bare `].html`, for maps read off a call.
    @map_read ~r/(?<![\w.@])@?[a-z_][\w.]*\[[^\[\]\n]*\]\.html(?![\w(?])/
    @bare_map_read ~r/\]\.html(?![\w(?])/

    @doc """
    Rewrites fragment map reads of `html` to `rendered_blocks`, notes them
    with file and line, and lists the other map reads of `html`.
    """
    def rewrite(igniter) do
      igniter = Igniter.include_glob(igniter, "lib/**/*.{ex,heex,eex,leex}")

      sources =
        Enum.map(sources(igniter), fn {path, content} -> {path, content, FragmentSources.analyze(path, content)} end)

      assigns = sources |> fragment_assigns() |> Enum.map(&"@#{&1}")

      {igniter, rewritten} =
        Enum.reduce(sources, {igniter, []}, fn {path, content, %{bindings: bindings}}, {igniter, rewritten} ->
          {updated, lines} = rewrite_reads(content, path, assigns, bindings)

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
            map_read?(path, line, &code?.(offset + &1)),
            do: "#{path}:#{number}: #{String.trim(line)}"

      igniter
      |> notice(rewritten)
      |> warning(remaining)
    end

    defp map_read?(path, line, code_at?) do
      regexes = if Path.extname(path) == ".ex", do: [@map_read], else: [@map_read, @bare_map_read]

      Enum.any?(regexes, fn regex ->
        Enum.any?(Regex.scan(regex, line, return: :index), fn [{start, _}] -> code_at?.(start) end)
      end)
    end

    defp sources(igniter) do
      igniter.rewrite
      |> Rewrite.sources()
      |> Enum.map(&{Source.get(&1, :path), Source.get(&1, :content)})
      |> Enum.filter(fn {path, _content} -> String.starts_with?(path, "lib/") and Path.extname(path) in @extensions end)
      |> Enum.sort()
    end

    # The assigns that hold a fragments map: those the plug names or a
    # function assigns from a fragments variable, unless something assigns
    # them other data too.
    defp fragment_assigns(sources) do
      plugged = for {_path, content, _analysis} <- sources, [_, name] <- Regex.scan(@plug_as, content), do: name
      sites = Enum.flat_map(sources, fn {_path, _content, analysis} -> analysis.sites end)
      assigned = for {name, true} <- sites, do: name
      mixed = for {name, false} <- sites, do: name

      Enum.uniq(plugged ++ assigned) -- mixed
    end

    # `{content, [line]}`: the content with each `<name>[…].html` read of a
    # fragments map in code pointed at `rendered_blocks`, and the lines it
    # changed.
    defp rewrite_reads(content, path, assigns, bindings) do
      variables = bindings |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

      case assigns ++ variables do
        [] -> {content, []}
        names -> rewrite_reads(content, path, names, assigns, bindings)
      end
    end

    defp rewrite_reads(content, path, names, assigns, bindings) do
      code? = TemplateCode.code?(content, path)
      alternatives = Enum.map_join(names, "|", &Regex.escape/1)
      read = ~r/(?<![\w.@])(#{alternatives})\[[^\[\]\n]*\]\.(html)(?![\w(?])/

      reads =
        read
        |> Regex.scan(content, return: :index)
        |> Enum.filter(fn [{start, _length}, {name_start, name_length} | _] ->
          name = binary_part(content, name_start, name_length)

          code?.(start) and
            (name in assigns or FragmentSources.bound?(bindings, name, line_number(content, start)))
        end)

      updated =
        reads
        |> Enum.reverse()
        |> Enum.reduce(content, fn [_read, _name, {start, length}], content ->
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
