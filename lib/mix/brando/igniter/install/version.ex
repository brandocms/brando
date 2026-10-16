if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Version do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Module, as: CodeModule
    alias Igniter.Project.MixProject
    alias Rewrite.Source

    @attribute ~s[@version "VERSION" |> File.read!() |> String.trim()]
    # COPY sources that bring VERSION into an image.
    @context_copies ["VERSION", ".", "./"]

    @doc """
    Keeps the application's version in a `VERSION` file that `mix.exs` reads.

    Florist reads the version of the release it builds from `VERSION`, falling
    back to a literal `@version "..."` in `mix.exs`; phx.new writes neither, only
    an inline `version: "0.1.0"`. A literal version, inline or in `@version`,
    moves to a new `VERSION` file. An existing `VERSION` is kept: `mix.exs` is
    pointed at it when its literal version agrees, and a notice reports a
    disagreement. A `mix.exs` that already reads `VERSION`, or computes its
    version some other way, is left unchanged.

    When `mix.exs` reads `VERSION`, each Dockerfile stage that copies `mix.exs`
    copies `VERSION` after it, so the image's mix commands can evaluate it; a
    Dockerfile this cannot follow, or a `.dockerignore` that may exclude
    `VERSION`, gets a notice.
    """
    def plan(igniter) do
      {igniter, file} = version_file(igniter)

      case {mix_version(igniter), file} do
        {:reads_file, _} -> docker(igniter)
        {{:literal, version, at}, nil} -> igniter |> create(version) |> read_file(at) |> docker()
        {{:literal, version, at}, version} -> igniter |> read_file(at) |> docker()
        {{:literal, version, _at}, file} -> disagreement(igniter, version, file)
        {:other, _} -> other_notice(igniter, file)
      end
    end

    # The Docker build evaluates mix.exs (phx.gen.release's Dockerfile runs
    # `mix deps.get` after `COPY mix.exs mix.lock ./`), so every stage that
    # copies mix.exs needs VERSION next to it.
    defp docker(igniter) do
      if Igniter.exists?(igniter, "Dockerfile") do
        igniter = Igniter.include_existing_file(igniter, "Dockerfile")
        current = igniter.rewrite |> Rewrite.source!("Dockerfile") |> Source.get(:content)

        {contents, recognized?} = copy_version(current)

        igniter =
          if contents == current,
            do: igniter,
            else: Igniter.update_file(igniter, "Dockerfile", &Source.update(&1, :content, contents))

        igniter =
          if recognized?,
            do: igniter,
            else:
              Igniter.add_notice(
                igniter,
                docker_notice("The Dockerfile does not copy mix.exs in a way this installer recognizes")
              )

        dockerignore(igniter)
      else
        igniter
      end
    end

    defp docker_notice(reason) do
      """
      #{reason}. mix.exs now reads VERSION, so the Docker build needs it next to mix.exs:
        COPY VERSION ./
      """
    end

    # Lines are kept as they are; a stage that copies mix.exs and not VERSION
    # (or the whole build context) gets `COPY VERSION <dest>` after that line.
    # Not recognized when nothing copies mix.exs, VERSION or the context, or a
    # stage copies mix.exs in a form `copy/1` does not read.
    defp copy_version(contents) do
      stages = contents |> String.split("\n") |> stages()
      copies = Enum.map(stages, fn lines -> Enum.map(lines, &copy/1) end)
      copied? = Enum.any?(List.flatten(copies), &copies_any?(&1, ["mix.exs" | @context_copies]))

      {stages |> Enum.zip_with(copies, &stage_with_version/2) |> Enum.join("\n"),
       copied? and not Enum.any?(Enum.zip(stages, copies), &unread_mix_copy?/1)}
    end

    defp unread_mix_copy?({lines, copies}) do
      not Enum.any?(copies, &copies_any?(&1, @context_copies)) and
        lines
        |> Enum.zip(copies)
        |> Enum.any?(fn {line, copy} ->
          copy == :skip and Regex.match?(~r/^\s*(COPY|ADD)\s(?!.*--from).*mix\.exs/i, line)
        end)
    end

    defp stages(lines) do
      lines
      |> Enum.reduce([], fn
        line, [] -> [[line]]
        line, [stage | rest] = stages -> if from?(line), do: [[line] | stages], else: [[line | stage] | rest]
      end)
      |> Enum.reverse()
      |> Enum.map(&Enum.reverse/1)
    end

    # Only a VERSION or context copy before the first RUN after the mix.exs
    # copy counts: that RUN (`mix deps.get`) is what first reads mix.exs.
    defp stage_with_version(lines, copies) do
      index = Enum.find_index(copies, &copies_any?(&1, ["mix.exs"]))

      if index && not Enum.any?(Enum.take(copies, first_run_after(lines, index)), &copies_any?(&1, @context_copies)) do
        {:copy, _sources, line_for} = Enum.at(copies, index)
        lines |> List.insert_at(index + 1, line_for.("VERSION")) |> Enum.join("\n")
      else
        Enum.join(lines, "\n")
      end
    end

    defp first_run_after(lines, index) do
      lines
      |> Enum.with_index()
      |> Enum.find_value(length(lines), fn {line, i} -> i > index and Regex.match?(~r/^\s*RUN\s/i, line) and i end)
    end

    defp copies_any?({:copy, sources, _line_for}, paths), do: Enum.any?(sources, &(&1 in paths))
    defp copies_any?(:skip, _paths), do: false

    defp from?(line), do: Regex.match?(~r/^\s*FROM\s/i, line)

    # `COPY [--chown=...] src... dest` on one line, from the build context,
    # with its sources less any leading "./", and a function that writes the
    # line for another source with the same flags and destination.
    defp copy(line) do
      with [_, indent, rest] <- Regex.run(~r/^(\s*)COPY\s+(.*?)\s*$/i, line),
           false <- String.ends_with?(rest, "\\") or String.starts_with?(rest, "["),
           {flags, paths} = rest |> String.split() |> Enum.split_while(&String.starts_with?(&1, "--")),
           false <- Enum.any?(flags, &String.starts_with?(&1, "--from")),
           [_, _ | _] <- paths do
        {sources, [dest]} = Enum.split(paths, -1)

        case directory(sources, dest) do
          nil -> :skip
          dir -> {:copy, Enum.map(sources, &normalize_source/1), &Enum.join([indent <> "COPY" | flags] ++ [&1, dir], " ")}
        end
      else
        _ -> :skip
      end
    end

    # The directory VERSION goes to. A destination ending in "/" (or "." for
    # the working directory) is one; a single source copied to a path that
    # names the same file goes to that path's directory. Anything else (a file
    # renamed on copy, or a variable whose shape is unknown) is not read, so
    # the stage gets a notice instead of a line that might overwrite mix.exs.
    defp directory(sources, dest) do
      cond do
        String.ends_with?(dest, "/") or dest in [".", "./"] or String.ends_with?(dest, "/.") -> dest
        match?([_], sources) and Path.basename(dest) == Path.basename(hd(sources)) -> Path.dirname(dest) <> "/"
        true -> nil
      end
    end

    defp normalize_source("./" <> source) when source != "", do: source
    defp normalize_source(source), do: source

    defp dockerignore(igniter) do
      if Igniter.exists?(igniter, ".dockerignore") do
        igniter = Igniter.include_existing_file(igniter, ".dockerignore")

        patterns =
          igniter.rewrite
          |> Rewrite.source!(".dockerignore")
          |> Source.get(:content)
          |> String.split("\n")
          |> Enum.map(&String.trim/1)

        # The last pattern matching VERSION decides, as in Docker.
        excluded? =
          patterns
          |> Enum.reverse()
          |> Enum.find_value(fn
            "!" <> pattern -> if excludes_version?(pattern), do: :kept
            pattern -> if excludes_version?(pattern), do: :excluded
          end) == :excluded

        if excluded?,
          do:
            Igniter.add_notice(igniter, docker_notice(".dockerignore may exclude VERSION; keep it in the build context")),
          else: igniter
      else
        igniter
      end
    end

    defp excludes_version?(pattern),
      do: pattern in ~w(VERSION /VERSION **/VERSION VERSION* /VERSION* * ** **/* /*)

    defp create(igniter, version), do: Igniter.create_new_file(igniter, "VERSION", version <> "\n")

    defp read_file(igniter, :inline) do
      igniter
      |> MixProject.update(:project, [:version], fn _ -> {:ok, {:code, quote(do: @version)}} end)
      |> Igniter.update_elixir_file("mix.exs", fn zipper ->
        # move_to_def/3 lands in the function body; the attribute goes before the def.
        with {:ok, body} <- CodeFunction.move_to_def(zipper, :project, 0),
             {:ok, project} <- Common.move_upwards(body, &CodeFunction.function_call?(&1, :def, 2)) do
          {:ok, Common.add_code(project, @attribute, placement: :before)}
        end
      end)
    end

    defp read_file(igniter, {:attribute, name}) do
      Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
        with {:ok, attribute} <- CodeModule.move_to_attribute_definition(zipper, name) do
          code = String.replace_prefix(@attribute, "@version", "@#{name}")
          {:ok, Common.replace_code(attribute, code)}
        end
      end)
    end

    defp disagreement(igniter, version, file) do
      Igniter.add_notice(igniter, """
      VERSION says #{file} and mix.exs says #{version}; both were left unchanged.
      Florist deploys the version in VERSION. Settle on one and have mix.exs read it:
        #{@attribute}
      """)
    end

    defp other_notice(igniter, file) do
      Igniter.add_notice(igniter, """
      mix.exs computes its version in a way this installer does not change#{if file, do: "", else: ", and there is no VERSION file"}.
      Florist reads the release version from VERSION, so keep it there and have mix.exs read it:
        #{@attribute}
      """)
    end

    defp version_file(igniter) do
      if Igniter.exists?(igniter, "VERSION") do
        igniter = Igniter.include_existing_file(igniter, "VERSION", source_handler: Source)
        {igniter, igniter.rewrite |> Rewrite.source!("VERSION") |> Source.get(:content) |> String.trim()}
      else
        {igniter, nil}
      end
    end

    # The project's `version:`, read from the source without evaluating it.
    defp mix_version(igniter) do
      quoted = igniter.rewrite |> Rewrite.source!("mix.exs") |> Source.get(:content) |> Code.string_to_quoted!()

      case project_keyword(quoted, :version) do
        # An unrelated @version would be shadowed by the one this adds.
        version when is_binary(version) ->
          if attribute_value(quoted, :version) == :missing, do: {:literal, version, :inline}, else: :other

        {:@, _, [{name, _, context}]} when is_atom(context) ->
          attribute(quoted, name)

        value ->
          if reads_version_file?(value), do: :reads_file, else: :other
      end
    end

    defp attribute(quoted, name) do
      case attribute_value(quoted, name) do
        version when is_binary(version) -> {:literal, version, {:attribute, name}}
        value -> if reads_version_file?(value), do: :reads_file, else: :other
      end
    end

    defp project_keyword(quoted, key) do
      {_, found} =
        Macro.prewalk(quoted, :missing, fn
          {:def, _, [{:project, _, args}, [do: body]]} = node, :missing when args in [nil, []] ->
            {node, if(Keyword.keyword?(body), do: Keyword.get(body, key, :missing), else: :missing)}

          node, found ->
            {node, found}
        end)

      found
    end

    defp attribute_value(quoted, name) do
      {_, found} =
        Macro.prewalk(quoted, :missing, fn
          {:@, _, [{^name, _, [value]}]} = node, :missing -> {node, value}
          node, found -> {node, found}
        end)

      found
    end

    defp reads_version_file?(value) do
      {_, found?} =
        Macro.prewalk(value, false, fn
          "VERSION" = node, _ -> {node, true}
          node, found? -> {node, found?}
        end)

      found?
    end
  end
else
  defmodule Mix.Brando.Igniter.Install.Version do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
