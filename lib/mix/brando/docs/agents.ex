defmodule Mix.Brando.Docs.Agents do
  @moduledoc false

  # Builds the agent-facing documentation from `guides/*.md`:
  #
  #   * `usage-rules.md`: the regions of each guide between
  #     `<!-- usage-rules:start -->` and `<!-- usage-rules:end -->`, under one
  #     heading per guide;
  #   * `llms.txt`: an llmstxt.org index of the guides, with a one-line
  #     description of each (`<!-- llms-description: ... -->` in the guide, or
  #     its first sentence);
  #   * `llms-full.txt`: every guide joined.
  #
  # All three follow the docs sidebar: `groups_for_extras`, then `extras`.
  #
  # Output depends only on the guides and the docs config, so a second run
  # writes the same bytes.

  @start "<!-- usage-rules:start -->"
  @stop "<!-- usage-rules:end -->"
  @no_compile "<!-- usage-rules:no-compile -->"
  @markers [@start, @stop]
  @deps_guides "deps/brando/guides"

  defmodule Guide do
    @moduledoc false
    defstruct [:path, :file, :id, :title, :group, :description, :source, regions: []]
  end

  @doc "The marker that excludes the next Elixir code fence from the example check."
  def no_compile_marker, do: @no_compile

  @doc """
  Reads the guides listed in the docs extras, in sidebar order: by group, in
  the order of `groups_for_extras`, then in the order of `extras`.
  """
  def guides(root \\ File.cwd!(), docs \\ docs_config()) do
    groups = docs[:groups_for_extras] || []
    group_order = groups |> Enum.map(&to_string(elem(&1, 0))) |> Enum.with_index() |> Map.new()

    docs
    |> Keyword.fetch!(:extras)
    |> Enum.map(&extra_path/1)
    |> Enum.filter(&String.starts_with?(&1, "guides/"))
    |> Enum.map(&read_guide(root, &1, groups))
    |> Enum.with_index()
    |> Enum.sort_by(fn {guide, index} -> {Map.get(group_order, guide.group, map_size(group_order)), index} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp docs_config, do: Mix.Project.config()[:docs] || []

  defp extra_path({path, _opts}), do: to_string(path)
  defp extra_path(path), do: to_string(path)

  defp read_guide(root, path, groups) do
    source = File.read!(Path.join(root, path))
    file = Path.basename(path)

    %Guide{
      path: path,
      file: file,
      id: Path.rootname(file),
      title: title(source, path),
      group: group(groups, path),
      description: description(source),
      source: source,
      regions: regions(source, path)
    }
  end

  defp title(source, path) do
    case Regex.run(~r/\A#\s+(.+)$/m, source) do
      [_, title] -> String.trim(title)
      nil -> raise ArgumentError, "#{path} must start with a level-one heading"
    end
  end

  defp group(groups, path) do
    Enum.find_value(groups, "Other guides", fn {name, paths} ->
      if path in Enum.map(paths, &to_string/1), do: to_string(name)
    end)
  end

  # `<!-- llms-description: ... -->` anywhere in the guide, or the first
  # sentence of the first paragraph after the title.
  defp description(source) do
    case Regex.run(~r/<!--\s*llms-description:\s*(.+?)\s*-->/s, source) do
      [_, description] -> String.replace(description, ~r/\s+/, " ")
      nil -> first_paragraph_sentence(source)
    end
  end

  defp first_paragraph_sentence(source) do
    source
    |> String.split("\n")
    |> Enum.drop(1)
    |> Enum.drop_while(&(String.trim(&1) == "" or String.starts_with?(&1, "<!--")))
    |> Enum.take_while(&(String.trim(&1) != ""))
    |> Enum.join(" ")
    |> strip_links()
    |> String.replace("**", "")
    |> String.replace(~r/\s+/, " ")
    |> first_sentence()
  end

  defp first_sentence(text) do
    case Regex.run(~r/\A(.+?[.!?])(?:\s|\z)/, text) do
      [_, sentence] -> sentence
      nil -> String.trim(text)
    end
  end

  defp strip_links(text), do: Regex.replace(~r/\[([^\]]+)\]\([^)]*\)/, text, "\\1")

  ## Regions

  defp regions(source, path) do
    {regions, state} =
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{fence: nil, open: nil}}, &scan_line(&1, &2, path))

    if state.open, do: raise(ArgumentError, "#{path}:#{state.open.line}: #{@start} has no matching #{@stop}")

    Enum.reverse(regions)
  end

  defp scan_line({line, number}, {regions, %{fence: nil} = state}, path) do
    case marker(String.trim(line), state, "#{path}:#{number}") do
      :open -> {regions, %{state | open: %{line: number, lines: []}}}
      :close -> {[region_text(state.open) | regions], %{state | open: nil}}
      :none -> {regions, collect(%{state | fence: fence_open(line)}, line)}
    end
  end

  defp scan_line({line, _number}, {regions, state}, _path) do
    fence = if fence_closes?(line, state.fence), do: nil, else: state.fence
    {regions, collect(%{state | fence: fence}, line)}
  end

  defp marker(@start, %{open: nil}, _location), do: :open
  defp marker(@start, _state, location), do: raise(ArgumentError, "#{location}: usage-rules regions cannot be nested")
  defp marker(@stop, %{open: nil}, location), do: raise(ArgumentError, "#{location}: #{@stop} without #{@start}")
  defp marker(@stop, _state, _location), do: :close
  defp marker(@no_compile, _state, _location), do: :none

  defp marker("<!--" <> _ = comment, _state, location) do
    if String.contains?(comment, "usage-rules:"),
      do: raise(ArgumentError, "#{location}: unknown usage-rules marker #{comment}"),
      else: :none
  end

  defp marker(_line, _state, _location), do: :none

  defp region_text(open), do: open.lines |> Enum.reverse() |> Enum.join("\n") |> trim_blank_lines()

  defp collect(%{open: nil} = state, _line), do: state
  defp collect(%{open: open} = state, line), do: %{state | open: %{open | lines: [line | open.lines]}}

  defp fence_open(line) do
    case Regex.run(~r/^\s*(`{3,}|~{3,})/, line) do
      [_, fence] -> fence
      nil -> nil
    end
  end

  defp fence_closes?(line, fence) do
    trimmed = String.trim(line)
    String.starts_with?(trimmed, fence) and String.trim(trimmed, String.first(fence)) == ""
  end

  defp trim_blank_lines(text) do
    text
    |> String.split("\n")
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  ## usage-rules.md

  @doc "The contents of `usage-rules.md`."
  def usage_rules(guides) do
    sections =
      guides
      |> Enum.reject(&(&1.regions == []))
      |> Enum.map(&usage_rules_section/1)

    Enum.join([usage_rules_header() | sections], "\n\n") <> "\n"
  end

  defp usage_rules_header do
    """
    # Brando usage rules

    <!-- Generated by `mix brando.docs.agents` from the usage-rules regions in
    Brando's guides/*.md. Edit the guides, then run the task again. -->

    Brando is a CMS for Phoenix applications: Blueprints declare content types,
    editors compose entries from blocks and modules in a LiveView admin, and
    the application renders them. These rules are the short version of the
    guides that ship with the package in `#{@deps_guides}/`. Each section names
    its guide; read it before changing code in that area, and prefer what the
    guide says over conventions from other CMSs or older Brando versions.\
    """
  end

  defp usage_rules_section(guide) do
    shift = heading_shift(guide.regions)

    body =
      Enum.map_join(guide.regions, "\n\n", &(&1 |> transform_prose(guide, shift) |> String.trim_trailing()))

    """
    ## #{guide.title}

    Guide: `#{@deps_guides}/#{guide.file}`

    #{body}\
    """
  end

  # The shallowest heading inside a guide's regions becomes `###`.
  defp heading_shift(regions) do
    regions
    |> Enum.flat_map(&prose_lines/1)
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^(#+)\s/, line) do
        [_, hashes] -> [String.length(hashes)]
        nil -> []
      end
    end)
    |> case do
      [] -> 0
      levels -> max(3 - Enum.min(levels), 0)
    end
  end

  defp prose_lines(text) do
    text
    |> String.split("\n")
    |> map_prose(fn line -> line end)
    |> Enum.filter(&match?({:prose, _}, &1))
    |> Enum.map(&elem(&1, 1))
  end

  defp transform_prose(text, guide, shift) do
    text
    |> String.split("\n")
    |> map_prose(fn line ->
      line
      |> shift_heading(shift)
      |> rewrite_links(guide)
    end)
    |> Enum.map_join("\n", &elem(&1, 1))
  end

  # Applies `fun` to lines outside code fences, tagging each line.
  defp map_prose(lines, fun) do
    {tagged, _fence} =
      Enum.map_reduce(lines, nil, fn
        line, nil ->
          case fence_open(line) do
            nil -> {{:prose, fun.(line)}, nil}
            fence -> {{:code, line}, fence}
          end

        line, fence ->
          {{:code, line}, if(fence_closes?(line, fence), do: nil, else: fence)}
      end)

    tagged
  end

  defp shift_heading(line, 0), do: line

  defp shift_heading(line, shift) do
    case Regex.run(~r/^(#+)(\s.*)$/, line) do
      [_, hashes, rest] -> String.duplicate("#", min(String.length(hashes) + shift, 6)) <> rest
      nil -> line
    end
  end

  # Links resolve from a consuming project's root, where the guides are in
  # deps/brando/guides.
  defp rewrite_links(line, guide) do
    Regex.replace(~r/\]\(([^)\s]+)\)/, line, fn whole, target ->
      cond do
        String.starts_with?(target, "#") -> "](#{@deps_guides}/#{guide.file}#{target})"
        Regex.match?(~r/^[a-z0-9_]+\.md(#.*)?$/, target) -> "](#{@deps_guides}/#{target})"
        true -> whole
      end
    end)
  end

  ## llms.txt and llms-full.txt

  @doc "The contents of `llms.txt`, an llmstxt.org index of the guides."
  def llms_txt(guides, project \\ project_info()) do
    sections =
      guides
      |> Enum.chunk_by(& &1.group)
      |> Enum.map(fn [%{group: group} | _] = chunk ->
        links = Enum.map_join(chunk, "\n", &"- [#{&1.title}](#{&1.id}.md): #{&1.description}")
        "## #{group}\n\n#{links}"
      end)

    optional = """
    ## Optional

    - [All guides in one file](llms-full.txt): Every guide above, joined in this order.
    - [API reference](api-reference.md): Every public module and Mix task.\
    """

    header = """
    # #{project.name}

    > #{project.summary}

    Version #{project.version}. Projects that depend on Brando also have these
    guides in `#{@deps_guides}/` and the short rules in `deps/brando/usage-rules.md`.\
    """

    Enum.join([header | sections] ++ [optional], "\n\n") <> "\n"
  end

  @doc "The contents of `llms-full.txt`: every guide, joined."
  def llms_full_txt(guides, project \\ project_info()) do
    body =
      Enum.map_join(guides, "\n\n", fn guide ->
        "<!-- guides/#{guide.file} -->\n\n" <> (guide.source |> strip_markers() |> String.trim())
      end)

    "# #{project.name} v#{project.version} guides\n\n> #{project.summary}\n\n" <> body <> "\n"
  end

  defp strip_markers(source) do
    source
    |> String.replace(~r/<!--\s*llms-description:.*?-->\n?/s, "")
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) in [@no_compile | @markers]))
    |> Enum.join("\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
  end

  defp project_info do
    config = Mix.Project.config()

    %{
      name: config[:name] || "Brando",
      version: config[:version],
      summary: summary()
    }
  end

  @doc "The one-line summary shown in llms.txt and on HexDocs."
  def summary do
    "Brando is a CMS for Elixir and Phoenix. Blueprints declare content types; " <>
      "editors compose entries from blocks and modules in a LiveView admin; " <>
      "the application renders pages, previews and metadata from them."
  end

  ## Code examples

  @doc """
  The Elixir code fences of a generated rules file, with the section each is
  under and whether it is marked as not compilable.
  """
  def examples(markdown) do
    {examples, _} =
      markdown
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{section: nil, previous: nil, fence: nil}}, &example_line/2)

    Enum.reverse(examples)
  end

  defp example_line({line, number}, {examples, %{fence: nil} = state}) do
    cond do
      match = Regex.run(~r/^(\s*)```elixir\s*$/, line) ->
        [_, indent] = match

        fence = %{
          line: number + 1,
          indent: indent,
          lines: [],
          no_compile: state.previous == @no_compile,
          section: state.section
        }

        {examples, %{state | fence: fence, previous: nil}}

      fence = fence_open(line) ->
        {examples, %{state | fence: {:other, fence}, previous: nil}}

      String.starts_with?(line, "## ") ->
        {examples, %{state | section: String.trim_leading(line, "## "), previous: nil}}

      String.trim(line) == "" ->
        {examples, state}

      true ->
        {examples, %{state | previous: String.trim(line)}}
    end
  end

  defp example_line({line, _number}, {examples, %{fence: {:other, fence}} = state}) do
    if fence_closes?(line, fence), do: {examples, %{state | fence: nil}}, else: {examples, state}
  end

  defp example_line({line, _number}, {examples, %{fence: fence} = state}) do
    if fence_closes?(line, "```") do
      example = %{
        code: fence.lines |> Enum.reverse() |> Enum.join("\n"),
        line: fence.line,
        section: fence.section,
        no_compile: fence.no_compile
      }

      {[example | examples], %{state | fence: nil}}
    else
      line = String.replace_prefix(line, fence.indent, "")
      {examples, %{state | fence: %{fence | lines: [line | fence.lines]}}}
    end
  end
end
