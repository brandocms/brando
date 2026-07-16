defmodule Brando.Villain.Tags.Fragment do
  @moduledoc false
  @behaviour Liquex.Tag

  alias Brando.Pages
  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:fragment)

  @impl true
  def render([parent_key: parent_key, key: key, language: language], context) do
    {:ok, fragment} =
      Pages.get_fragment(%{matches: %{parent_key: parent_key, key: key, language: language}})

    {[fragment.html], context}
  end
end
