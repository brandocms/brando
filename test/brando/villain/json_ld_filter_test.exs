defmodule Brando.Villain.JSONLDFilterTest do
  use ExUnit.Case, async: false

  alias Brando.JSONLD.CollectionTest.Thing
  alias Brando.Villain.Filters

  defp context(assigns \\ %{}) do
    Liquex.Context.new(Map.merge(%{"url" => "/things", "language" => "no"}, assigns))
  end

  defp entries, do: [%Thing{id: 1, title: "A", slug: "a"}, %Thing{id: 2, title: "B", slug: "b"}]

  test "emits an ItemList for the entries" do
    html = Filters.json_ld(entries(), context())

    assert html =~ ~s(<script type="application/ld+json">)
    assert html =~ ~s("@type":"ItemList")
    assert html =~ ~s("numberOfItems":2)
  end

  test "types the items when given a type" do
    html = Filters.json_ld(entries(), "CreativeWork", context())
    assert html =~ ~s("@type":"CreativeWork")
  end

  test "wraps in a CollectionPage from the render context with the page flag" do
    html = Filters.json_ld(entries(), "Article", "page", context())

    assert html =~ ~s("@type":"CollectionPage")
    assert html =~ ~s("inLanguage":"no")
    assert html =~ ~s(/things/#collectionpage")
  end

  test "the page flag works without a type" do
    html = Filters.json_ld(entries(), "page", context())
    assert html =~ ~s("@type":"CollectionPage")
    refute html =~ ~s("@type":"page")
  end

  test "emits nothing for an empty collection" do
    assert Filters.json_ld([], context()) == ""
  end

  test "renders raw through a Liquid template" do
    {:ok, parsed} = Liquex.parse(~s({{ entries | json_ld: "CreativeWork" }}), Brando.Villain.LiquexParser)

    ctx =
      Brando.Villain.get_base_context()
      |> Liquex.Context.assign("url", "/things")
      |> Liquex.Context.assign("entries", entries())

    {result, _} = Liquex.Render.render!([], parsed, ctx)
    html = result |> Enum.join() |> String.trim()

    assert String.starts_with?(html, ~s(<script type="application/ld+json">))
    refute html =~ "&lt;"
    assert html =~ ~s("@type":"CreativeWork")
  end
end
