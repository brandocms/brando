defmodule Brando.HTML.TreeTest do
  use ExUnit.Case, async: true
  alias Brando.HTML.Tree

  describe "parse_fragment/1" do
    test "keeps the whitespace between elements" do
      assert Tree.parse_fragment("<b>a</b> <i>b</i>") == [{"b", [], ["a"]}, " ", {"i", [], ["b"]}]
    end

    test "keeps table rows and cells without their table" do
      assert Tree.parse_fragment("<tr><td>x</td></tr>") == [{"tr", [], [{"td", [], ["x"]}]}]
      assert Tree.parse_fragment("<td>x</td>") == [{"td", [], ["x"]}]
    end

    test "a stray end tag for a template loses nothing" do
      assert Tree.parse_fragment("<p>a</p></template><p>b</p>") == [{"p", [], ["a"]}, {"p", [], ["b"]}]
    end

    test "keeps templates in the fragment" do
      assert Tree.parse_fragment(~s(<template data-x="1"><p>a</p></template>)) ==
               [{"template", [{"data-x", "1"}], [{"p", [], ["a"]}]}]
    end

    # Browsers read a noscript's content as text, ending at the first
    # `</noscript>`. lexbor parses with scripting off, where it is markup
    # and an unclosed element inside swallowed the rest of the field.
    test "a noscript ends at its end tag, its content parsed on its own" do
      html = ~s(<noscript class="n"><p>Enable JavaScript</noscript><h2>Title</h2><p>Body</p>)

      assert Tree.parse_fragment(html) == [
               {"noscript", [{"class", "n"}], [{"p", [], ["Enable JavaScript"]}]},
               {"h2", [], ["Title"]},
               {"p", [], ["Body"]}
             ]

      assert Tree.parse_fragment(html) == Floki.parse_fragment!(html)

      assert html |> Tree.parse_fragment() |> Tree.to_html() ==
               ~s(<noscript class="n"><p>Enable JavaScript</p></noscript><h2>Title</h2><p>Body</p>)
    end

    test "noscript in a script, textarea or comment is left to them" do
      html = ~s(<script>"<noscript><p>"</script><textarea><noscript>a</noscript></textarea><!-- <noscript> --><p>a</p>)

      assert Tree.parse_fragment(html) == [
               {"script", [], [~s("<noscript><p>")]},
               {"textarea", [], ["<noscript>a</noscript>"]},
               {:comment, " <noscript> "},
               {"p", [], ["a"]}
             ]
    end

    test "takes iodata" do
      assert Tree.parse_fragment(["<p>", "a", "</p>"]) == [{"p", [], ["a"]}]
    end
  end

  describe "parse_document/1" do
    test "a noscript in head keeps the head tags after it in head" do
      html =
        ~s(<html><head><noscript><img src="px"></noscript><title>T</title><link rel="canonical" href="/c"></head><body>b</body></html>)

      assert [{"html", [], [{"head", [], head}, {"body", [], ["b"]}]}] = Tree.parse_document(html)

      assert head == [
               {"noscript", [], [{"img", [{"src", "px"}], []}]},
               {"title", [], ["T"]},
               {"link", [{"rel", "canonical"}, {"href", "/c"}], []}
             ]
    end
  end

  describe "to_html/1" do
    test "writes what parses back to the same tree" do
      for html <- [
            ~s(<p>a &amp; b <b>c</b> <i>d</i></p>\n<p>e</p>),
            ~s(<pre>\n\nindented</pre>),
            ~s(<textarea>\nx</textarea>),
            ~s(<svg viewBox="0 0 1 1"><path d="M0"></path></svg>)
          ] do
        tree = Tree.parse_fragment(html)
        assert tree |> Tree.to_html() |> Tree.parse_fragment() == tree
      end
    end

    test "a pre's leading line break is written twice, so it is not lost" do
      assert "<pre>\n\nx</pre>" |> Tree.parse_fragment() |> Tree.to_html() == "<pre>\n\nx</pre>"
      assert "<pre>\nx</pre>" |> Tree.parse_fragment() |> Tree.to_html() == "<pre>x</pre>"
    end
  end

  describe "text/2" do
    @html ~s(<p>a <b>b</b><br>c</p><script>s</script><style>t</style><!-- d -->)

    test "a br is a line break; scripts and comments give nothing" do
      assert @html |> Tree.parse_fragment() |> Tree.text() == "a b\nct"
    end

    test "options" do
      tree = Tree.parse_fragment(@html)
      assert Tree.text(tree, style: false) == "a b\nc"
      assert Tree.text(tree, js: true, style: false) == "a b\ncs"
      assert Tree.text(tree, sep: "|", style: false) == "a |b\n|c"
    end
  end

  test "find/2 and attr/2" do
    tree = Tree.parse_fragment(~s(<div data-a="1"><p data-a="2">x</p></div><p>y</p>))
    found = Tree.find(tree, &Tree.attr(&1, "data-a"))
    assert Enum.map(found, &Tree.attr(&1, "data-a")) == ["1", "2"]
    assert Tree.find(hd(tree), &match?({"p", _, _}, &1)) == [{"p", [{"data-a", "2"}], ["x"]}]
    assert Tree.attr({"p", [], []}, "data-a") == nil
  end
end
