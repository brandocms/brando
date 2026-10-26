defmodule Brando.Villain.Parser.EscapingTest do
  # Settings the parser puts into attributes are escaped for them, and
  # addresses with a script or unknown scheme are left out, whoever wrote them.
  use ExUnit.Case, async: true

  alias Brando.Villain.Parser

  @breakout ~s(t"><img src=x onerror=document.title=1><b class="x)

  defp html(iodata), do: IO.iodata_to_binary(iodata)

  defp count(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  test "a header's class, id and anchor are escaped" do
    for data <- [%{class: @breakout}, %{id: @breakout}] do
      out = html(Parser.header(Map.merge(%{text: "Rooms", level: 2}, data), %{}))
      assert count(out, "img") == 0
      assert count(out, "h2") == 1
    end

    out = html(Parser.header(%{text: "Rooms", level: 2, anchor: @breakout}, %{}))
    assert count(out, "img") == 0
  end

  test "a header link must have an allowed scheme, and is escaped" do
    out = html(Parser.header(%{text: "Rooms", level: 2, link: "javascript:document.title=1"}, %{}))
    assert out == "<h2>Rooms</h2>"

    out = html(Parser.header(%{text: "Rooms", level: 2, link: ~s(/rooms" onclick="x)}, %{}))
    assert count(out, "a[onclick]") == 0

    out = html(Parser.header(%{text: "Rooms", level: 2, class: "big", id: "rooms", link: "/rooms?a=1&b=2"}, %{}))
    assert out == ~s(<a href="/rooms?a=1&amp;b=2"><h2 class="big" id="rooms">Rooms</h2></a>)
  end

  test "a map embed address is escaped, and must have an allowed scheme" do
    url = ~s(https://www.google.com/maps/embed?pb=1"/onload="document.title=1)
    out = Parser.map(%{embed_url: url, source: :gmaps}, %{})
    assert count(out, "iframe") == 1
    assert count(out, "iframe[onload]") == 0

    assert Parser.map(%{embed_url: "javascript:document.title=1", source: :gmaps}, %{}) == ""
    assert Parser.map(%{embed_url: "javascript&#58;document.title=1", source: :gmaps}, %{}) =~ "javascript&amp;#58;"
    assert Parser.map(%{embed_url: nil, source: :gmaps}, %{}) == ""
  end

  test "a video embed's id cannot end its address" do
    out = Parser.video(%{remote_id: ~s(abc"/onload="document.title=1), type: :youtube, autoplay: false}, %{})
    assert count(out, "iframe") == 1
    assert count(out, "iframe[onload]") == 0
    assert out =~ "autoplay=0&controls=0"
  end

  test "a text type, a list's and a gallery's classes and ids are escaped" do
    assert count(Parser.text(%{text: "<p>x</p>", type: @breakout}, %{}), "img") == 0

    list = Parser.list(%{rows: [%{class: @breakout, value: "x"}], id: @breakout, class: @breakout}, %{})
    assert count(list, "img") == 0
    assert count(list, "li") == 1
  end
end
