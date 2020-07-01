defmodule Brando.Lexer do
  alias Brando.Lexer.Context

  @type document_t :: [
          {:control_flow, nonempty_maybe_improper_list}
          | {:iteration, [...]}
          | {:object, [...]}
          | {:text, any}
          | {:variable, [...]}
        ]

  @spec parse(String.t(), module) :: {:ok, document_t} | {:error, String.t(), pos_integer()}
  @doc """
  Parses a liquid `template` string using the given `parser`.
  Returns a liquid AST document or the parser error
  """
  def parse(template, parser \\ Brando.Lexer.Parser) do
    case parser.parse(template) do
      {:ok, content, _, _, _, _} -> {:ok, content}
      {:error, reason, _, _, {line, _}, _} -> {:error, reason, line}
    end
  end

  def render(document, context \\ %Context{}),
    do: Brando.Lexer.Render.render([], document, context)

  def parse_and_render(html, context) do
    {:ok, parsed_doc, _, _, _, _} = Brando.Lexer.Parser.parse(html)
    {result, _} = render(parsed_doc, context)
    Enum.join(result)
  end
end
