defmodule Brando.Villain.Tags.Output do
  @moduledoc """
  Liquid's `{{ x }}` and `{% echo x %}`, rendered by Liquex's own tags, with
  the start of what they print closed (`Brando.Villain.InertLiquid.close_delimiter/1`)
  where the output printed right before it ended in a `{`.

  A template writes a brace right before a value with `{{ "{" }}{{ x }}`. A
  value starting with `%` or `{` would make a Liquid delimiter with it, which
  the final pass runs or fails to parse. Only a value right after such an
  output is closed, with no text of the template between them, so a template
  printing JSON after a brace and some text (`{{ "{" }}"a": {{ json | raw }}}`)
  keeps it.

  The parser marks each output with whether template text comes right before
  and after it (`mark_joins/5`). The output before it, in a loop's last pass
  or before a tag, is known only when rendering: it is kept in the context's
  private data.
  """

  alias Brando.Villain.InertLiquid
  alias Brando.Villain.Markdown
  alias Liquex.Context

  @open :brando_output_open_brace
  @outputs [Liquex.Tag.ObjectTag, Liquex.Tag.EchoTag]

  @doc """
  A `post_traverse` for a document's nodes, in the reverse order NimbleParsec
  gives them: each output's tag in this module, with its neighbours.
  """
  def mark_joins(rest, nodes, context, _line, _offset) do
    {rest, nodes |> Enum.reverse() |> mark([]) |> Enum.reverse(), context}
  end

  defp mark([], _previous), do: []

  defp mark([{{:tag, tag}, contents} | rest], previous) when tag in @outputs do
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
    {output, context} = tag.render(contents, context)
    output = IO.iodata_to_binary(output)

    output =
      if not after_text? and open?(context) and not Markdown.template_context?(context),
        do: InertLiquid.close_delimiter(output),
        else: output

    {output, put_open(context, not before_text? and String.ends_with?(output, "{"))}
  end

  @doc "`context` for a document rendered on its own, with no output before it."
  def reset(%Context{} = context), do: put_open(context, false)

  defp open?(%Context{private: private}), do: Map.get(private, @open, false)

  defp put_open(%Context{private: private} = context, open?) do
    if Map.get(private, @open, false) == open?,
      do: context,
      else: %{context | private: Map.put(private, @open, open?)}
  end
end
