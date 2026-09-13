defmodule BrandoAdmin.Components.Form.Block.LiquidPreview do
  @moduledoc false

  @regions ~w(if unless for hide)
  @end_tags Map.new(@regions, &{"end" <> &1, &1})
  @tag_name ~r/\A{%-?\s*(\w+|#)/
  @end_raw ~r/{%-?\s*endraw\s*-?%}/

  # These non-Liquid substitutions retain the editor's existing behavior.
  @cleanup ~r/(<img.*?src="{{(?:-)? .*? (?:-)?}}".*?>)|(data-moonwalk-run(?:="\w+")|data-moonwalk-run|data-moonwalk-section(?:="\w+")|data-moonwalk-section|href(?:="[a-zA-Z0-9{}|._\s]+")|id(?:="{{[a-zA-Z0-9{}._\s]+}}"))/s

  @type error ::
          {:unclosed_tag, String.t()}
          | {:unexpected_end, String.t()}
          | {:mismatched_end, String.t(), String.t()}
          | :unterminated_tag
          | :unterminated_output

  @doc """
  Removes complete editor-hidden Liquid regions without evaluating expressions.

  Source outside those regions is preserved until the existing HTML cleanup pass.
  Quoted strings, output tokens, and raw/comment bodies cannot change the region
  stack. Malformed boundaries return an error, never partially stripped HTML.
  """
  @spec strip_logic(String.t()) :: {:ok, String.t()} | {:error, error()}
  def strip_logic(code) do
    with {:ok, stripped} <- scan(code, [], []) do
      {:ok, Regex.replace(@cleanup, stripped, "")}
    end
  end

  @ref_tag ~r/{%-?\s*ref\s+refs\.(\w+)/

  @doc """
  Names the refs that only appear inside regions `strip_logic/1` removes.

  Such a ref never gets an editable slot in the block editor: the region it
  sits in is gone before the code is split into slots. A ref that is also
  rendered at the top level keeps its slot and is not reported. Malformed
  code reports nothing — the preview already surfaces that error.

  Uses the region scan alone, not the HTML cleanup pass, so the answer depends
  only on where the ref sits in the Liquid structure.
  """
  @spec stripped_refs(String.t() | nil) :: [String.t()]
  def stripped_refs(nil), do: []

  def stripped_refs(code) when is_binary(code) do
    case scan(code, [], []) do
      {:ok, visible} ->
        reachable = MapSet.new(ref_names(visible))

        code
        |> ref_names()
        |> Enum.reject(&MapSet.member?(reachable, &1))
        |> Enum.uniq()

      {:error, _} ->
        []
    end
  end

  defp ref_names(code) do
    @ref_tag
    |> Regex.scan(code, capture: :all_but_first)
    |> List.flatten()
  end

  defp scan(code, stack, acc) do
    case :binary.match(code, ["{%", "{{"]) do
      :nomatch ->
        finish(code, stack, acc)

      {offset, _length} ->
        {text, remaining} = :erlang.split_binary(code, offset)
        acc = keep(text, stack, acc)

        with {:ok, name, token, rest} <- take_token(remaining) do
          scan_token(name, token, rest, stack, acc)
        end
    end
  end

  defp scan_token(name, token, rest, stack, acc) when name in ["raw", "comment"] do
    with {:ok, size} <- opaque_length(rest, name) do
      {body, remaining} = :erlang.split_binary(rest, size)
      scan(remaining, stack, keep([token, body], stack, acc))
    end
  end

  defp scan_token(name, _token, rest, stack, acc) when name in @regions do
    scan(rest, [name | stack], acc)
  end

  defp scan_token(name, token, rest, stack, acc) do
    case Map.fetch(@end_tags, name) do
      {:ok, opening} -> close_region(name, opening, rest, stack, acc)
      :error when name == "assign" -> scan(rest, stack, acc)
      :error -> scan(rest, stack, keep(token, stack, acc))
    end
  end

  # Raw ends at its first closing marker, even when its contents are not Liquid.
  defp opaque_length(code, "raw") do
    case Regex.run(@end_raw, code, return: :index) do
      [{offset, length}] -> {:ok, offset + length}
      nil -> {:error, {:unclosed_tag, "raw"}}
    end
  end

  defp opaque_length(code, "comment"), do: comment_length(code, 0)

  # Comments can contain other comments and raw regions. Their tokens must not
  # affect the surrounding if/for/hide stack, including after an inner comment.
  defp comment_length(code, length) do
    case :binary.match(code, ["{%", "{{"]) do
      :nomatch ->
        {:error, {:unclosed_tag, "comment"}}

      {offset, _} ->
        {_text, remaining} = :erlang.split_binary(code, offset)

        with {:ok, name, token, rest} <- take_token(remaining) do
          length = length + offset + byte_size(token)

          case name do
            "endcomment" ->
              {:ok, length}

            name when name in ["raw", "comment"] ->
              with {:ok, size} <- opaque_length(rest, name) do
                {_body, tail} = :erlang.split_binary(rest, size)
                comment_length(tail, length + size)
              end

            _ ->
              comment_length(rest, length)
          end
        end
    end
  end

  defp close_region(_name, opening, rest, [opening | stack], acc), do: scan(rest, stack, acc)
  defp close_region(name, _opening, _rest, [], _acc), do: {:error, {:unexpected_end, name}}

  defp close_region(name, _opening, _rest, [expected | _], _acc) do
    {:error, {:mismatched_end, "end" <> expected, name}}
  end

  defp take_token("{%" <> body = code) do
    name =
      case Regex.run(@tag_name, code, capture: :all_but_first) do
        [name] -> name
        nil -> nil
      end

    # Inline comments also allow unmatched quotes in their contents.
    length =
      if name == "#" do
        case :binary.match(body, "%}") do
          {offset, 2} -> {:ok, offset + 2}
          :nomatch -> {:error, :unterminated_tag}
        end
      else
        token_length(body, :tag, nil, 0)
      end

    extract_token(code, name, length)
  end

  defp take_token("{{" <> body = code) do
    extract_token(code, nil, token_length(body, :output, nil, 0))
  end

  defp extract_token(code, name, {:ok, length}) do
    size = length + 2
    {token, rest} = :erlang.split_binary(code, size)
    {:ok, name, token, rest}
  end

  defp extract_token(_code, _name, {:error, _} = error), do: error

  defp token_length("", :tag, _quote, _length), do: {:error, :unterminated_tag}
  defp token_length("", :output, _quote, _length), do: {:error, :unterminated_output}
  defp token_length("%}" <> _rest, :tag, nil, length), do: {:ok, length + 2}
  defp token_length("}}" <> _rest, :output, nil, length), do: {:ok, length + 2}

  defp token_length(<<quote, rest::binary>>, kind, nil, length) when quote in [?", ?'] do
    token_length(rest, kind, quote, length + 1)
  end

  defp token_length(<<quote, rest::binary>>, kind, quote, length) do
    token_length(rest, kind, nil, length + 1)
  end

  defp token_length(<<_byte, rest::binary>>, kind, quote, length) do
    token_length(rest, kind, quote, length + 1)
  end

  defp keep(text, [], acc), do: [text | acc]
  defp keep(_text, _stack, acc), do: acc

  defp finish(code, [], acc), do: {:ok, IO.iodata_to_binary(Enum.reverse([code | acc]))}
  defp finish(_code, [name | _], _acc), do: {:error, {:unclosed_tag, name}}
end
