defmodule Brando.Lexer.Render.Object do
  @moduledoc false

  alias Brando.Lexer.Argument
  alias Brando.Lexer.Context

  @behaviour Brando.Lexer.Render

  @impl Brando.Lexer.Render
  @spec render(any, Context.t()) :: {String.t(), Context.t()}
  def render({:object, tag}, context), do: do_render(tag, context)

  def render(_, _), do: false

  def do_render([argument, filters: filters], %Context{} = context) do
    {argument
     |> List.wrap()
     |> Argument.eval(context)
     |> process_filters(filters, context)
     |> to_string(), context}
  end

  @spec process_filters(any, [any], Context.t()) :: any
  defp process_filters(value, filters, %Context{filter_module: filter_module} = context) do
    filters
    |> Enum.reduce(value, fn filter, memo ->
      memo
      |> filter_module.apply(filter, context)
    end)
  end
end
