defmodule BrandoAdmin.Components.TextDiff.Highlight do
  @moduledoc false
  # Splits one line of a template into tokens for TextDiff's `highlight`:
  # tags, attribute names, quoted values, Liquid or HEEx expressions and
  # comments. A line at a time, so a tag or comment that spans lines is
  # coloured on the line it starts on; the text is never changed, only split.
  # HEEx escapes each token when it renders.

  @type token :: {String.t() | nil, String.t()}

  @doc "`line` as `[{class | nil, text}]`, for `:liquid`, `:heex` or `:html`."
  @spec tokens(String.t(), :liquid | :heex | :html) :: [token()]
  def tokens(line, language) when language in [:liquid, :heex, :html] do
    line |> scan(language, []) |> merge()
  end

  defp scan("", _language, acc), do: Enum.reverse(acc)

  defp scan("<!--" <> _ = rest, language, acc) do
    {comment, rest} = take_until(rest, "-->", 4)
    scan(rest, language, [{"tok-comment", comment} | acc])
  end

  defp scan("<%" <> _ = rest, language, acc) do
    {expr, rest} = take_until(rest, "%>", 2)
    scan(rest, language, [{"tok-liquid", expr} | acc])
  end

  defp scan("{%" <> _ = rest, language, acc) when language != :heex do
    {expr, rest} = take_until(rest, "%}", 2)
    scan(rest, language, [{"tok-liquid", expr} | acc])
  end

  defp scan("{{" <> _ = rest, language, acc) when language != :heex do
    {expr, rest} = take_until(rest, "}}", 2)
    scan(rest, language, [{"tok-liquid", expr} | acc])
  end

  defp scan("{" <> _ = rest, :heex, acc) do
    {expr, rest} = take_braces(rest)
    scan(rest, :heex, [{"tok-liquid", expr} | acc])
  end

  defp scan("<" <> after_lt = rest, language, acc) do
    case Regex.run(~r/^\/?[.:a-zA-Z][\w.:-]*/u, after_lt) do
      [name] ->
        tag = "<" <> name
        {tokens, rest} = attributes(drop(rest, tag), language, [{"tok-tag", tag}])
        scan(rest, language, tokens ++ acc)

      nil ->
        scan(after_lt, language, [{nil, "<"} | acc])
    end
  end

  defp scan(rest, language, acc) do
    {char, rest} = String.split_at(rest, 1)
    scan(rest, language, [{nil, char} | acc])
  end

  # Inside a tag, up to and including its `>`, or the end of the line
  defp attributes("", _language, acc), do: {acc, ""}
  defp attributes(">" <> rest, _language, acc), do: {[{"tok-tag", ">"} | acc], rest}
  defp attributes("/>" <> rest, _language, acc), do: {[{"tok-tag", "/>"} | acc], rest}

  defp attributes("\"" <> _ = rest, language, acc) do
    {value, rest} = quoted(rest, "\"")
    attributes(rest, language, [{"tok-str", value} | acc])
  end

  defp attributes("'" <> _ = rest, language, acc) do
    {value, rest} = quoted(rest, "'")
    attributes(rest, language, [{"tok-str", value} | acc])
  end

  defp attributes("{" <> _ = rest, :heex, acc) do
    {expr, rest} = take_braces(rest)
    attributes(rest, :heex, [{"tok-liquid", expr} | acc])
  end

  defp attributes(rest, language, acc) do
    cond do
      language != :heex and (String.starts_with?(rest, "{{") or String.starts_with?(rest, "{%")) ->
        close = if String.starts_with?(rest, "{%"), do: "%}", else: "}}"
        {expr, rest} = take_until(rest, close, 2)
        attributes(rest, language, [{"tok-liquid", expr} | acc])

      match = Regex.run(~r/^[a-zA-Z_:@][\w:.\-]*/u, rest) ->
        [name] = match
        attributes(drop(rest, name), language, [{"tok-attr", name} | acc])

      true ->
        {char, rest} = String.split_at(rest, 1)
        attributes(rest, language, [{nil, char} | acc])
    end
  end

  defp drop(text, prefix), do: binary_part(text, byte_size(prefix), byte_size(text) - byte_size(prefix))

  defp quoted(text, quote) do
    rest = drop(text, quote)

    case :binary.match(rest, quote) do
      {at, _} -> {quote <> binary_part(rest, 0, at + 1), binary_part(rest, at + 1, byte_size(rest) - at - 1)}
      :nomatch -> {text, ""}
    end
  end

  # From the start of `text` through `close`, searched for after the opening
  # `skip` bytes; the rest of the line when it doesn't close there
  defp take_until(text, close, skip) do
    rest = binary_part(text, skip, byte_size(text) - skip)

    case :binary.match(rest, close) do
      {at, len} ->
        size = skip + at + len
        {binary_part(text, 0, size), binary_part(text, size, byte_size(text) - size)}

      :nomatch ->
        {text, ""}
    end
  end

  # A HEEx `{…}`, with the braces nested in it
  defp take_braces(text), do: take_braces(text, 0, 0)

  defp take_braces(text, at, _depth) when at >= byte_size(text), do: {text, ""}

  defp take_braces(text, at, depth) do
    case :binary.at(text, at) do
      ?{ ->
        take_braces(text, at + 1, depth + 1)

      ?} when depth == 1 ->
        {binary_part(text, 0, at + 1), binary_part(text, at + 1, byte_size(text) - at - 1)}

      ?} ->
        take_braces(text, at + 1, depth - 1)

      _ ->
        take_braces(text, at + 1, depth)
    end
  end

  @doc """
  `tokens` as safe HTML: each class in a span, every text escaped, and
  nothing between them, so a line in `white-space: pre-wrap` reads as it is.
  """
  @spec to_html([token()]) :: Phoenix.HTML.safe()
  def to_html(tokens) do
    {:safe,
     Enum.map(tokens, fn
       {nil, text} -> escape(text)
       {class, text} -> [~s(<span class="), escape(class), ~s(">), escape(text), "</span>"]
     end)}
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # Plain text comes a character at a time: one token per run
  defp merge(tokens) do
    tokens
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn [{class, _} | _] = run -> {class, Enum.map_join(run, &elem(&1, 1))} end)
  end
end
