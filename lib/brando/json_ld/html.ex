defmodule Brando.JSONLD.HTML do
  @moduledoc """
  HTML functions for rendering JSON-LD data as a single @graph document.
  """

  import Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  alias Brando.JSONLD

  @doc """
  Renders all JSON-LD entities as a single `@graph` script tag.

  The entities come from `Brando.JSONLD.Graph.entities/1`.
  """
  def render_json_ld(%{conn: %{assigns: %{language: _}} = conn} = assigns) do
    case JSONLD.Graph.entities(conn) do
      [] ->
        ~H""

      entities ->
        assigns = assign(assigns, :graph_json, encode_graph(entities))

        ~H"""
        <script type="application/ld+json">
          <%= @graph_json %>
        </script>
        """
    end
  end

  def render_json_ld(assigns), do: ~H""

  # Safe: to_graph_json returns JSON from Jason.encode!/1 — no user HTML content.
  # Content is injected inside <script type="application/ld+json"> which is not
  # parsed as HTML by browsers.
  defp encode_graph(entities), do: raw(JSONLD.to_graph_json(entities))
end
