defmodule Brando.Lexer.Render do
  @moduledoc false

  alias Brando.Lexer.Context

  @callback render({atom, any}, Context.t()) :: {any, Context.t()} | false

  @doc """
  Renders a Liquid AST `document` into an `iolist`
  A `context` is given to handle temporary contextual information for
  this render.
  """
  @spec render(iolist(), Brando.Lexer.document_t(), Context.t()) :: {iolist(), Context.t()}
  def render(content, [], context),
    do: {content |> Enum.reverse(), context}

  def render(content, [tag | tail], %{render_module: custom_module} = context) do
    [
      custom_module,
      Brando.Lexer.Render.Text,
      Brando.Lexer.Render.Object,
      Brando.Lexer.Render.ControlFlow,
      Brando.Lexer.Render.Variable,
      Brando.Lexer.Render.Iteration
    ]
    |> do_render(tag, context)
    |> case do
      {result, context} ->
        [result | content]
        |> render(tail, context)

      _ ->
        raise "No tag renderer found"
    end
  end

  defp do_render(modules, tag, context) do
    modules
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(& &1.render(tag, context))
  end
end
