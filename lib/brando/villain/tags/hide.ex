defmodule Brando.Villain.Tags.Hide do
  @moduledoc false
  @behaviour Liquex.Tag

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:hide)

  @impl true
  def render(_, context), do: {[""], context}
end
