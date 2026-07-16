defmodule Brando.Villain.Tags.EndHide do
  @moduledoc false
  @behaviour Liquex.Tag

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:end_hide)

  @impl true
  def render(_, context), do: {[""], context}
end
