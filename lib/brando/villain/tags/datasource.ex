defmodule Brando.Villain.Tags.Datasource do
  @moduledoc false
  @behaviour Liquex.Tag

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:datasource)

  @impl true
  def render(_, context), do: {[""], context}
end
