defmodule Brando.Lexer.Render.Text do
  @behaviour Brando.Lexer.Render

  @impl Brando.Lexer.Render
  def render({:text, text}, context), do: {text, context}
  def render(_, _), do: false
end
