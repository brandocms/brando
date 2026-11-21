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

    test "a noscript in an attribute value is the value's text" do
      for html <- [
            ~s(<p data-tip="Wrap fallbacks in <noscript> tags">Tip</p><h2>Keep</h2><noscript><img src=p></noscript><p>after</p>),
            ~s(<img alt="<noscript>x</noscript>"><p>a</p>),
            ~s(<p title='<noscript>'>a</p><noscript>b</noscript>)
          ] do
        assert Tree.parse_fragment(html) == Floki.parse_fragment!(html)
      end

      assert [{"p", _, ["Tip"]}, {"h2", [], ["Keep"]}, {"noscript", [], [{"img", _, []}]}, {"p", [], ["after"]}] =
               Tree.parse_fragment(
                 ~s(<p data-tip="Wrap fallbacks in <noscript> tags">Tip</p><h2>Keep</h2><noscript><img src=p></noscript><p>after</p>)
               )
    end

    test "a quote opens an attribute value only after `=`" do
      html = ~s(<noscript title=it's><p>x</noscript><p>Don't stop</p><noscript>y</noscript>)

      assert Tree.parse_fragment(html) == [
               {"noscript", [{"title", "it's"}], [{"p", [], ["x"]}]},
               {"p", [], ["Don't stop"]},
               {"noscript", [], ["y"]}
             ]

      assert Tree.parse_fragment(html) == Floki.parse_fragment!(html)
    end

    test "noscript tags in any case, with junk in the end tag" do
      for html <- [~s(<NOSCRIPT CLASS=x><p>a</NoScript ><p>b</p>), ~s(<noscript>a</noscript foo><p>b</p>)] do
        assert Tree.parse_fragment(html) == Floki.parse_fragment!(html)
      end

      assert Tree.parse_fragment(~s(<NOSCRIPT CLASS=x><p>a</NoScript ><p>b</p>)) ==
               [{"noscript", [{"class", "x"}], [{"p", [], ["a"]}]}, {"p", [], ["b"]}]
    end

    test "an unclosed noscript runs to the end" do
      html = ~s(<noscript>open<p>x)
      assert Tree.parse_fragment(html) == [{"noscript", [], ["open", {"p", [], ["x"]}]}]
      assert Tree.parse_fragment(html) == Floki.parse_fragment!(html)
    end

    # Floki ends the outer noscript at the second end tag; a browser ends
    # it at the first, and the rest is text after it.
    test "a nested noscript ends the outer one at its end tag" do
      assert Tree.parse_fragment(~s(<noscript><noscript>a</noscript>b</noscript><p>c</p>)) ==
               [{"noscript", [], [{"noscript", [], ["a"]}]}, "b", {"p", [], ["c"]}]
    end

    # An unclosed textarea, comment or script, and plaintext, run to the end
    # of the input; Floki ends them with a `</floki>` of its own.
    test "unclosed text elements and comments keep a noscript in them as text" do
      assert Tree.parse_fragment(~s(<textarea><noscript>x</noscript>)) ==
               [{"textarea", [], ["<noscript>x</noscript>"]}]

      assert Tree.parse_fragment(~s(<!-- <noscript>x</noscript>)) == [comment: " <noscript>x</noscript>"]
      assert Tree.parse_fragment(~s(<script><noscript>x</noscript>)) == [{"script", [], ["<noscript>x</noscript>"]}]

      assert Tree.parse_fragment(~s(<plaintext><noscript>x</noscript>)) ==
               [{"plaintext", [], ["<noscript>x</noscript>"]}]
    end

    test "a bogus or abrupt comment ends at its own end" do
      assert Tree.parse_fragment(~s(<!x<noscript>y</noscript>z)) == [{:comment, "x<noscript"}, "yz"]
      assert Tree.parse_fragment(~s(<?pi <noscript>?>a)) == [{:comment, "?pi <noscript"}, "?>a"]

      for html <- [~s(<!--><noscript>a</noscript>), ~s(<!---><noscript>a</noscript>)] do
        assert Tree.parse_fragment(html) == [{:comment, ""}, {"noscript", [], ["a"]}]
      end
    end

    # A script in its escaped state (`<!--<script>`) is not ended by `</script>`.
    test "a double escaped script keeps a noscript in it as text" do
      assert Tree.parse_fragment(~s(<script><!--<script></script><noscript>a</noscript>--></script><p>c</p>)) ==
               [{"script", [], ["<!--<script></script><noscript>a</noscript>-->"]}, {"p", [], ["c"]}]
    end

    test "a marker that would land in text is given up, and the input parsed as lexbor reads it" do
      for html <- [
            ~s(<svg><foreignObject><script>"</svg><noscript>x</noscript>"</script></foreignObject></svg>),
            ~s(<svg><foreignObject><textarea></svg><noscript>x</noscript></textarea></foreignObject></svg>)
          ] do
        nodes = Tree.parse_fragment(html)
        refute Tree.to_html(nodes) =~ "data-brando-noscript"

        assert nodes ==
                 html
                 |> then(&("<template>" <> &1))
                 |> LazyHTML.from_fragment()
                 |> LazyHTML.to_tree()
                 |> then(fn [{"template", [], c} | rest] -> c ++ rest end)
      end
    end

    test "a title in svg is not a text element" do
      assert Tree.parse_fragment(~s(<svg><title><noscript>a</noscript></title></svg><p>b</p><noscript><p>c</noscript>)) ==
               [
                 {"svg", [], [{"title", [], [{"noscript", [], ["a"]}]}]},
                 {"p", [], ["b"]},
                 {"noscript", [], [{"p", [], ["c"]}]}
               ]
    end

    test "a template in the input is never taken for a noscript" do
      html =
        ~s(<template data-brando-noscript="0"><p>mine</p></template><template data-brando-noscript="0"></template><noscript>n</noscript>)

      assert Tree.parse_fragment(html) == [
               {"template", [{"data-brando-noscript", "0"}], [{"p", [], ["mine"]}]},
               {"template", [{"data-brando-noscript", "0"}], []},
               {"noscript", [], ["n"]}
             ]

      assert Tree.parse_fragment(html) == Floki.parse_fragment!(html)
    end

    # Counts reductions, not time, so a slow or loaded runner cannot fail it.
    # Each unclosed `<title>` runs to the end of the input: a scan that
    # searched from each one again would do about 16 times the work for 4
    # times the input (the regex this scan replaced did), a linear one about 4.
    test "finding noscripts is linear in the input" do
      html = fn titles -> "<noscript>a</noscript>" <> String.duplicate("<title>a ", titles) end

      # Each measured parse must also be a whole one: a scan that gave up early
      # on a large input would count few reductions.
      parse = fn titles ->
        reductions(fn ->
          assert [{"noscript", [], ["a"]}, {"title", [], [_]}] = Tree.parse_fragment(html.(titles))
        end)
      end

      ratio = parse.(8000) / parse.(2000)

      assert ratio < 8, "4 times the input took #{Float.round(ratio, 1)} times the reductions"
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

  # The reductions `fun` takes in a process of its own.
  defp reductions(fun) do
    fn ->
      {:reductions, before} = Process.info(self(), :reductions)
      fun.()
      {:reductions, after_fun} = Process.info(self(), :reductions)
      after_fun - before
    end
    |> Task.async()
    |> Task.await(:infinity)
  end
end
