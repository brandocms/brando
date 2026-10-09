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
  @code_follows "(?:(?=[^\\s\\w\"'!?;<])|(?=<(?![/a-zA-Z!%]))" <>
                  "|(?=\\s+(?:[|=+\\-*/.,)\\]}:>]|&&|<(?![/a-zA-Z!%])|%>|(?:in|and|or|not|when|do)\\b))" <>
                  "|(?=\\s*\\z))"

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
  `[{path, first_line, text}]` for every template in `sources`
  (`[{path, text}]`): template files, and in Elixir sources the template
  sigils and the strings and files handed to EEx-style compilers.
  `read_file` reads a file named that way, `{:ok, text}` or `:error`.
  """
  def corpus(sources, read_file) do
    Enum.flat_map(sources, fn {path, text} ->
      cond do
        template_file?(path) -> [{path, 1, text}]
        Path.extname(path) in [".ex", ".exs"] -> embedded(path, text, read_file)
        true -> []
      end
    end)
  end

  defp embedded(path, text, read_file) do
    with true <- String.contains?(text, ["~", "_string", "_file"]),
         {:ok, ast} <- Code.string_to_quoted(text, columns: false, emit_warnings: false) do
      {_ast, found} = Macro.prewalk(ast, [], &embedded_node(&1, &2, path, read_file))
      Enum.reverse(found)
    else
      _ -> []
    end
  end

  defp embedded_node({sigil, meta, [{:<<>>, _, parts} | _]} = node, found, path, _read_file) when sigil in @sigils do
    first_line = meta[:line] + if(meta[:delimiter] in [~s("""), ~s(''')], do: 1, else: 0)
    {node, [{path, first_line, parts |> Enum.filter(&is_binary/1) |> Enum.join()} | found]}
  end

  defp embedded_node({call, meta, args} = node, found, path, read_file) when is_list(args) do
    case call_name(call) do
      name when name in @string_compilers ->
        {node, Enum.reverse(for(arg <- args, is_binary(arg), do: {path, meta[:line] || 1, arg}), found)}

      name when name in @file_compilers ->
        files =
          for file <- args, is_binary(file), {:ok, text} <- [read_file.(file)], do: {file, 1, text}

        {node, Enum.reverse(files, found)}

      _ ->
        {node, found}
    end
  end

  defp embedded_node(node, found, _path, _read_file), do: {node, found}

  defp call_name({:., _, [_receiver, name]}) when is_atom(name), do: name
  defp call_name(name) when is_atom(name), do: name
  defp call_name(_call), do: nil

  @doc """
  `[{path, line}]` where a template in `corpus` uses `token` (`Upload`,
  `Meta.HTML`) as a whole name that code could continue: followed at once
  by anything but a letter, a quote, `!`, `?`, `;` or a tag or EEx tag, or
  after whitespace by an operator, a closing delimiter, `%>`, an operator
  keyword (`in`, `when`, `do`, …) or the end of the template. So prose is
  skipped (`Upload a file`, `>Upload</span>`, `"Upload %{count} files"`,
  `Upload` before `<% … %>`) while `Upload.url`, `{Upload}`,
  `[Upload ]` and `Upload in @list` count.
  """
  def uses(corpus, token) do
    regex = Regex.compile!("(?<![\\w.@:\\-])" <> Regex.escape(token) <> @code_follows)

    for {path, first_line, text} <- corpus,
        [{at, _length}] <- [Regex.run(regex, text, return: :index)],
        do: {path, first_line + (text |> binary_part(0, at) |> :binary.matches("\n") |> length())}
  end

  @doc """
  The line of the first thing in `ast` (annotated by
  `Brando.Deprecated.LexicalAliases`) that lets a module render a
  template: a `use` of a Phoenix module or `use X, :atom`, `embed_templates`,
  EEx or Phoenix.Template, or a template sigil. Nil if nothing does.
  """
  def renders_templates(ast) do
    {_ast, line} =
      Macro.prewalk(ast, nil, fn
        node, nil -> {node, if(renders?(node), do: line(node))}
        node, line -> {node, line}
      end)

    line
  end

  defp renders?({:use, _, [target | options]}) do
    phoenix? = target |> LexicalAliases.module() |> inspect() |> String.starts_with?("Phoenix.")
    phoenix? or match?([option | _] when is_atom(option), Enum.map(options, &literal/1))
  end

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

  defp literal({:__block__, _, [value]}), do: value
  defp literal(value), do: value
end
