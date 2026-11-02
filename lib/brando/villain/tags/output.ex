defmodule Brando.Villain.Tags.Output do
  @moduledoc """
  Renders each tag of a template, `{{ x }}` and `{% echo x %}` included, with
  its own renderer, and closes the start of what it prints
  (`Brando.Villain.InertLiquid.close_delimiter/1`) where the template printed a
  `{` right before it.

  A template writes a brace right before a value with `{{ "{" }}{{ x }}`. A
  value starting with `%` or `{` would make a Liquid delimiter with it, which
  the final pass runs or fails to parse. Only what is printed right after such
  a brace is closed, with no text of the template between them, so a template
  printing JSON after a brace and some text (`{{ "{" }}"a": {{ json | raw }}}`)
  keeps it.

  The parser wraps each tag in this one, marked with whether template text
  comes right before and after it (`mark_joins/5`). Whether what was printed
  last ends in a `{` is kept in the context's private data: a tag that prints
  something sets it from its output, one that prints nothing (an empty value,
  `assign`, `capture`) leaves it as it was. A tag's body starts from what came
  before the tag, a capture's and a tablerow's from nothing.
  """

  alias Brando.Villain.InertLiquid
  alias Brando.Villain.Markdown
  alias Liquex.Context

  @open :brando_output_open_brace
  @body_after_markup [Liquex.Tag.CaptureTag, Liquex.Tag.TablerowTag]

  @doc """
  A `post_traverse` for a document's nodes, in the reverse order NimbleParsec
  gives them: each tag in this one, with its neighbours.
  """
  def mark_joins(rest, nodes, context, _line, _offset) do
    {rest, nodes |> Enum.reverse() |> mark([]) |> Enum.reverse(), context}
  end

  defp mark([], _previous), do: []

  defp mark([{{:tag, tag}, contents} | rest], previous) do
    node =
      {{:tag, __MODULE__},
       [
         tag: tag,
         contents: contents,
         after_text: match?([{:text, _} | _], previous),
         before_text: match?([{:text, _} | _], rest)
       ]}

    [node | mark(rest, [node])]
  end

  defp mark([node | rest], _previous), do: [node | mark(rest, [node])]

  def render([tag: tag, contents: contents, after_text: after_text?, before_text: before_text?], context) do
    open? = not after_text? and open?(context)

    # What a tag's body prints first follows what came before the tag, except a
    # capture's, which goes into a variable, and a tablerow's, after its cell
    case tag.render(contents, put_open(context, open? and tag not in @body_after_markup)) do
      {output, %Context{} = rendered} -> printed(to_binary(output), rendered, open?, before_text?)
      # `break` and `continue`, which the loop around them handles
      other -> other
    end
  end

  @doc """
  A parsed document with each tag as Liquex's own grammar gives it, without
  this one around it: for comparing a document's nodes.
  """
  def unwrap({{:tag, __MODULE__}, [tag: tag, contents: contents, after_text: _, before_text: _]}),
    do: {{:tag, tag}, unwrap(contents)}

  def unwrap(list) when is_list(list), do: Enum.map(list, &unwrap/1)
  def unwrap({key, value}), do: {unwrap(key), unwrap(value)}
  def unwrap(other), do: other

  @doc "`context` for a document rendered on its own, with nothing printed before it."
  def reset(%Context{} = context), do: put_open(context, false)

  # As the rendered document is joined: a tag may print `nil` (an empty ref)
  defp to_binary(output) when is_binary(output), do: output
  defp to_binary(output) when is_list(output), do: IO.chardata_to_string(output)
  defp to_binary(output), do: to_string(output)

  # Nothing reached the page: what was printed before still ends it
  defp printed("", context, open?, _before_text?), do: {"", put_open(context, open?)}

  defp printed(output, context, open?, before_text?) do
    output =
      if open? and not Markdown.template_context?(context),
        do: InertLiquid.close_delimiter(output),
        else: output

    {output, put_open(context, not before_text? and String.ends_with?(output, "{"))}
  end

  defp open?(%Context{private: private}), do: Map.get(private, @open, false)

  defp put_open(%Context{private: private} = context, open?) do
    if Map.get(private, @open, false) == open?,
      do: context,
      else: %{context | private: Map.put(private, @open, open?)}
  end
end
