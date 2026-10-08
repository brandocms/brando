defmodule Brando.JSONLD.PageArticleTest do
  # Builds the whole @graph, which reads the cached identity.
  use Brando.ConnCase, async: false

  alias Brando.JSONLD.Graph
  alias Brando.Pages.Page

  defp page(json_ld_type) do
    %Page{
      id: 41,
      title: "Opening hours",
      uri: "opening-hours",
      language: :en,
      status: :published,
      json_ld_type: json_ld_type,
      meta_description: "When we are open",
      inserted_at: ~N[2026-01-02 10:00:00],
      updated_at: ~N[2026-01-03 10:00:00],
      meta_image: nil
    }
  end

  defp graph(page) do
    Page
    |> Graph.for_entry(page, path: "/opening-hours")
    |> Jason.decode!()
    |> Map.fetch!("@graph")
  end

  defp types(graph), do: Enum.map(graph, & &1["@type"])

  test "a page emits its Article next to the WebPage" do
    graph = graph(page("WebPage"))

    assert "WebPage" in types(graph)
    assert %{"@id" => id, "headline" => "Opening hours"} = Enum.find(graph, &(&1["@type"] == "Article"))
    assert String.ends_with?(id, "#article")
  end

  test "a page type types the page, and the Article stays an Article" do
    graph = graph(page("ContactPage"))

    assert "ContactPage" in types(graph)
    assert "Article" in types(graph)
    refute "WebPage" in types(graph)
    assert Enum.count(graph, &(&1["@type"] == "ContactPage")) == 1
  end
end
