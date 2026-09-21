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

  describe "rendered_text/2" do
    test "separates adjacent block elements instead of running them together" do
      entry = %{rendered_blocks: "<h2>Tittel</h2><p>Brødtekst</p>"}
      assert Value.rendered_text(entry) == "Tittel Brødtekst"
    end

    test "decodes entities and squeezes whitespace" do
      entry = %{rendered_blocks: "<p>Design   &amp;\n   strategi &lt;3</p>"}
      assert Value.rendered_text(entry) == "Design & strategi <3"
    end

    test "truncates to the requested length" do
      entry = %{rendered_blocks: "<p>#{String.duplicate("a", 200)}</p>"}

      assert Value.rendered_text(entry) == String.duplicate("a", 157) <> "..."
      assert Value.rendered_text(entry, length: 20) == String.duplicate("a", 17) <> "..."
    end

    test "reads an alternate block field" do
      entry = %{rendered_body: "<p>Fra body</p>", rendered_blocks: "<p>Fra blocks</p>"}
      assert Value.rendered_text(entry, field: :body) == "Fra body"
    end

    test "returns nil for empty, missing or markup-only content" do
      assert Value.rendered_text(%{rendered_blocks: nil}) == nil
      assert Value.rendered_text(%{rendered_blocks: ""}) == nil
      assert Value.rendered_text(%{rendered_blocks: "<div><br></div>"}) == nil
      assert Value.rendered_text(%{}) == nil
    end

    test "composes with fallback/1 so a filled meta_description still wins" do
      entry = %{meta_description: "Manuell beskrivelse", rendered_blocks: "<p>Fra blokker</p>"}

      assert Value.fallback([entry.meta_description, Value.rendered_text(entry)]) ==
               "Manuell beskrivelse"

      blank = %{meta_description: nil, rendered_blocks: "<p>Fra blokker</p>"}
      assert Value.fallback([blank.meta_description, Value.rendered_text(blank)]) == "Fra blokker"
    end
  end
end
