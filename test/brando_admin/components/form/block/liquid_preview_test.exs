defmodule BrandoAdmin.Components.Form.Block.LiquidPreviewTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.Block
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
      assert {:ok, _} = LiquidPreview.strip_logic(opaque <> "{% if a %}hidden{% endif %}")
    end
  end

  test "drops a comment with its body, whatever Liquid the body holds" do
    code = """
    <p>before</p>{% comment %}
      Which image drops: "auto" keeps the layout's own.
      {% if a %}{% case b %}{% when 1 %}{{ c }}{% ref refs.d %}{% picture e {} %}
      {% endcomment %}<p>after</p>
    """

    assert LiquidPreview.strip_logic(code) == {:ok, "<p>before</p><p>after</p>\n"}
    assert LiquidPreview.strip_logic("a{%- comment -%}{% endif %} ' {%- endcomment -%}b") == {:ok, "ab"}
  end

  test "drops inline comments, which may contain unmatched quotes and opening tag text" do
    code = ~S({% # don't treat {% if fake as an opener %}<p>kept</p>{%- # trimmed -%})
    assert LiquidPreview.strip_logic(code) == {:ok, "<p>kept</p>"}
  end

  test "raw keeps its body as printed text, without its tags or Liquid slots" do
    code = ~S(<p>{%- raw -%}<b>{{ title }}</b> {% ref refs.x %} {% if a %}{%- endraw -%}</p>)

    assert LiquidPreview.strip_logic(code) ==
             {:ok, "<p><b>&#123;{ title }}</b> &#123;% ref refs.x %} &#123;% if a %}</p>"}

    # No ref slot, variable or picture: the body is text the site prints.
    assert code |> Block.liquid_splits([], nil) |> Enum.all?(&is_binary/1)
  end

  test "raw leaves braces that open no Liquid alone, as style and script bodies need them" do
    code = ~S|{% raw %}<style>.a { color: red }</style><script>if (a) { b({ c: 1 }) }</script>{% endraw %}|

    assert LiquidPreview.strip_logic(code) ==
             {:ok, ~S|<style>.a { color: red }</style><script>if (a) { b({ c: 1 }) }</script>|}
  end

  test "nested comments and raw regions cannot expose comment contents to the region stack" do
    comment = """
    {% comment %}
      {% if b %}{% comment %}inner{% endcomment %}{% endif %}
      {% raw %}{% endcomment %}{% if fake %}{{ 'unfinished{% endraw %}
    {% endcomment %}
    """

    assert LiquidPreview.strip_logic("{% if a %}<div>" <> comment <> "</div>{% endif %}kept") == {:ok, "kept"}
    assert LiquidPreview.strip_logic(comment) == {:ok, "\n"}
  end

  @issue_example """
  {% comment %}
    Which image drops: "auto" keeps the layout's own.
  {% endcomment %}
  {% assign lowered = "" %}
  {% case lower %}
    {% when "first" %}{% assign lowered = "1" %}
    {% when "second" %}{% assign lowered = "2" %}
    {% else %}
      {% case layout %}
        {% when "pair" %}{% assign lowered = "2" %}
      {% endcase %}
  {% endcase %}
  <article b-tpl="media-row" data-lowered="{{ lowered }}">
    <div class="inner">{{ content }}</div>
  </article>
  """

  test "shows none of the logic in the issue's module template" do
    assert LiquidPreview.strip_logic(@issue_example) ==
             {:ok,
              """



              <article b-tpl="media-row" data-lowered="{{ lowered }}">
                <div class="inner">{{ content }}</div>
              </article>
              """}

    splits = Block.liquid_splits(@issue_example, [], nil)
    assert {:content, "content"} in splits
    refute splits |> Enum.filter(&is_binary/1) |> Enum.join() |> String.contains?(["{%", "comment", "when"])
  end

  @hidden_regions [
    {"case", "case layout", "endcase"},
    {"capture", "capture label", "endcapture"},
    {"tablerow", "tablerow row in rows cols: 2", "endtablerow"}
  ]

  for {name, opening, closing} <- @hidden_regions do
    test "strips #{name} regions with their branches, as it does if" do
      open = "{%- #{unquote(opening)} -%}"
      close = "{% #{unquote(closing)} %}"

      code =
        "<article>{% ref refs.text %}" <>
          open <>
          "{% when 'a' %}<div>" <>
          open <>
          "<span>{{ hidden }}</span>" <>
          close <>
          "</div>{% else %}b" <>
          close <> "</article>"

      assert LiquidPreview.strip_logic(code) == {:ok, "<article>{% ref refs.text %}</article>"}
    end

    test "names a ref inside #{name} as one the editor cannot show" do
      code = "{% ref refs.visible %}{% #{unquote(opening)} %}{% ref refs.hidden %}{% #{unquote(closing)} %}"
      assert LiquidPreview.stripped_refs(code) == ["hidden"]
    end
  end

  test "balances case and if regions nested in each other" do
    code = """
    a{% case x %}{% when 1 %}{% if y %}{% case z %}{% when 2 %}{% endcase %}{% else %}{% unless w %}u{% endunless %}{% endif %}{% else %}{% for i in is %}{% case i %}{% endcase %}{% endfor %}{% endcase %}b
    {% if y %}{% case x %}{% when 1 %}{% if z %}z{% endif %}{% endcase %}{% endif %}c
    """

    assert LiquidPreview.strip_logic(code) == {:ok, "ab\nc\n"}
  end

  test "drops tags the preview has no part for, keeping the markup around and between them" do
    code = """
    <ul class="{% cycle 'odd', 'even' %}">{%- increment n -%}{% decrement m %}{% echo title %}
    {% liquid
      assign x = 1
      echo x
    %}{% editable entry.cover %}<li>{% t en: "Hi", no: "Hei" %}</li>{% endeditable %}
    <a href="{% route_i18n 'en' 'page' { entry.uri } %}">{% render_palette %}</a>{% when 'stray' %}{% else %}{% elsif q %}
    {% endcomment %}{% endraw %}{% %}</ul>
    """

    assert LiquidPreview.strip_logic(code) ==
             {:ok,
              """
              <ul class="">
              <li></li>
              <a href=""></a>
              </ul>
              """}
  end

  test "keeps every tag the preview renders" do
    code =
      ~S(<div>{% ref refs.a %}{% headless_ref refs.b %}{% picture entry.cover { size: 'auto' } %}{{ title }}) <>
        ~S({% datasource %}x{% enddatasource %}{%- ref refs.c -%}</div>)

    assert LiquidPreview.strip_logic(code) == {:ok, code}
  end

  test "new regions return the same errors for unclosed and mismatched tags" do
    assert LiquidPreview.strip_logic("{% case a %}{% when 1 %}x") == {:error, {:unclosed_tag, "case"}}
    assert LiquidPreview.strip_logic("{% capture a %}x") == {:error, {:unclosed_tag, "capture"}}
    assert LiquidPreview.strip_logic("x{% endcase %}") == {:error, {:unexpected_end, "endcase"}}
    assert LiquidPreview.strip_logic("{% endcapture %}") == {:error, {:unexpected_end, "endcapture"}}

    assert LiquidPreview.strip_logic("{% case a %}{% if b %}{% endcase %}{% endif %}") ==
             {:error, {:mismatched_end, "endif", "endcase"}}

    assert LiquidPreview.strip_logic("{% if b %}{% case a %}{% endif %}") ==
             {:error, {:mismatched_end, "endcase", "endif"}}

    assert LiquidPreview.strip_logic("{% case a %}{% comment %}{% endcase %}") == {:error, {:unclosed_tag, "comment"}}
    assert LiquidPreview.strip_logic("{% case a") == {:error, :unterminated_tag}
    assert LiquidPreview.strip_logic("{% cycle 'a, 'b' %}") == {:error, :unterminated_tag}
  end

  test "never raises on any arrangement of tags, however malformed" do
    fragments = [
      "<p>",
      "{{ x }}",
      "{{ x",
      "{% if a %}",
      "{% endif %}",
      "{% case a %}",
      "{% when 1 %}",
      "{% else %}",
      "{% endcase %}",
      "{% capture c %}",
      "{% endcapture %}",
      "{% comment %}",
      "{% endcomment %}",
      "{% raw %}",
      "{% endraw %}",
      "{% # note %}",
      "{% cycle 'a' %}",
      "{% ref refs.r %}",
      "{% '",
      "{%",
      "%}",
      "}}"
    ]

    for a <- fragments, b <- fragments, c <- fragments do
      code = a <> b <> c
      assert {status, _} = LiquidPreview.strip_logic(code)
      assert status in [:ok, :error], code
      assert is_list(LiquidPreview.stripped_refs(code))
      assert is_list(Block.liquid_splits(code, [], nil))
    end
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

  describe "stripped_refs/1" do
    test "names a ref that only appears inside a stripped region" do
      for {_, opening, closing} <- @regions do
        code = "{% ref refs.visible %}{% #{opening} %}<div>{% ref refs.hidden %}</div>{% #{closing} %}"
        assert LiquidPreview.stripped_refs(code) == ["hidden"]
      end
    end

    test "reports each hidden ref once, in source order, however deeply nested" do
      code = """
      {% if a %}{% ref refs.one %}{% for x in xs %}{% ref refs.two %}{% ref refs.one %}{% endfor %}{% endif %}
      {% hide %}{% ref refs.three %}{% endhide %}
      """

      assert LiquidPreview.stripped_refs(code) == ["one", "two", "three"]
    end

    test "does not report a ref that is also rendered at the top level" do
      code = "{% ref refs.text %}{% if a %}{% ref refs.text %}{% endif %}"
      assert LiquidPreview.stripped_refs(code) == []
    end

    test "does not report headless_ref declarations or plain reads inside a region" do
      # The supported pattern: declare the slot at the top level, read it inside.
      code = """
      {% headless_ref refs.text %}
      {% if refs.text.active %}<div>{{ refs.text.data.data.text }}</div>{% else %}<div>No text</div>{% endif %}
      """

      assert LiquidPreview.stripped_refs(code) == []
    end

    test "does not report a ref rendered inside a region when headless_ref declares its slot" do
      # One slot, shown one of two ways: the declaration gives the editor its
      # input, the region decides how the site renders it.
      code = """
      {% headless_ref refs.media %}
      {% if refs.media.data.type == "file" %}<canvas></canvas>{% else %}{% ref refs.media %}{% endif %}
      """

      assert LiquidPreview.stripped_refs(code) == []
    end

    test "recognizes trim markers and loose whitespace in the ref tag" do
      assert LiquidPreview.stripped_refs("{% if a %}{%-  ref   refs.spaced -%}{% endif %}") == ["spaced"]
    end

    test "ignores ref tags inside raw, comment and quoted strings" do
      code = """
      {% if a %}{% raw %}{% ref refs.rawref %}{% endraw %}{% endif %}
      {% comment %}{% ref refs.commented %}{% endcomment %}
      {{ '{% ref refs.quoted %}' }}
      """

      # A `{% ref %}` inside raw/comment is never a slot at all, and one in a
      # quoted string is text. None are "hidden by a conditional": inside a
      # region the raw body is dropped with it, so `rawref` is reported as
      # unreachable — it is.
      assert LiquidPreview.stripped_refs(code) == ["rawref"]
    end

    test "reports nothing for malformed code or no code" do
      assert LiquidPreview.stripped_refs("{% if a %}{% ref refs.text %}") == []
      assert LiquidPreview.stripped_refs("") == []
      assert LiquidPreview.stripped_refs(nil) == []
    end
  end
end
