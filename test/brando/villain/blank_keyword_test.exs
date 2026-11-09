defmodule Brando.Villain.BlankKeywordTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.TemplateParser
  alias Brando.Villain

  # `:missing` leaves `x` out of the context.
  @blank [nil, "", false, [], %{}, :missing]
  @present ["/a", " ", 0, true, ["a"], %{"a" => 1}]

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
    end

    test "works on a nested field" do
      context = Liquex.Context.new(%{"entry" => %{"title" => ""}})

      assert Villain.parse_and_render("{% if entry.title == blank %}untitled{% endif %}", context) == "untitled"
    end
  end

  describe "in an and/or chain" do
    test "keeps its place when the expansion sits before an or" do
      # Liquid chains right to left: an inline `x != nil and x != empty or y`
      # would read as `x != nil and (x != empty or y)`, false for a nil x.
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

  test "when blank matches each blank value" do
    template = "{% case x %}{% when blank %}blank{% when 1 %}one{% else %}other{% endcase %}"

    for x <- @blank, do: assert(render(template, x) == "blank", "#{inspect(x)} should be blank")
    assert render(template, 1) == "one"
    assert render(template, "/a") == "other"
  end

  test "leaves empty with Liquid's meaning" do
    template = "{% if x == empty %}empty{% else %}not empty{% endif %}"

    assert render(template, "") == "empty"
    assert render(template, nil) == "not empty"
  end

  test "does not change text or output that spells blank" do
    context = Liquex.Context.new(%{"blank" => "value", "target" => "_blank"})

    assert Villain.parse_and_render(~S|<a target="{{ target }}">blank</a>|, context) ==
             ~S|<a target="_blank">blank</a>|
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
    render = fn vars -> document |> Liquex.render!(Liquex.Context.new(vars)) |> elem(0) |> IO.iodata_to_binary() end

    assert render.(%{"slug" => ""}) == ""
    assert render.(%{"slug" => "about"}) == "/about"
  end
end
