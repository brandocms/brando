defmodule Brando.Blueprint.ValueTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Value

  doctest Value

  test "fallback can strip and truncate values resolved by path" do
    long_html = "<p>#{String.duplicate("a", 200)}</p>"

    assert Value.fallback(%{description: long_html}, [{:strip_tags_and_truncate, :description}]) ==
             String.duplicate("a", 157) <> "..."
  end

  test "the compatibility facade retains value helper behavior" do
    data = %{title: "<strong>Title</strong>"}

    assert Brando.Blueprint.Utils.fallback(data, [{:strip_tags, :title}]) == "Title"
    assert Brando.Blueprint.Utils.try_path(data, [:title]) == "<strong>Title</strong>"
  end
end
