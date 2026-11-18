defmodule BrandoAdmin.Components.Form.Block.LiquidPreview do
  @moduledoc false

  # Regions whose contents depend on evaluation. The preview shows none of
  # their branches, as Liquid would show at most one of them.
  @regions ~w(if unless case for tablerow capture hide)
  @end_tags Map.new(@regions, &{"end" <> &1, &1})
  @tag_name ~r/\A{%-?\s*(\w+|#)/
  @end_raw ~r/{%-?\s*endraw\s*-?%}/
  # A brace that opens a Liquid delimiter, or ends a body and could open one
  # with the text after it.
  @liquid_open ~r/{(?=[{%]|\z)/

  # The tags `Block.liquid_splits/3` turns into a part of the preview: ref slots
  # and pictures, and the datasource region it removes. Every other tag would
  # print as its own source text, so the preview drops it.
  @preview_tags ~w(ref headless_ref picture datasource enddatasource)

  # These non-Liquid substitutions retain the editor's existing behavior.
  @cleanup ~r/(<img.*?src="{{(?:-)? .*? (?:-)?}}".*?>)|(data-moonwalk-run(?:="\w+")|data-moonwalk-run|data-moonwalk-section(?:="\w+")|data-moonwalk-section|href(?:="[a-zA-Z0-9{}|._\s]+")|id(?:="{{[a-zA-Z0-9{}._\s]+}}"))/s

  @type error ::
          {:unclosed_tag, String.t()}
          | {:unexpected_end, String.t()}
          | {:mismatched_end, String.t(), String.t()}
          | :unterminated_tag
          | :unterminated_output

  @doc """
  Removes the Liquid the block editor's preview cannot show, without
  evaluating expressions.

  Complete `if`, `unless`, `case`, `for`, `tablerow`, `capture` and `hide`
  regions go with all their branches. Comments go with their bodies. A raw
  region keeps its body as printed text. Of the other tags, only those
  `Block.liquid_splits/3` renders are kept: `ref`, `headless_ref`, `picture`
  and `datasource`. Markup and `{{ … }}` outside the regions are preserved
  until the existing HTML cleanup pass.

  Quoted strings, output tokens, and raw/comment bodies cannot change the region
  stack. Malformed boundaries return an error, never partially stripped HTML.
  """
  @spec strip_logic(String.t()) :: {:ok, String.t()} | {:error, error()}
  def strip_logic(code) do
    with {:ok, segments} <- scan(code, [], []) do
      {:ok, Regex.replace(@cleanup, render(segments, :preview), "")}
    end
  end

  @ref_tag ~r/{%-?\s*ref\s+refs\.(\w+)/
  @slot_tag ~r/{%-?\s*(?:ref|headless_ref)\s+refs\.(\w+)/

  @doc """
  Names the refs that only appear inside regions `strip_logic/1` removes.

  Such a ref never gets an editable slot in the block editor: the region it
  sits in is gone before the code is split into slots. A ref that is also
  rendered at the top level, or declared there with `headless_ref`, keeps its
  slot and is not reported. Malformed code reports nothing — the preview
  already surfaces that error.

  Uses the region scan alone, not the HTML cleanup pass or the tags and
  comments the preview drops outside regions, so the answer depends only on
  where the ref sits in the region structure.
  """
  @spec stripped_refs(String.t() | nil) :: [String.t()]
  def stripped_refs(nil), do: []

  def stripped_refs(code) when is_binary(code) do
    case scan(code, [], []) do
      {:ok, segments} ->
        visible = render(segments, :source)
        reachable = MapSet.new(names(@slot_tag, visible))

        @ref_tag
        |> names(code)
        |> Enum.reject(&MapSet.member?(reachable, &1))
        |> Enum.uniq()

      {:error, _} ->
        []
    end
  end

  defp names(tag, code) do
    tag
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

  # Outside regions, the scan keeps a segment per piece of source: a binary
  # both views show, or `{preview, source}` where the preview shows something
  # other than the source. `stripped_refs/1` reads the source view.
  defp scan_token("comment", token, rest, stack, acc) do
    with {:ok, size} <- opaque_length(rest, "comment") do
      {body, remaining} = :erlang.split_binary(rest, size)
      scan(remaining, stack, keep({"", [token, body]}, stack, acc))
    end
  end

  # A raw body prints as written, so the brace opening each Liquid delimiter in
  # it is escaped: the preview's splits would otherwise turn `{{ x }}` or
  # `{% ref … %}` into a variable or a ref slot. `&#123;` reads back as `{` in
  # text and attributes. Other braces stay, as `<style>` and `<script>` bodies
  # do not decode character references.
  defp scan_token("raw", token, rest, stack, acc) do
    with {:ok, offset, length} <- end_raw(rest) do
      {body, remaining} = :erlang.split_binary(rest, offset + length)
      text = Regex.replace(@liquid_open, binary_part(rest, 0, offset), "&#123;")
      scan(remaining, stack, keep({text, [token, body]}, stack, acc))
    end
  end

  defp scan_token(name, _token, rest, stack, acc) when name in @regions do
    scan(rest, [name | stack], acc)
  end

  defp scan_token(name, token, rest, stack, acc) do
    case Map.fetch(@end_tags, name) do
      {:ok, opening} -> close_region(name, opening, rest, stack, acc)
      :error -> scan(rest, stack, keep_tag(name, token, stack, acc))
    end
  end

  defp keep_tag(_name, "{{" <> _ = output, stack, acc), do: keep(output, stack, acc)
  defp keep_tag("assign", _token, _stack, acc), do: acc
  defp keep_tag(name, token, stack, acc) when name in @preview_tags, do: keep(token, stack, acc)
  defp keep_tag(_name, token, stack, acc), do: keep({"", token}, stack, acc)

  defp opaque_length(code, "raw") do
    with {:ok, offset, length} <- end_raw(code), do: {:ok, offset + length}
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
          continue_comment(name, rest, length + offset + byte_size(token))
        end
    end
  end

  defp continue_comment("endcomment", _rest, length), do: {:ok, length}

  defp continue_comment(name, rest, length) when name in ["raw", "comment"] do
    with {:ok, size} <- opaque_length(rest, name) do
      {_body, tail} = :erlang.split_binary(rest, size)
      comment_length(tail, length + size)
    end
  end

  defp continue_comment(_name, rest, length), do: comment_length(rest, length)

  # Raw ends at its first closing marker, even when its contents are not Liquid.
  defp end_raw(code) do
    case Regex.run(@end_raw, code, return: :index) do
      [{offset, length}] -> {:ok, offset, length}
      nil -> {:error, {:unclosed_tag, "raw"}}
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

  defp finish(code, [], acc), do: {:ok, Enum.reverse([code | acc])}
  defp finish(_code, [name | _], _acc), do: {:error, {:unclosed_tag, name}}

  defp render(segments, view) do
    segments
    |> Enum.map(fn
      {preview, _source} when view == :preview -> preview
      {_preview, source} -> source
      text -> text
    end)
    |> IO.iodata_to_binary()
  end
end
