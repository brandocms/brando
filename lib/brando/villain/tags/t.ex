defmodule Brando.Villain.Tags.T do
  @moduledoc """
  {% t no 'Norsk' %}
  """
  @behaviour Liquex.Tag

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:translation)

  @impl true
  def render([language: language, string: string], context) do
    ctx_language = Access.get(context, "language")

    if language == ctx_language do
      {[string], context}
    else
      {[], context}
    end
  end
end
