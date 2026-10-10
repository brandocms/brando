defmodule Brando.Deprecated.TemplateHazards do
  @moduledoc false
  # A backstop for `mix brando.migrate55` that does not depend on knowing
  # which module a template belongs to. Renaming an alias changes what a
  # template compiled into that module can see: `Upload` is gone once
  # `alias Brando.Upload` becomes `alias Brando.Uploads.Store`, and
  # `Meta.HTML` points under `Brando.Sites.Meta` once `alias Brando.Meta`
  # does. So the task reads every template in the project (`corpus/2`), and
  # a file whose rewrite changes such a name, and that can render templates
  # at all (`renders_templates/1`), is left when any template uses it
  # (`uses/2`).

  alias Brando.Deprecated.LexicalAliases

  @base_extensions ["heex", "eex", "leex", "exs", "sface"]
  @sigils [:sigil_H, :sigil_h, :sigil_L, :sigil_l, :sigil_E, :sigil_e, :sigil_F, :sigil_f]
  @string_compilers [:function_from_string, :compile_string, :eval_string]
  @file_compilers [:function_from_file, :compile_file, :eval_file]
  @compilers @string_compilers ++ @file_compilers
  @heredoc ~s(""")

  @doc "Template extensions: Phoenix's engines, and HEEx, LEEx, EEx, ExsEngine's and Surface's."
  def extensions do
    engines =
      if Code.ensure_loaded?(Phoenix.Template),
        do: Phoenix.Template.engines() |> Map.keys() |> Enum.map(&Atom.to_string/1),
        else: []

    Enum.uniq(@base_extensions ++ (engines -- ["ex"]))
  end

  @doc """
  Whether `path` is a template file: a template extension, and for `.exs`
  a format before it (`show.html.exs`), so a script is not one.
  """
  def template_file?(path) do
    case Path.extname(path) do
      ".exs" -> Path.extname(Path.rootname(path)) =~ ~r/\A\.[a-z0-9]+\z/ and not String.ends_with?(path, "_test.exs")
      "." <> extension -> extension in extensions()
      _ -> false
    end
  end

  @doc """
  `[{path, first_line, text, mode, owner}]` for every template in
  `sources` (`[{path, text}]`): template files, and in Elixir sources the
  template sigils and the strings and files handed to EEx-style compilers.
  `read_file` reads a file named that way, `{:ok, text}` or `:error`.

  `owner` is the file whose modules the template can compile into, or
  `:project` when it may be any: a sigil compiles into the module around
  it, so it is its file's, unless it sits in a `quote` that a macro hands
  to its callers. Template files and EEx-compiled strings and files are
  the project's.
  """
  def corpus(sources, read_file) do
    Enum.flat_map(sources, fn {path, text} ->
      cond do
        template_file?(path) -> [{path, 1, text, mode(path), :project}]
        Path.extname(path) in [".ex", ".exs"] -> embedded(path, text, read_file)
        true -> []
      end
    end)
  end

  defp embedded(path, text, read_file) do
    with true <- String.contains?(text, ["~", "_string", "_file"]),
         {:ok, ast} <- Code.string_to_quoted(text, columns: false, emit_warnings: false) do
      {_ast, {found, 0}} = Macro.traverse(ast, {[], 0}, &enter(&1, &2, path, read_file), &leave/2)
      Enum.reverse(found)
    else
      _ -> []
    end
  end

  # How many `quote`s the walk is inside: a sigil there is the project's
  defp enter(node, {found, quotes}, path, read_file) do
    quotes = if quote?(node), do: quotes + 1, else: quotes
    {node, found} = embedded_node(node, found, {path, if(quotes > 0, do: :project, else: path)}, read_file)
    {node, {found, quotes}}
  end

  defp leave(node, {found, quotes}), do: {node, {found, if(quote?(node), do: quotes - 1, else: quotes)}}

  defp quote?(node), do: match?({:quote, _, [_ | _]}, node)

  defp embedded_node({sigil, meta, [{:<<>>, _, parts} | _]} = node, found, {path, owner}, _read_file)
       when sigil in @sigils do
    first_line = meta[:line] + if(meta[:delimiter] in [~s("""), ~s(''')], do: 1, else: 0)
    mode = if sigil in [:sigil_H, :sigil_h, :sigil_F, :sigil_f], do: :heex, else: :eex
    {node, [{path, first_line, parts |> Enum.filter(&is_binary/1) |> Enum.join(), mode, owner} | found]}
  end

  defp embedded_node({call, meta, args} = node, found, {path, _owner}, read_file) when is_list(args) do
    case call_name(call) do
      name when name in @string_compilers ->
        strings = for arg <- args, is_binary(arg), do: {path, meta[:line] || 1, arg, :eex, :project}
        {node, Enum.reverse(strings, found)}

      name when name in @file_compilers ->
        files =
          for file <- args,
              is_binary(file),
              {:ok, text} <- [read_file.(file)],
              do: {file, 1, text, file_mode(file), :project}

        {node, Enum.reverse(files, found)}

      _ ->
        {node, found}
    end
  end

  defp embedded_node(node, found, _path, _read_file), do: {node, found}

  # EEx reads any file as EEx; a .heex one is HEEx
  defp file_mode(file), do: if(mode(file) == :heex, do: :heex, else: :eex)

  defp call_name({:., _, [_receiver, name]}) when is_atom(name), do: name
  defp call_name(name) when is_atom(name), do: name
  defp call_name(_call), do: nil

  @doc """
  `[{path, line}]` where a template in `corpus` (see `corpus/2`; `mode`
  and `owner` may be left off) that `file` may own uses `token`
  (`Upload`, `Meta.HTML`, whose dot may have whitespace around it) as a
  whole name, anywhere but in provable prose (`prose_mask/2`). A nil
  `file` reads every template.
  """
  def uses(corpus, token, file \\ nil) do
    regex =
      Regex.compile!(
        "(?<![\\w.@])" <> (token |> String.split(".") |> Enum.map_join("\\s*\\.\\s*", &Regex.escape/1)) <> "(?![\\w])"
      )

    for entry <- corpus,
        {path, first_line, text, mode, owner} = with_mode(entry),
        is_nil(file) or owner in [:project, file],
        code = prose_mask(text, mode),
        [{at, _length}] <- [Regex.run(regex, code, return: :index)],
        do: {path, first_line + (code |> binary_part(0, at) |> :binary.matches("\n") |> length())}
  end

  defp with_mode({path, first_line, text}), do: {path, first_line, text, mode(path), :project}
  defp with_mode({path, first_line, text, mode}), do: {path, first_line, text, mode, :project}
  defp with_mode(entry), do: entry

  @doc "How a template file is read: `:heex` (HEEx, Surface), `:eex` (EEx, LEEx) or `:code`."
  def mode(path) do
    case Path.extname(path) do
      extension when extension in [".heex", ".sface"] -> :heex
      extension when extension in [".eex", ".leex"] -> :eex
      _ -> :code
    end
  end

  @doc """
  `text` with what is provably prose blanked out, newlines kept, so offsets
  and lines stay. Prose is only plain text: outside every `{…}` (`:heex`),
  `<% … %>`, and tag attribute `={…}`, quoted attribute values and
  comments included, and the inside of a string literal in code but for
  its `\#{…}`. A tag's name stays (`<Meta.HTML.render_meta`). In `:code`
  nothing is prose, and a template the scan cannot follow (an unclosed
  brace, tag, comment or string) is all code.
  """
  def prose_mask(text, mode) do
    case classify(text, mode) do
      {:ok, masked} -> masked
      :unsure -> text
    end
  end

  @doc "`{:ok, masked}` (see `prose_mask/2`), or `:unsure` when the scan cannot follow `text`."
  def classify(text, :code), do: {:ok, text}

  def classify(text, mode) do
    {:ok, text |> markup(mode, []) |> Enum.reverse() |> IO.iodata_to_binary()}
  catch
    :unsure -> :unsure
  end

  defp markup(<<>>, _mode, acc), do: acc

  defp markup(<<"<%!--", rest::binary>>, mode, acc) do
    {comment, rest} = until!(rest, "--%>")
    markup(rest, mode, [blank("<%!--" <> comment <> "--%>") | acc])
  end

  defp markup(<<"<%", _::binary>> = text, mode, acc) do
    {masked, rest} = eex(text)
    markup(rest, mode, [masked | acc])
  end

  defp markup(<<"<!--", rest::binary>>, mode, acc) do
    {masked, rest} = raw(rest, "-->", ["    "])
    markup(rest, mode, [masked | acc])
  end

  defp markup(<<"{", rest::binary>>, :heex, acc) do
    {code, rest} = braces!(rest)
    markup(rest, :heex, ["}", code(code), "{" | acc])
  end

  defp markup(<<"<", c, _::binary>> = text, :heex, acc) when c in ?a..?z or c in ?A..?Z or c in [?., ?:, ?/] do
    {masked, rest} = tag(text)
    markup(rest, :heex, [masked | acc])
  end

  defp markup(<<"\n", rest::binary>>, mode, acc), do: markup(rest, mode, ["\n" | acc])
  defp markup(<<_, rest::binary>>, mode, acc), do: markup(rest, mode, [" " | acc])

  # `<%% %>` and `<%# %>` are text; `<% … %>` code up to the first `%>`
  defp eex(<<"<%%", rest::binary>>), do: {"   ", rest}

  defp eex(<<"<%#", rest::binary>>) do
    {comment, rest} = until!(rest, "%>")
    {blank("<%#" <> comment <> "%>"), rest}
  end

  defp eex(<<"<%", rest::binary>>) do
    {code, rest} = until!(rest, "%>")
    {["  ", code(code), "  "], rest}
  end

  # Text up to `terminator` in which only EEx tags are code
  defp raw(text, terminator, acc) do
    case :binary.match(text, [terminator, "<%"]) do
      :nomatch ->
        throw(:unsure)

      {at, length} ->
        before = blank(binary_part(text, 0, at))
        rest = binary_part(text, at, byte_size(text) - at)

        if binary_part(text, at, length) == terminator do
          {Enum.reverse([blank(terminator), before | acc]), binary_part(rest, length, byte_size(rest) - length)}
        else
          {masked, rest} = eex(rest)
          raw(rest, terminator, [masked, before | acc])
        end
    end
  end

  # A tag: its name stays, quoted values are text, `{…}` values are code;
  # `<script>` and `<style>` content is text but for EEx tags
  defp tag(<<"<", rest::binary>>) do
    [name] = Regex.run(~r/\A\/?[\w.:\-@]*/, rest)
    rest = binary_part(rest, byte_size(name), byte_size(rest) - byte_size(name))
    {attributes, rest} = attributes(rest, [])
    masked = [" ", name | attributes]

    if String.downcase(name) in ["script", "style"] do
      {content, rest} = raw(rest, "</" <> name, [])
      {[masked, content], rest}
    else
      {masked, rest}
    end
  end

  defp attributes(<<">", rest::binary>>, acc), do: {Enum.reverse([" " | acc]), rest}
  defp attributes(<<>>, _acc), do: throw(:unsure)

  defp attributes(<<quote, rest::binary>>, acc) when quote in [?", ?'] do
    {value, rest} = until!(rest, <<quote>>)
    attributes(rest, [blank(<<quote>> <> value <> <<quote>>) | acc])
  end

  defp attributes(<<"{", rest::binary>>, acc) do
    {code, rest} = braces!(rest)
    attributes(rest, ["}", code(code), "{" | acc])
  end

  defp attributes(<<"\n", rest::binary>>, acc), do: attributes(rest, ["\n" | acc])
  defp attributes(<<_, rest::binary>>, acc), do: attributes(rest, [" " | acc])

  # Code with its string literals blanked but for their `#{…}`
  defp code(text), do: text |> code([]) |> Enum.reverse()

  defp code(<<>>, acc), do: acc

  # A name whole, `valid?` and `save!` included, so a `?` after it is not
  # read as a character literal
  defp code(<<c, _::binary>> = text, acc) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c in [?_, ?@] do
    [name] = Regex.run(~r/\A[@\w]+[?!]?/, text)
    code(binary_part(text, byte_size(name), byte_size(text) - byte_size(name)), [name | acc])
  end

  defp code(<<"?", c, rest::binary>>, acc), do: code(rest, [<<c>>, "?" | acc])

  defp code(<<"#", rest::binary>>, acc) do
    {comment, rest} =
      case :binary.split(rest, "\n") do
        [comment, rest] -> {comment <> "\n", rest}
        [comment] -> {comment, ""}
      end

    code(rest, [comment, "#" | acc])
  end

  defp code(<<?", ?", ?", rest::binary>>, acc) do
    {masked, rest} = string(rest, @heredoc, [])
    code(rest, [masked, "   " | acc])
  end

  defp code(<<quote, rest::binary>>, acc) when quote in [?", ?'] do
    {masked, rest} = string(rest, <<quote>>, [])
    code(rest, [masked, " " | acc])
  end

  defp code(<<c, rest::binary>>, acc), do: code(rest, [<<c>> | acc])

  defp string(<<>>, _quote, _acc), do: throw(:unsure)
  defp string(<<"\\", c, rest::binary>>, quote, acc), do: string(rest, quote, [blank(<<"\\", c>>) | acc])

  defp string(<<?#, ?{, rest::binary>>, quote, acc) do
    {interpolation, rest} = braces!(rest)
    string(rest, quote, ["}", interpolation, "  " | acc])
  end

  defp string(text, quote, acc) do
    if String.starts_with?(text, quote) do
      size = byte_size(quote)
      {Enum.reverse([blank(quote) | acc]), binary_part(text, size, byte_size(text) - size)}
    else
      <<c, rest::binary>> = text
      string(rest, quote, [blank(<<c>>) | acc])
    end
  end

  defp until!(text, terminator) do
    case :binary.split(text, terminator) do
      [before, rest] -> {before, rest}
      [_before] -> throw(:unsure)
    end
  end

  # The code up to the `}` closing a `{`, past nested braces and strings
  defp braces!(text) do
    length = closing(text, 0, 0)
    {binary_part(text, 0, length), binary_part(text, length + 1, byte_size(text) - length - 1)}
  end

  defp closing(text, at, _depth) when at >= byte_size(text), do: throw(:unsure)

  defp closing(text, at, depth) do
    case :binary.at(text, at) do
      ?} when depth == 0 -> at
      ?} -> closing(text, at + 1, depth - 1)
      ?{ -> closing(text, at + 1, depth + 1)
      ?? when at > 0 -> closing(text, at + if(name_end?(text, at - 1), do: 1, else: 2), depth)
      ?? -> closing(text, at + 2, depth)
      ?" -> closing(text, string_end(text, at + 1, ?"), depth)
      _ -> closing(text, at + 1, depth)
    end
  end

  # Whether the byte at `at` ends a name, so a `?` after it is part of it
  defp name_end?(text, at) do
    c = :binary.at(text, at)
    c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_
  end

  defp string_end(text, at, _quote) when at >= byte_size(text), do: throw(:unsure)

  defp string_end(text, at, quote) do
    case :binary.at(text, at) do
      ?\\ -> string_end(text, at + 2, quote)
      ^quote -> at + 1
      _ -> string_end(text, at + 1, quote)
    end
  end

  # Byte for byte, so offsets stay, whatever the encoding
  defp blank(text), do: for(<<byte <- text>>, into: "", do: if(byte == ?\n, do: "\n", else: " "))

  @doc """
  The line of the first thing in `ast` (annotated by
  `Brando.Deprecated.LexicalAliases`) that may let a module render a
  template: any `use` (a site's own macro may set templates up),
  `embed_templates`, EEx or Phoenix.Template, or a template sigil. Nil
  for a module that uses none of them.
  """
  def renders_templates(ast) do
    {_ast, line} =
      Macro.prewalk(ast, nil, fn
        node, nil -> {node, if(renders?(node), do: line(node))}
        node, line -> {node, line}
      end)

    line
  end

  defp renders?({:use, _, [_ | _]}), do: true

  defp renders?({:embed_templates, _, args}) when is_list(args), do: true
  defp renders?({{:., _, [_receiver, :embed_templates]}, _, _}), do: true
  defp renders?({sigil, _, _}) when sigil in @sigils, do: true

  defp renders?({{:., _, [receiver, _name]}, _, args}) when is_list(args),
    do: LexicalAliases.module(receiver) in [EEx, Phoenix.Template]

  defp renders?({name, _, args}) when name in @compilers and is_list(args), do: true
  defp renders?(_node), do: false

  defp line({_, meta, _}) when is_list(meta), do: meta[:line] || 1
  defp line({{_, meta, _}, _, _}) when is_list(meta), do: meta[:line] || 1
  defp line(_node), do: 1
end
