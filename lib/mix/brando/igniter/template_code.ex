if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.TemplateCode do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # Where the Elixir code is in a template or module, for source rewrites that
    # must not touch the JavaScript, CSS or text around it.
    #
    # `code?/2` returns a function telling whether a byte offset in a file's
    # content starts Elixir code:
    #
    #   * `.eex` and `.leex`: inside `<% %>` tags;
    #   * `.heex`: inside `<% %>` tags, `{...}` in text and attributes, outside
    #     `<script>` and `<style>` bodies, where HEEx does not interpolate;
    #   * `.ex` and `.exs`: the start of a parsed Elixir expression (any node
    #     with a position), and code inside `~H` sigils as in `.heex`.
    #
    # String literals inside code are not code (their interpolations are).
    # A file that does not parse has no code.

    @doc "A function of a byte offset into `content`: whether Elixir code is there."
    def code?(content, path) do
      case Path.extname(path) do
        ext when ext in [".eex", ".leex"] -> in_ranges(eex_ranges(content))
        ".heex" -> in_ranges(heex_ranges(content))
        ext when ext in [".ex", ".exs"] -> module_code(content)
        _other -> fn _offset -> false end
      end
    end

    defp in_ranges(ranges),
      do: fn offset -> Enum.any?(ranges, fn {start, length} -> offset >= start and offset < start + length end) end

    ## EEx

    defp eex_ranges(text),
      do: text |> tags(0, []) |> Enum.flat_map(fn {start, length} -> code_ranges(text, start, length) end)

    defp tags(<<>>, _pos, acc), do: Enum.reverse(acc)

    defp tags(<<"<%", rest::binary>>, pos, acc) do
      case :binary.match(rest, "%>") do
        {length, 2} ->
          after_tag = drop(rest, length + 2)
          acc = if comment_tag?(rest), do: acc, else: [{pos + 2, length} | acc]
          tags(after_tag, pos + 2 + length + 2, acc)

        :nomatch ->
          Enum.reverse(acc)
      end
    end

    defp tags(<<_char, rest::binary>>, pos, acc), do: tags(rest, pos + 1, acc)

    defp comment_tag?(<<"#", _::binary>>), do: true
    defp comment_tag?(<<"!--", _::binary>>), do: true
    defp comment_tag?(_tag), do: false

    ## HEEx

    @raw_elements ~w(script style)

    defp heex_ranges(text) do
      text
      |> heex(0, :text, [])
      |> Enum.flat_map(fn {start, length} -> code_ranges(text, start, length) end)
    end

    defp heex(<<>>, _pos, _state, acc), do: Enum.reverse(acc)

    defp heex(<<"<%", _::binary>> = text, pos, state, acc) do
      case tags(text, 0, []) do
        [{2, length} | _] ->
          skip = 2 + length + 2
          rest = drop(text, skip)
          heex(rest, pos + skip, state, [{pos + 2, length} | acc])

        _comment_or_unclosed ->
          case :binary.match(text, "%>") do
            {at, 2} ->
              rest = drop(text, at + 2)
              heex(rest, pos + at + 2, state, acc)

            :nomatch ->
              Enum.reverse(acc)
          end
      end
    end

    defp heex(<<"<!--", rest::binary>>, pos, :text, acc) do
      case :binary.match(rest, "-->") do
        {at, 3} ->
          after_comment = drop(rest, at + 3)
          heex(after_comment, pos + 4 + at + 3, :text, acc)

        :nomatch ->
          Enum.reverse(acc)
      end
    end

    defp heex(<<"<", rest::binary>> = text, pos, :text, acc) do
      case Regex.run(~r/\A\/?([A-Za-z][\w.:-]*)/, rest) do
        [_match, name] ->
          raw =
            if String.downcase(name) in @raw_elements and not String.starts_with?(rest, "/"), do: String.downcase(name)

          after_lt = drop(text, 1)
          heex(after_lt, pos + 1, {:tag, raw}, acc)

        nil ->
          heex(rest, pos + 1, :text, acc)
      end
    end

    defp heex(<<"{", rest::binary>>, pos, state, acc) when state == :text or elem(state, 0) == :tag do
      case expression_length(rest, 1, 0) do
        {:ok, length} ->
          after_expression = drop(rest, length + 1)
          heex(after_expression, pos + 1 + length + 1, state, [{pos + 1, length} | acc])

        :error ->
          Enum.reverse(acc)
      end
    end

    defp heex(<<quote, rest::binary>>, pos, {:tag, _raw} = state, acc) when quote in [?", ?'] do
      case :binary.match(rest, <<quote>>) do
        {at, 1} ->
          after_value = drop(rest, at + 1)
          heex(after_value, pos + 1 + at + 1, state, acc)

        :nomatch ->
          Enum.reverse(acc)
      end
    end

    defp heex(<<">", rest::binary>>, pos, {:tag, nil}, acc), do: heex(rest, pos + 1, :text, acc)
    defp heex(<<">", rest::binary>>, pos, {:tag, raw}, acc), do: heex(rest, pos + 1, {:raw, raw}, acc)

    defp heex(<<"</", rest::binary>> = text, pos, {:raw, name} = state, acc) do
      if String.downcase(binary_part(rest, 0, min(byte_size(name), byte_size(rest)))) == name,
        do: heex(text, pos, :text, acc),
        else: heex(rest, pos + 2, state, acc)
    end

    defp heex(<<_char, rest::binary>>, pos, state, acc), do: heex(rest, pos + 1, state, acc)

    # The length of a `{...}` expression's body, given the text after `{`.
    defp expression_length(<<"}", _::binary>>, 1, length), do: {:ok, length}
    defp expression_length(<<"}", rest::binary>>, depth, length), do: expression_length(rest, depth - 1, length + 1)
    defp expression_length(<<"{", rest::binary>>, depth, length), do: expression_length(rest, depth + 1, length + 1)

    defp expression_length(<<?", rest::binary>>, depth, length) do
      case string_length(rest, 0) do
        {:ok, string} ->
          after_string = drop(rest, string + 1)
          expression_length(after_string, depth, length + 1 + string + 1)

        :error ->
          :error
      end
    end

    defp expression_length(<<_char, rest::binary>>, depth, length), do: expression_length(rest, depth, length + 1)
    defp expression_length(<<>>, _depth, _length), do: :error

    # The length of a string's body, given the text after its opening `"`.
    defp string_length(<<"\\", _escaped, rest::binary>>, length), do: string_length(rest, length + 2)
    defp string_length(<<?", _::binary>>, length), do: {:ok, length}
    defp string_length(<<_char, rest::binary>>, length), do: string_length(rest, length + 1)
    defp string_length(<<>>, _length), do: :error

    # The parts of a code range outside string literals, with the code of
    # their interpolations.
    defp code_ranges(text, start, length) do
      text |> binary_part(start, length) |> code_parts(start, start, [])
    end

    defp code_parts(<<>>, from, pos, acc), do: Enum.reverse(add_range(acc, from, pos))

    defp code_parts(<<?", rest::binary>>, from, pos, acc) do
      acc = add_range(acc, from, pos)
      {consumed, interpolations} = string_body(rest, pos + 1, 0, [])
      after_string = drop(rest, consumed)
      next = pos + 1 + consumed
      code_parts(after_string, next, next, Enum.reverse(interpolations) ++ acc)
    end

    defp code_parts(<<_char, rest::binary>>, from, pos, acc), do: code_parts(rest, from, pos + 1, acc)

    defp add_range(acc, from, pos) when pos > from, do: [{from, pos - from} | acc]
    defp add_range(acc, _from, _pos), do: acc

    # Bytes consumed by a string's body and closing quote, and the ranges of
    # its `#{...}` interpolations.
    defp string_body(<<"\\", _escaped, rest::binary>>, pos, consumed, acc),
      do: string_body(rest, pos + 2, consumed + 2, acc)

    defp string_body(<<?", _::binary>>, _pos, consumed, acc), do: {consumed + 1, acc}

    defp string_body(<<"\#{", rest::binary>>, pos, consumed, acc) do
      case expression_length(rest, 1, 0) do
        {:ok, length} ->
          after_interpolation = drop(rest, length + 1)
          string_body(after_interpolation, pos + 2 + length + 1, consumed + 2 + length + 1, [{pos + 2, length} | acc])

        :error ->
          {consumed + 2 + byte_size(rest), acc}
      end
    end

    defp string_body(<<_char, rest::binary>>, pos, consumed, acc), do: string_body(rest, pos + 1, consumed + 1, acc)
    defp string_body(<<>>, _pos, consumed, acc), do: {consumed, acc}

    defp drop(binary, count), do: binary_part(binary, count, byte_size(binary) - count)

    ## Elixir modules

    defp module_code(content) do
      case Sourceror.parse_string(content) do
        {:ok, ast} ->
          lines = {line_offsets(content), content |> String.split("\n") |> List.to_tuple()}
          {starts, sigils} = positions(ast, lines)
          starts = MapSet.new(starts)
          fn offset -> MapSet.member?(starts, offset) or Enum.any?(sigils, & &1.(offset)) end

        {:error, _error} ->
          fn _offset -> false end
      end
    end

    # The byte offset of each node with a position, and for each `~H` sigil a
    # test of whether an offset is code in its template.
    defp positions(ast, lines) do
      {_ast, found} =
        Macro.prewalk(ast, {[], []}, fn
          {:sigil_H, meta, [{:<<>>, string_meta, [template]}, _modifiers]} = node, {starts, sigils}
          when is_binary(template) ->
            {node, {starts, [sigil_code(template, meta, string_meta, lines) | sigils]}}

          {_form, meta, _args} = node, {starts, sigils} when is_list(meta) ->
            case offset(lines, meta[:line], meta[:column]) do
              nil -> {node, {starts, sigils}}
              offset -> {node, {[offset | starts], sigils}}
            end

          node, found ->
            {node, found}
        end)

      found
    end

    defp sigil_code(template, meta, string_meta, lines) do
      code? = in_ranges(heex_ranges(template))

      if meta[:delimiter] in [~s("""), "'''"] do
        # Heredoc lines start on the line after the sigil, without their indentation.
        indentation = string_meta[:indentation] || 0
        template_lines = line_offsets(template)
        first_line = meta[:line] + 1

        fn offset -> heredoc_code?(code?, offset, lines, template_lines, first_line, indentation) end
      else
        start = offset(lines, meta[:line], meta[:column])
        fn offset -> start != nil and offset >= start + 3 and code?.(offset - start - 3) end
      end
    end

    defp heredoc_code?(code?, offset, lines, template_lines, first_line, indentation) do
      with {line, column} <- position(elem(lines, 0), offset),
           index = line - first_line,
           true <- index >= 0 and index < tuple_size(template_lines) and column >= indentation do
        code?.(elem(template_lines, index) + column - indentation)
      else
        _ -> false
      end
    end

    defp line_offsets(text) do
      text
      |> String.split("\n")
      |> Enum.map_reduce(0, fn line, offset -> {offset, offset + byte_size(line) + 1} end)
      |> elem(0)
      |> List.to_tuple()
    end

    # Byte offset of a 1-based line and column; Elixir counts columns in
    # characters.
    defp offset({lines, texts}, line, column) when is_integer(line) and is_integer(column) and line >= 1 do
      if line <= tuple_size(lines) do
        elem(lines, line - 1) + byte_size(String.slice(elem(texts, line - 1), 0, column - 1))
      end
    end

    defp offset(_lines, _line, _column), do: nil

    # 1-based line and 0-based byte column of an offset.
    defp position(lines, offset) do
      index = lines |> Tuple.to_list() |> Enum.take_while(&(&1 <= offset)) |> length()
      if index > 0, do: {index, offset - elem(lines, index - 1)}
    end
  end
else
  defmodule Mix.Brando.Igniter.TemplateCode do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
