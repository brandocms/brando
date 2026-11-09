defmodule Brando.Villain.EmptyKeywordsTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.TemplateParser
  alias Brando.Villain
  alias Brando.Villain.EmptyKeywords

  # `:missing` leaves `x` out of the context.
  @empty [nil, "", [], %{}, :missing]
  @blank [false | @empty]
  @present ["/a", " ", 0, true, ["a"], %{"a" => 1}, Decimal.new("0"), Decimal.new("24.49")]

  # Compiling this module is the test that a Blueprint template using
  # `blank` or `empty` builds: the parsed document goes through `Macro.escape/1`.
  defmodule BlankURL do
    import Brando.Blueprint.AbsoluteURL

    absolute_url "{% if slug != blank %}/{{ slug }}{% endif %}{% case kind %}{% when empty %}/none{% endcase %}"
  end

  defmodule BlankIdentifier do
    import Brando.Blueprint.Identifier.DSL

    @data_layer :database
    identifier "{% if entry.title != blank %}{{ entry.title }}{% else %}Untitled{% endif %}"
  end

  defp render(template, x, extra \\ %{}) do
    vars = if x == :missing, do: extra, else: Map.put(extra, "x", x)
    Villain.parse_and_render(template, Liquex.Context.new(vars))
  end

  describe "x != blank" do
    test "is false for blank values and true for the rest" do
      template = "{% if x != blank %}shown{% endif %}"

      for x <- @blank, do: assert(render(template, x) == "", "#{inspect(x)} should be blank")
      for x <- @present, do: assert(render(template, x) == "shown", "#{inspect(x)} should not be blank")
    end

    test "hides the markup a module guards around an empty var" do
      template = ~S|{% if url != blank %}<a href="{{ url }}">{{ label }} →</a>{% endif %}|
      context = Liquex.Context.new(%{"url" => nil, "label" => "Read more"})

      assert Villain.parse_and_render(template, context) == ""
    end

    test "works with blank on the left" do
      template = "{% if blank != x %}shown{% endif %}"

      assert render(template, nil) == ""
      assert render(template, "/a") == "shown"
    end
  end

  describe "x == blank" do
    test "is true for blank values and false for the rest" do
      template = "{% if x == blank %}blank{% else %}present{% endif %}"

      for x <- @blank, do: assert(render(template, x) == "blank", "#{inspect(x)} should be blank")
      for x <- @present, do: assert(render(template, x) == "present", "#{inspect(x)} should not be blank")
    end

    test "works in elsif and unless" do
      assert render("{% if false %}a{% elsif x == blank %}b{% endif %}", "") == "b"
      assert render("{% unless x == blank %}shown{% endunless %}", nil) == ""
      assert render("{% unless x == blank %}shown{% endunless %}", "/a") == "shown"

      template = "{% unless y %}a{% elsif x != blank %}b{% else %}c{% endunless %}"
      assert render(template, "/a", %{"y" => true}) == "b"
      assert render(template, "", %{"y" => true}) == "c"
      assert render(template, "", %{"y" => false}) == "a"
    end

    test "works in a liquid tag" do
      template = """
      {% liquid
        if x != blank
          echo "shown"
        endif
      %}
      """

      assert render(template, "/a") =~ "shown"
      refute render(template, "") =~ "shown"
    end

    test "works on a nested field" do
      context = Liquex.Context.new(%{"entry" => %{"title" => ""}})

      assert Villain.parse_and_render("{% if entry.title == blank %}untitled{% endif %}", context) == "untitled"
    end
  end

  describe "in an and/or chain" do
    test "keeps its place when the expansion sits before an or" do
      # Liquid chains right to left, so the blank test must stay one term:
      # `x != nil and x != empty or y` would read as
      # `x != nil and (x != empty or y)`, false for a nil x.
      template = "{% if x != blank or y %}shown{% endif %}"

      assert render(template, nil, %{"y" => true}) == "shown"
      assert render(template, nil, %{"y" => false}) == ""
      assert render(template, "/a", %{"y" => false}) == "shown"
    end

    test "keeps its place when the expansion sits before an and" do
      template = "{% if x == blank and y %}shown{% endif %}"

      assert render(template, "", %{"y" => true}) == "shown"
      assert render(template, "", %{"y" => false}) == ""
      assert render(template, "/a", %{"y" => true}) == ""
    end

    test "keeps its place after another condition" do
      template = "{% if y and x != blank %}shown{% endif %}"

      assert render(template, "/a", %{"y" => true}) == "shown"
      assert render(template, "", %{"y" => true}) == ""
      assert render(template, "/a", %{"y" => false}) == ""
    end
  end

  test "a Decimal compares without raising" do
    # Liquex raises comparing a Decimal with nil or false.
    price = Decimal.new("24.49")

    assert render("{% if x != blank %}{{ x }}{% endif %}", price) == "24.49"
    assert render("{% if x == blank %}blank{% else %}present{% endif %}", price) == "present"
    assert render("{% if x > 10 and x != blank %}dear{% endif %}", price) == "dear"
    assert render("{% if x != empty %}{{ x }}{% endif %}", price) == "24.49"
    assert render("{% if x == empty %}empty{% else %}present{% endif %}", price) == "present"
  end

  test "other conditions in the same tag still evaluate with Liquex" do
    template = ~S|{% if x != blank and y contains "b" or z == 1.5 %}shown{% endif %}|

    assert render(template, "/a", %{"y" => "abc"}) == "shown"
    assert render(template, "/a", %{"y" => "xyz"}) == ""
    # Right to left: `x != blank and (y contains "b" or z == 1.5)`.
    assert render(template, "/a", %{"y" => "xyz", "z" => 1.5}) == "shown"
    assert render(template, "", %{"y" => "xyz", "z" => 1.5}) == ""
  end

  test "when blank matches each blank value" do
    template = "{% case x %}{% when blank %}blank{% when 1 %}one{% else %}other{% endcase %}"

    for x <- @blank, do: assert(render(template, x) == "blank", "#{inspect(x)} should be blank")
    assert render(template, 1) == "one"
    assert render(template, "/a") == "other"
  end

  describe "empty" do
    test "x != empty is false for empty values, nil among them, and true for the rest" do
      template = "{% if x != empty %}shown{% endif %}"

      for x <- @empty, do: assert(render(template, x) == "", "#{inspect(x)} should be empty")
      for x <- [false | @present], do: assert(render(template, x) == "shown", "#{inspect(x)} should not be empty")
    end

    test "x == empty is true for empty values and false for the rest" do
      template = "{% if x == empty %}empty{% else %}present{% endif %}"

      for x <- @empty, do: assert(render(template, x) == "empty", "#{inspect(x)} should be empty")
      for x <- [false | @present], do: assert(render(template, x) == "present", "#{inspect(x)} should not be empty")
    end

    test "hides a datasource's markup when it has no entries" do
      template = "{% if entries != empty %}<ul>{% for e in entries %}<li>{{ e }}</li>{% endfor %}</ul>{% endif %}"

      assert Villain.parse_and_render(template, Liquex.Context.new(%{"entries" => nil})) == ""
      assert Villain.parse_and_render(template, Liquex.Context.new(%{"entries" => []})) == ""
      assert Villain.parse_and_render(template, Liquex.Context.new(%{"entries" => ["a"]})) == "<ul><li>a</li></ul>"
    end

    test "works in unless, with empty on the left and beside blank" do
      assert render("{% unless x == empty %}shown{% endunless %}", nil) == ""
      assert render("{% if empty != x %}shown{% endif %}", "/a") == "shown"

      template = "{% if x != empty and y != blank %}shown{% endif %}"
      assert render(template, "/a", %{"y" => "b"}) == "shown"
      assert render(template, "/a", %{"y" => false}) == ""
      assert render(template, nil, %{"y" => "b"}) == ""
    end

    test "when empty matches each empty value and not false" do
      template = "{% case x %}{% when empty %}empty{% else %}other{% endcase %}"

      for x <- @empty, do: assert(render(template, x) == "empty", "#{inspect(x)} should be empty")
      assert render(template, false) == "other"
      assert render(template, "/a") == "other"
    end
  end

  test "does not change text or output that spells blank" do
    context = Liquex.Context.new(%{"blank" => "value", "target" => "_blank"})

    assert Villain.parse_and_render(~S|<a target="{{ target }}">blank</a>|, context) ==
             ~S|<a target="_blank">blank</a>|
  end

  test "a template that only spells _blank renders its conditions as before" do
    # The text "blank" sends every if and unless through EmptyKeywords' tags.
    template = ~S"""
    {%- for i in (1..6) -%}
    {%- if i == 2 %}{% continue %}{% elsif i == 5 %}{% break %}{% endif -%}
    {%- unless i == 3 or y contains "b" and z %}[{{ i }}]{% else %}<{{ i }}>{% endunless -%}
    {%- if y == "abc" and z or i > 3 %}!{% endif -%}
    {%- endfor -%}
    """

    for vars <- [%{"y" => "abc", "z" => true}, %{"y" => "xyz", "z" => false}, %{}] do
      plain = Villain.parse_and_render(template, Liquex.Context.new(vars))
      with_blank = Villain.parse_and_render(~S|<a target="_blank">| <> template, Liquex.Context.new(vars))

      assert ~S|<a target="_blank">| <> plain == with_blank
    end
  end

  test "break and continue work under a blank test" do
    template =
      "{% for i in items %}{% if i == blank %}{% continue %}{% endif %}{% if i == 'stop' %}{% break %}{% endif %}{{ i }}{% endfor %}"

    context = Liquex.Context.new(%{"items" => ["a", "", nil, "b", "stop", "c"]})

    assert Villain.parse_and_render(template, context) == "ab"
  end

  test "leaves a comparison outside if and unless as Liquex parsed it" do
    blank = [left: [field: [key: "x"]], op: :!=, right: [literal: %Liquex.Special{type: :blank}]]
    empty = [left: [field: [key: "x"]], op: :==, right: [literal: %Liquex.Special{type: :empty}]]
    document = [{{:tag, MyApp.ConditionTag}, [expression: [blank, :or, empty], contents: []]}]

    assert EmptyKeywords.rewrite(document) == document
  end

  test "the cached module render rewrites too" do
    template = "{% if x != blank %}cached-#{System.unique_integer([:positive])}{% endif %}"
    context = Liquex.Context.new(%{"x" => ""})

    assert Villain.parse_and_render_cached(template, context) == ""
    # The second render reads the cached document.
    assert Villain.parse_and_render_cached(template, context) == ""
  end

  test "Blueprint templates rewrite too" do
    {:ok, document} = TemplateParser.parse("{% if slug != blank %}/{{ slug }}{% endif %}")

    assert render_document(document, %{"slug" => ""}) == ""
    assert render_document(document, %{"slug" => "about"}) == "/about"

    assert BlankIdentifier.__has_identifier__()

    document = BlankURL.__absolute_url_parsed__()
    assert render_document(document, %{"slug" => "about", "kind" => "page"}) == "/about"
    assert render_document(document, %{"slug" => nil, "kind" => nil}) == "/none"
  end

  defp render_document(document, vars),
    do: document |> Liquex.render!(Liquex.Context.new(vars)) |> elem(0) |> IO.iodata_to_binary()
end
