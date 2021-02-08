defmodule Brando.Villain.LiquexRenderer do
  alias Brando.Pages

  def render({:fragment_tag, [parent_key: parent_key, key: key, language: language]}, context) do
    {:ok, fragment} =
      Pages.get_page_fragment(%{matches: %{parent_key: parent_key, key: key, language: language}})

    {[fragment.html], context}
  end

  # Ignore this tag if we don't match
  def render(_, _), do: false
end
