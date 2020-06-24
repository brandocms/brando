defmodule Brando.Lexer.Render.ControlFlow do
  @moduledoc false

  alias Brando.Lexer.Expression

  @behaviour Brando.Lexer.Render

  @impl Brando.Lexer.Render
  def render({:control_flow, tag}, context), do: do_render(tag, context)
  def render(_, _), do: false

  defp do_render(list, context, match \\ nil)

  defp do_render([{tag, [expression: expression, contents: contents]} | tail], context, _)
       when tag in [:if, :elsif] do
    if Expression.eval(expression, context) do
      Brando.Lexer.render(contents, context)
    else
      do_render(tail, context)
    end
  end

  defp do_render([{:else, [contents: contents]} | _tail], context, _),
    do: Brando.Lexer.render(contents, context)

  defp do_render([], context, _), do: {[], context}
end
