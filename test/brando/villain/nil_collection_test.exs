defmodule Brando.Villain.NilCollectionTest do
  # A list that is nil reads as an empty list, as in standard Liquid: a loop
  # over it runs zero times (its `else` branch renders), and the collection
  # filters give an empty list. Anything else that is no list still raises.
  use Brando.ConnCase, async: true

  defp render(template), do: Brando.Villain.parse_and_render(template, Brando.Villain.get_base_context())

  describe "a for loop over nil" do
    test "runs zero times, and the rest of the template renders" do
      assert render("<p>before</p>{% for img in missing %}<i>{{ img }}</i>{% endfor %}<p>after</p>") ==
               "<p>before</p><p>after</p>"
    end

    test "renders its else branch" do
      assert render("{% for img in missing.gallery_objects %}<i>{{ img }}</i>{% else %}<em>none</em>{% endfor %}") ==
               "<em>none</em>"
    end

    test "with limit, offset and reversed, runs zero times" do
      assert render("{% for x in missing limit: 2 offset: 1 reversed %}{{ x }}{% else %}none{% endfor %}") == "none"
      assert render("{% for x in missing offset: continue %}{{ x }}{% else %}none{% endfor %}") == "none"
    end

    test "inside another loop, runs zero times for each item, and the outer forloop carries on" do
      template = """
      {%- assign items = "a,b,c" | split: "," -%}
      {%- for item in items -%}
      {{ forloop.index }}/{{ forloop.length }}{% for x in item.missing %}{{ forloop.index }}{% else %}-{% endfor %}{% if forloop.last %}!{% endif %}
      {%- endfor -%}
      """

      assert render(template) == "1/3-2/3-3/3-!"
    end

    test "leaves no forloop behind" do
      assert render("{% for x in missing %}{% endfor %}[{{ forloop.index }}]") == "[]"
    end
  end

  test "a tablerow over nil renders no rows" do
    assert render("<table>{% tablerow x in missing cols: 2 %}{{ x }}{% endtablerow %}</table>") == "<table></table>"
  end

  test "the collection filters give an empty list for nil" do
    assert render("[{{ missing | sort | size }}]") == "[0]"
    assert render(~s([{{ missing | sort: "title" | size }}])) == "[0]"
    assert render("[{{ missing | sort_natural | size }}]") == "[0]"
    assert render(~s([{{ missing | sort_natural: "title" | size }}])) == "[0]"
    assert render(~s([{{ missing | where: "published" | size }}])) == "[0]"
    assert render(~s([{{ missing | where: "status", "published" | size }}])) == "[0]"
    assert render(~s({% assign xs = missing | sort %}{% for x in xs %}{{ x }}{% else %}none{% endfor %})) == "none"
  end

  test "a value that is no list and not nil still raises" do
    assert_raise Protocol.UndefinedError, fn -> render("{% assign t = true %}{% for x in t %}{{ x }}{% endfor %}") end
    assert_raise Protocol.UndefinedError, fn -> render("{% assign t = false %}{{ t | sort }}") end
  end
end
