defmodule Brando.Villain.Tags.EndEditable do
  @moduledoc false
  @behaviour Liquex.Tag

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:end_editable)

  @impl true
  def render(_, context), do: Brando.Villain.Tags.Editable.close(context)
end
