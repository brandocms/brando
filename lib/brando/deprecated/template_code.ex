defmodule Brando.Deprecated.TemplateCode do
  @moduledoc false
  # The parts of a template that are code, for the 0.55 module renames to
  # resolve: `segments/2` splits HEEx, Surface or EEx text into
  #
  #   * `{:code, elixir, line}`: inside `{…}` (HEEx and Surface, attribute
  #     values included; Surface's `{#if …}` without its keyword) and
  #     `<%= … %>` / `<% … %>` (everywhere, HTML comments and `<script>`
  #     and `<style>` content included), and
  #   * `{:tag, name, line}`: a component tag's module, `Meta.HTML` in
  #     `<Meta.HTML.render_meta …>` or `</Meta.HTML.render_meta>`,
  #
  # with `line` counted from 0 at the start of the text. Plain text, HEEx
  # and EEx comments (`<%!-- … --%>`, `<%# … %>`), escaped `<%%`, and `{…}`
  # in an HTML comment or in `<script>` and `<style>` content (where HEEx
  # does not interpolate) are skipped.
  #
  # The scan is a best effort: `mix brando.migrate55` only trusts it to
  # clear a template that does not name a renamed alias anywhere.

  @doc "The code segments and component tags in `text`; `mode` is `:heex`, `:surface` or `:eex`."
  def segments(text, mode), do: text |> scan(0, mode, []) |> Enum.reverse()

  @doc "How a template file is read, from its extension."
  def mode(path) do
    case Path.extname(path) do
      ".heex" -> :heex
      ".sface" -> :surface
      _ -> :eex
    end
  end

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

  # A HEEx comment runs nothing; an HTML comment's EEx tags still run
  defp scan(<<"<%!--", rest::binary>>, line, mode, acc), do: skip(rest, "--%>", line, mode, acc)
  defp scan(<<"<!--", rest::binary>>, line, mode, acc), do: raw(rest, "-->", line, mode, acc)

  defp scan(<<"<%", rest::binary>>, line, mode, acc) do
    {rest, line, acc} = eex_tag(rest, line, acc)
    scan(rest, line, mode, acc)
  end

  # `<script>` and `<style>` content does not interpolate `{…}`, but their
  # attributes and EEx tags are code
  defp scan(<<"<script", c, rest::binary>>, line, mode, acc)
       when mode != :eex and c in [?\s, ?\t, ?\n, ?\r, ?>, ?/] do
    raw_tag("script", <<c, rest::binary>>, line, mode, acc)
  end

  defp scan(<<"<style", c, rest::binary>>, line, mode, acc)
       when mode != :eex and c in [?\s, ?\t, ?\n, ?\r, ?>, ?/] do
    raw_tag("style", <<c, rest::binary>>, line, mode, acc)
  end

  defp scan(<<"{", rest::binary>>, line, mode, acc) when mode != :eex do
    {code, rest} = interpolation(rest)
    code = if mode == :surface, do: String.replace(code, ~r/\A\s*[#\/]\w*/, ""), else: code
    scan(rest, line + newlines(code), mode, [{:code, code, line} | acc])
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

  # After `<%`: escaped `<%%`, a comment, or code up to `%>`
  defp eex_tag(<<"%", rest::binary>>, line, acc), do: {rest, line, acc}

  defp eex_tag(<<"!--", rest::binary>>, line, acc) do
    {skipped, rest} = until(rest, "--%>")
    {rest, line + newlines(skipped), acc}
  end

  defp eex_tag(<<"#", rest::binary>>, line, acc) do
    {skipped, rest} = until(rest, "%>")
    {rest, line + newlines(skipped), acc}
  end

  defp eex_tag(rest, line, acc) do
    {code, rest} = until(rest, "%>")
    {rest, line + newlines(code), [{:code, String.trim_leading(code, "="), line} | acc]}
  end

  # An opening tag's attributes, then its content up to the closing tag
  defp raw_tag(tag, text, line, mode, acc) do
    {rest, line, acc} = attributes(text, line, acc)
    raw(rest, "</" <> tag <> ">", line, mode, acc)
  end

  defp attributes(<<">", rest::binary>>, line, acc), do: {rest, line, acc}

  defp attributes(<<quote, rest::binary>>, line, acc) when quote in [?", ?'] do
    {value, rest} = until(rest, <<quote>>)
    attributes(rest, line + newlines(value), acc)
  end

  defp attributes(<<"{", rest::binary>>, line, acc) do
    {code, rest} = interpolation(rest)
    attributes(rest, line + newlines(code), [{:code, code, line} | acc])
  end

  defp attributes(<<"\n", rest::binary>>, line, acc), do: attributes(rest, line + 1, acc)
  defp attributes(<<_, rest::binary>>, line, acc), do: attributes(rest, line, acc)
  defp attributes(<<>>, line, acc), do: {<<>>, line, acc}

  # Text up to `terminator` in which only EEx tags are code
  defp raw(text, terminator, line, mode, acc) do
    case :binary.match(text, [terminator, "<%"]) do
      :nomatch ->
        scan(<<>>, line + newlines(text), mode, acc)

      {at, length} ->
        before = binary_part(text, 0, at)
        rest = binary_part(text, at + length, byte_size(text) - at - length)
        line = line + newlines(before)

        if binary_part(text, at, length) == terminator do
          scan(rest, line, mode, acc)
        else
          {rest, line, acc} = eex_tag(rest, line, acc)
          raw(rest, terminator, line, mode, acc)
        end
    end
  end

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

  # `{code, rest}` for an interpolation, after its `{`
  defp interpolation(text) do
    length = closing_brace(text, 0, 0)
    rest_at = min(length + 1, byte_size(text))
    {binary_part(text, 0, length), binary_part(text, rest_at, byte_size(text) - rest_at)}
  end

  # The length of the code before the `}` that closes an interpolation,
  # past nested braces and string literals; the whole text if none does
  defp closing_brace(text, at, _depth) when at >= byte_size(text), do: byte_size(text)

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
  defp string_end(text, at, _quote) when at >= byte_size(text), do: byte_size(text)

  defp string_end(text, at, quote) do
    case :binary.at(text, at) do
      ?\\ -> string_end(text, at + 2, quote)
      ^quote -> at + 1
      _ -> string_end(text, at + 1, quote)
    end
  end

  defp newlines(text), do: text |> :binary.matches("\n") |> length()
end
