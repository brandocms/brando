defmodule Brando.Villain.Tags.Fragment do
  @moduledoc false
  @behaviour Liquex.Tag

  alias Brando.Pages
  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:fragment)

  @impl true
  def render([parent_key: parent_key, key: key, language: language], context) do
    html = parent_key |> Pages.render_embedded_fragment(key, language) |> Phoenix.HTML.safe_to_string()
    {[html], context}
  end
end
