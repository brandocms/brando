defmodule Brando.Deprecated.TemplateCode do
  @moduledoc false
  # The parts of a template that are code, for the 0.55 module renames to
  # resolve: `segments/2` splits HEEx or EEx text into
  #
  #   * `{:code, elixir, line}`: inside `{…}` (HEEx only, attribute values
  #     included) and `<%= … %>` / `<% … %>`, and
  #   * `{:tag, name, line}`: a component tag's module, `Meta.HTML` in
  #     `<Meta.HTML.render_meta …>` or `</Meta.HTML.render_meta>`,
  #
  # with `line` counted from 0 at the start of the text. Plain text, HEEx and
  # HTML comments, EEx comments (`<%# … %>`, `<%!-- … --%>`), escaped `<%%`,
  # and `<script>` and `<style>` content (where HEEx does not interpolate)
  # are skipped.

  @doc "The code segments and component tags in `text`; `mode` is `:heex` or `:eex`."
  def segments(text, mode), do: text |> scan(0, mode, []) |> Enum.reverse()

  @doc "How a template file is read: `:heex` for `.heex`, `:eex` otherwise."
  def mode(path), do: if(Path.extname(path) == ".heex", do: :heex, else: :eex)

  @doc """
  The pattern and root of `embed_templates pattern, root: …` (root "."
  when not given), or `:computed` when either is not a literal string.
  Reads both `Code.string_to_quoted/2` and Sourceror ASTs.
  """
  def embed_pattern(pattern, options) do
    with pattern when is_binary(pattern) <- literal(pattern),
         {:ok, root} <- embed_root(options) do
      {:ok, pattern, root}
    else
      _ -> :computed
    end
  end

  defp embed_root([]), do: {:ok, "."}

  defp embed_root([options]) do
    case literal(options) do
      options when is_list(options) -> Enum.reduce_while(options, {:ok, "."}, &root_option/2)
      _ -> :computed
    end
  end

  defp embed_root(_options), do: :computed

  defp root_option({key, value}, acc) do
    cond do
      literal(key) != :root -> {:cont, acc}
      is_binary(literal(value)) -> {:halt, {:ok, literal(value)}}
      true -> {:halt, :computed}
    end
  end

  defp root_option(_option, _acc), do: {:halt, :computed}

  defp literal({:__block__, _, [value]}), do: value
  defp literal(value), do: value

  defp scan(<<"<%!--", rest::binary>>, line, mode, acc), do: skip(rest, "--%>", line, mode, acc)
  defp scan(<<"<!--", rest::binary>>, line, mode, acc), do: skip(rest, "-->", line, mode, acc)
  defp scan(<<"<%%", rest::binary>>, line, mode, acc), do: scan(rest, line, mode, acc)
  defp scan(<<"<%#", rest::binary>>, line, mode, acc), do: skip(rest, "%>", line, mode, acc)

  defp scan(<<"<%", rest::binary>>, line, mode, acc) do
    {code, rest} = until(rest, "%>")
    code = String.trim_leading(code, "=")
    scan(rest, line + newlines(code), mode, [{:code, code, line} | acc])
  end

  defp scan(<<"<script", rest::binary>>, line, :heex, acc), do: skip(rest, "</script>", line, :heex, acc)
  defp scan(<<"<style", rest::binary>>, line, :heex, acc), do: skip(rest, "</style>", line, :heex, acc)

  defp scan(<<"{", rest::binary>>, line, :heex, acc) do
    length = closing_brace(rest, 0, 0)
    code = binary_part(rest, 0, length)
    rest = binary_part(rest, min(length + 1, byte_size(rest)), max(byte_size(rest) - length - 1, 0))
    scan(rest, line + newlines(code), :heex, [{:code, code, line} | acc])
  end

  defp scan(<<"<", rest::binary>> = text, line, mode, acc) do
    case Regex.run(~r/\A<\/?([A-Z]\w*(?:\.[A-Z]\w*)*)/, text) do
      [_, name] -> scan(rest, line, mode, [{:tag, name, line} | acc])
      nil -> scan(rest, line, mode, acc)
    end
  end

  defp scan(<<"\n", rest::binary>>, line, mode, acc), do: scan(rest, line + 1, mode, acc)
  defp scan(<<_, rest::binary>>, line, mode, acc), do: scan(rest, line, mode, acc)
  defp scan(<<>>, _line, _mode, acc), do: acc

  defp skip(text, terminator, line, mode, acc) do
    {skipped, rest} = until(text, terminator)
    scan(rest, line + newlines(skipped), mode, acc)
  end

  defp until(text, terminator) do
    case :binary.split(text, terminator) do
      [before, rest] -> {before, rest}
      [before] -> {before, ""}
    end
  end

  # The length of the code before the `}` that closes an interpolation,
  # past nested braces and string literals
  defp closing_brace(text, at, _depth) when at >= byte_size(text), do: at

  defp closing_brace(text, at, depth) do
    case :binary.at(text, at) do
      ?} when depth == 0 -> at
      ?} -> closing_brace(text, at + 1, depth - 1)
      ?{ -> closing_brace(text, at + 1, depth + 1)
      ?" -> closing_brace(text, string_end(text, at + 1, ?"), depth)
      ?' -> closing_brace(text, string_end(text, at + 1, ?'), depth)
      _ -> closing_brace(text, at + 1, depth)
    end
  end

  # The position after the quote that closes a string opened before `at`
  defp string_end(text, at, _quote) when at >= byte_size(text), do: at

  defp string_end(text, at, quote) do
    case :binary.at(text, at) do
      ?\\ -> string_end(text, at + 2, quote)
      ^quote -> at + 1
      _ -> string_end(text, at + 1, quote)
    end
  end

  defp newlines(text), do: text |> :binary.matches("\n") |> length()
end
