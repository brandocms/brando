defmodule BrandoAdmin.Components.Form.Block.LiquidPreviewTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.Block.LiquidPreview

  @regions [
    {"if", "if visible", "endif"},
    {"unless", "unless hidden", "endunless"},
    {"for", "for item in items", "endfor"},
    {"hide", "hide", "endhide"}
  ]

  for {name, opening, closing} <- @regions do
    test "strips nested #{name} regions through the outer closing tag" do
      open = "{% #{unquote(opening)} %}"
      close = "{% #{unquote(closing)} %}"

      code =
        "<article>{% ref refs.text %}" <>
          open <> "<div>" <> open <> "<span>hidden</span>" <> close <> "</div>" <> close <> "</article>"

      assert LiquidPreview.strip_logic(code) == {:ok, "<article>{% ref refs.text %}</article>"}
    end

    test "recognizes whitespace and trim markers for #{name}" do
      open = "{%-\n\t#{unquote(opening)}\t-%}"
      close = "{%\t#{unquote(closing)}\n%}"

      assert LiquidPreview.strip_logic("before " <> open <> open <> "hidden" <> close <> close <> " after") ==
               {:ok, "before  after"}
    end
  end

  test "strips every pairing of region types without removing adjacent content" do
    for {_, outer, outer_end} <- @regions, {_, inner, inner_end} <- @regions do
      code = "a{% #{outer} %}<div>{% #{inner} %}<p>hidden</p>{% #{inner_end} %}</div>{% #{outer_end} %}b"
      assert LiquidPreview.strip_logic(code) == {:ok, "ab"}
    end
  end

  test "handles deeper nesting and preserves content between sequential regions" do
    code = """
    <section>
    {% if a %}<div>{% if b %}<div>{% if c %}<div>hidden</div>{% endif %}</div>{% endif %}</div>{% endif %}
    {% headless_ref refs.title %}
    {% if d %}<p>hidden</p>{% endif %}
    <p>Visible</p>
    </section>
    """

    assert LiquidPreview.strip_logic(code) ==
             {:ok, "<section>\n\n{% headless_ref refs.title %}\n\n<p>Visible</p>\n</section>\n"}
  end

  test "strips all branches of nested conditionals and loop fallbacks" do
    code = """
    {% if a %}a{% elsif b %}{% unless c %}c{% else %}d{% endunless %}{% else %}e{% endif %}
    {% for item in items %}{% if item.active %}item{% endif %}{% else %}empty{% endfor %}
    """

    assert LiquidPreview.strip_logic(code) == {:ok, "\n\n"}
  end

  test "recognizes loop arguments without parsing their expressions" do
    for expression <- ["rows limit: 2", "rows offset: 1 reversed", "(1..3)", "data['rows']"] do
      code =
        "<main>{% for row in #{expression} %}<div>{% for col in row.cols limit: 2 %}col{% endfor %}</div>{% endfor %}</main>"

      assert LiquidPreview.strip_logic(code) == {:ok, "<main></main>"}
    end
  end

  test "strips conditional attributes while preserving the surrounding element" do
    code = ~s(<div class="card"{% if a %} data-a{% if b %} data-b{% endif %}{% endif %}>body</div>)
    assert LiquidPreview.strip_logic(code) == {:ok, ~s(<div class="card">body</div>)}
  end

  test "preserves top-level refs, content, pictures, variables and Unicode source" do
    code = """
    <article class="blå">Æøå — 日本語
    {% ref refs.text %}{% headless_ref refs.image %}
    {{ entry.title }}{{ content | renderless }}
    {% picture image { sizes: 'auto' } %}
    {% datasource %}source{% enddatasource %}
    </article>
    """

    assert LiquidPreview.strip_logic(code) == {:ok, code}
    assert LiquidPreview.strip_logic("") == {:ok, ""}
  end

  test "refs inside stripped regions remain stripped" do
    assert LiquidPreview.strip_logic("{% if a %}{% ref refs.hidden %}{% endif %}{% ref refs.visible %}") ==
             {:ok, "{% ref refs.visible %}"}
  end

  test "quoted tag names and delimiters cannot close a region" do
    code =
      ~S(<article>{% if a %}<div>{% assign label = "%} {% endif %}" %}{{ '}} {% endif %}' }}</div>{% endif %}</article>)

    assert LiquidPreview.strip_logic(code) == {:ok, "<article></article>"}
  end

  test "quoted opening tags cannot start a region" do
    code = ~S({% assign label = "{% if a %}" %}{{ '{% if a %}' }}{% ref refs.text %})
    assert LiquidPreview.strip_logic(code) == {:ok, ~S({{ '{% if a %}' }}{% ref refs.text %})}
  end

  test "backslashes retain Liquex's literal string semantics" do
    assert LiquidPreview.strip_logic(~S({% assign path = 'folder\' %}kept)) == {:ok, "kept"}
  end

  test "assigns are removed as complete tokens including trim markers" do
    code = ~S(before{%- assign label = '%} literal' -%}after)
    assert LiquidPreview.strip_logic(code) == {:ok, "beforeafter"}
  end

  for name <- ["raw", "comment"] do
    test "ignores tag-like content and unmatched quotes in #{name} bodies" do
      opaque = "{%- #{unquote(name)} -%}{% endif %}{% if fake %}an unmatched ' quote{% end#{unquote(name)} %}"

      assert LiquidPreview.strip_logic("{% if a %}<div>" <> opaque <> "</div>{% endif %}kept") == {:ok, "kept"}
      assert LiquidPreview.strip_logic(opaque <> "{% if a %}hidden{% endif %}") == {:ok, opaque}
    end
  end

  test "inline comments may contain unmatched quotes and opening tag text" do
    code = ~S({% # don't treat {% if fake as an opener %}<p>kept</p>)
    assert LiquidPreview.strip_logic(code) == {:ok, code}
  end

  test "nested comments and raw regions cannot expose comment contents to the region stack" do
    comment = """
    {% comment %}
      {% if b %}{% comment %}inner{% endcomment %}{% endif %}
      {% raw %}{% endcomment %}{% if fake %}{{ 'unfinished{% endraw %}
    {% endcomment %}
    """

    assert LiquidPreview.strip_logic("{% if a %}<div>" <> comment <> "</div>{% endif %}kept") == {:ok, "kept"}
    assert LiquidPreview.strip_logic(comment) == {:ok, comment}
  end

  test "retains the existing image and attribute cleanup" do
    code =
      ~S(<div data-moonwalk-run="once" data-moonwalk-section id="{{ entry.id }}"><a href="{{ url }}">link</a><img src="{{ image }}"><img src="/static.png"></div>)

    assert LiquidPreview.strip_logic(code) ==
             {:ok, ~S(<div   ><a >link</a><img src="/static.png"></div>)}
  end

  test "unclosed regions return an error instead of partial markup" do
    for {name, opening, _} <- @regions do
      assert LiquidPreview.strip_logic("<article>{% #{opening} %}<div>incomplete</article>") ==
               {:error, {:unclosed_tag, name}}
    end
  end

  test "unexpected and mismatched closing tags return an error" do
    assert LiquidPreview.strip_logic("<article>{% endif %}</article>") == {:error, {:unexpected_end, "endif"}}

    assert LiquidPreview.strip_logic("{% if a %}{% for row in rows %}{% endif %}{% endfor %}") ==
             {:error, {:mismatched_end, "endfor", "endif"}}
  end

  test "unterminated tokens and opaque regions return errors" do
    assert LiquidPreview.strip_logic("<div>{% if a") == {:error, :unterminated_tag}
    assert LiquidPreview.strip_logic(~S({% assign a = 'unfinished %})) == {:error, :unterminated_tag}
    assert LiquidPreview.strip_logic("{{ value") == {:error, :unterminated_output}
    assert LiquidPreview.strip_logic("{% # unfinished") == {:error, :unterminated_tag}
    assert LiquidPreview.strip_logic("{% raw %}unfinished") == {:error, {:unclosed_tag, "raw"}}
    assert LiquidPreview.strip_logic("{% comment %}unfinished") == {:error, {:unclosed_tag, "comment"}}
  end
end
