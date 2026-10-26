defmodule Brando.Villain.Tags.Fragment do
  @moduledoc false
  @behaviour Liquex.Tag

  alias Brando.Pages
  alias Brando.Villain.InertLiquid
  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:fragment)

  @impl true
  def render([parent_key: parent_key, key: key, language: language], context) do
    html = parent_key |> Pages.render_embedded_fragment(key, language) |> Phoenix.HTML.safe_to_string()
    {[markdown_braces(html, context)], context}
  end

  # The fragment's braces are encoded for the entry's Liquid pass. A Markdown
  # template's output has no such pass, so the `.md` shows them as written.
  defp markdown_braces(html, context) do
    if Brando.Villain.Markdown.template_context?(context), do: InertLiquid.decode(html), else: html
  end
end
