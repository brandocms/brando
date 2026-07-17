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

  test "try_path traverses mixed maps, keyword lists, and indexed lists" do
    data = %{
      settings: [
        seo: %{
          images: [
            %{"url" => "/images/cover.jpg"}
          ]
        }
      ]
    }

    assert Value.try_path(data, [:settings, :seo, :images, 0, "url"]) ==
             "/images/cover.jpg"

    assert Value.try_path([%{name: "First"}], [0, :name]) == "First"
  end

  test "try_path returns nil instead of raising on incompatible path steps" do
    assert Value.try_path(%{title: "Text"}, [:title, :missing]) == nil
    assert Value.try_path(%{items: []}, [:items, 4, :title]) == nil
    assert Value.try_path([%{title: "Text"}], [:title]) == nil
    assert Value.try_path([title: "Text"], [0]) == nil
    assert Value.try_path(%{items: [%{title: "Text"}]}, [:items, :title]) == nil
  end

  test "fallback preserves false, zero, and empty values" do
    data = %{enabled: false, count: 0, title: ""}

    assert Value.fallback(data, [:enabled, :count]) == false
    assert Value.fallback(data, [:missing, :count]) == 0
    assert Value.fallback(data, [:missing, :title]) == ""
  end

  test "locale encoding preserves unknown locale codes" do
    assert Value.encode_locale("en") == "en_US"
    assert Value.encode_locale("no") == "nb_NO"
    assert Value.encode_locale("nb") == "nb_NO"
    assert Value.encode_locale("nn") == "nn_NO"
    assert Value.encode_locale("sv") == "sv"
  end
end
