defmodule Brando.Villain.RichTextRowsPrintingTest do
  # A subform row's rich text prints as a top-level rich-text field does:
  # through Brando.RichText.render_html/1, its markup sanitized, or its
  # text alone when it holds unsafe markup stored before rows were checked.
  # A row field is rich text for printing when a form of the owning schema
  # draws it as a `:rich_text` input in a subform on that relation; the
  # row's own module (embedded, or without a form) does not say so.
  use Brando.ConnCase, async: true

  alias Brando.RichTextRows.Entry
  alias Brando.RichTextRows.Item
  alias Brando.RichTextRows.Quote

  @safe ~s(<p>A <strong>quote</strong> with <a href="https://example.com/">a link</a></p>)
  @stored_unsafe ~s{<p onclick="alert(1)">Old <em>text</em></p>}

  defp render(template, entry), do: Brando.Villain.parse_and_render(template, Brando.Villain.get_base_context(entry))

  defp entry(text), do: %Entry{title: "T", quotes: [%Quote{text: text}], items: [%Item{label: "A", text: text}]}

  for {kind, relation} <- [embeds_many: "quotes", has_many: "items"] do
    describe "a #{kind} row" do
      test "prints safe markup as markup" do
        template = "{% for row in entry.#{unquote(relation)} %}{{ row.text }}{% endfor %}"
        assert render(template, entry(@safe)) == @safe
      end

      test "prints old unsafe markup as its text only" do
        template = "{% for row in entry.#{unquote(relation)} %}{{ row.text }}{% endfor %}"
        html = render(template, entry(@stored_unsafe))
        refute html =~ "onclick"
        refute html =~ "<"
        assert html =~ "Old text"
      end

      test "prints safe markup through raw as before" do
        template = "{% for row in entry.#{unquote(relation)} %}{{ row.text | raw }}{% endfor %}"
        assert render(template, entry(@safe)) == @safe
      end

      test "through raw, old unsafe markup prints as its text only" do
        template = "{% for row in entry.#{unquote(relation)} %}{{ row.text | raw }}{% endfor %}"
        html = render(template, entry(@stored_unsafe))
        refute html =~ "onclick"
        assert html =~ "Old"
      end

      # A filter that selects or reorders the rows gives back rows that
      # print as they do in a loop
      for {filter, template} <- [
            first: "{% assign r = entry.RELATION | first %}{{ r.FIELD }}",
            reverse: "{% assign rs = entry.RELATION | reverse %}{% for r in rs %}{{ r.FIELD }}{% endfor %}",
            sort: ~s({% assign rs = entry.RELATION | sort: "text" %}{% for r in rs %}{{ r.FIELD }}{% endfor %}),
            where: ~s({% assign rs = entry.RELATION | where: "text" %}{% for r in rs %}{{ r.FIELD }}{% endfor %})
          ] do
        test "a row taken through #{filter} prints safe markup as markup" do
          template = unquote(template) |> String.replace("RELATION", unquote(relation)) |> String.replace("FIELD", "text")
          assert render(template, entry(@safe)) == @safe
        end

        test "a row taken through #{filter} prints old unsafe markup through raw as its text only" do
          template =
            unquote(template) |> String.replace("RELATION", unquote(relation)) |> String.replace("FIELD", "text | raw")

          html = render(template, entry(@stored_unsafe))
          refute html =~ "onclick"
          assert html =~ "Old"
        end
      end

      test "a plain field of the row still prints escaped" do
        entry = %Entry{title: "T", quotes: [%Quote{credit: "<em>A</em>"}], items: [%Item{label: "<em>A</em>"}]}
        field = if unquote(relation) == "quotes", do: "credit", else: "label"
        html = render("{% for row in entry.#{unquote(relation)} %}{{ row.#{field} }}{% endfor %}", entry)
        assert html =~ "&lt;em&gt;"
      end
    end
  end

  test "a row field any form of the owner draws as rich text prints as rich text" do
    # The article's default form draws a quote's text as plain text, its
    # `rich_quotes` form as rich text: the stored value may hold markup
    article = %Brando.SyncTest.Article{title: "T", quotes: [%Brando.SyncTest.ArticleQuote{text: @safe}]}
    assert render("{% for q in entry.quotes %}{{ q.text }}{% endfor %}", article) == @safe
  end
end
