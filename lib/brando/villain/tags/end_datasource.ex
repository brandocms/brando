defmodule Brando.Villain.Tags.EndDatasource do
  @moduledoc false
  @behaviour Liquex.Tag

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:end_datasource)

  @impl true
  def render(_, context), do: {[""], context}
end
