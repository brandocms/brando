defmodule Brando.Villain.RichTextRowsPrintingTest do
  # A subform row's rich text prints as a top-level rich-text field does:
  # through Brando.RichText.render_html/1, its markup sanitized, or its
  # text alone when it holds unsafe markup stored before rows were checked.
  # A row field is rich text for printing when the owning schema's forms
  # draw it as a `:rich_text` input in a subform on that relation: at least
  # one does and none draws it as another input, or, when they disagree,
  # the default form does. The row's own module (embedded, or without a
  # form) does not say so.
  use Brando.ConnCase, async: true

  alias Brando.RichTextRows.CheckedItem
  alias Brando.RichTextRows.Disagreeing
  alias Brando.RichTextRows.DisagreeingItem
  alias Brando.RichTextRows.Entry
  alias Brando.RichTextRows.Feature
  alias Brando.RichTextRows.Item
  alias Brando.RichTextRows.Quote
  alias Ecto.Changeset

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

  describe "a row field forms disagree on" do
    # What an editor typed in a form that draws the field as plain text
    @link ~s(<a href="/help">Help</a>)
    @quote ~s[x" onmouseover="alert(1)]

    # Disagreeing's default form draws each of these as plain text and its
    # `:plain` form as rich text: an embeds_many row, the has_many rows of a
    # transformer, and a has_one row
    defp plain_by_default do
      [
        {"an embeds_many row", "{% for r in entry.quotes %}FIELD{% endfor %}", &%Disagreeing{quotes: [%Quote{text: &1}]}},
        {"a transformer's has_many row", "{% for r in entry.items %}FIELD{% endfor %}",
         &%Disagreeing{items: [%DisagreeingItem{text: &1}]}},
        {"a has_one row", "{% assign r = entry.lead %}FIELD", &%Disagreeing{lead: %DisagreeingItem{text: &1}}},
        # The article's default form draws a quote's text as plain text, its
        # `rich_quotes` form as rich text
        {"an article's quote", "{% for r in entry.quotes %}FIELD{% endfor %}",
         &%Brando.SyncTest.Article{quotes: [%Brando.SyncTest.ArticleQuote{text: &1}]}}
      ]
    end

    defp render_row(template, field, entry_fun, text),
      do: render(String.replace(template, "FIELD", field), %{entry_fun.(text) | title: "T"})

    test "prints typed markup as text when the default form draws it as plain text" do
      for {kind, template, entry_fun} <- plain_by_default() do
        html = render_row(template, "{{ r.text }}", entry_fun, @link)
        assert html == "&lt;a href=&quot;/help&quot;&gt;Help&lt;/a&gt;", kind
      end
    end

    test "keeps a typed quote inside an attribute when the default form draws it as plain text" do
      for {kind, template, entry_fun} <- plain_by_default() do
        html = render_row(template, ~s(<div title="{{ r.text }}"></div>), entry_fun, @quote)
        assert [{"div", [{"title", @quote}], []}] == Floki.parse_fragment!(html), kind
      end
    end

    test "prints through a filter and raw as a plain field does" do
      for {kind, template, entry_fun} <- plain_by_default() do
        html = render_row(template, "{{ r.text | truncate: 100 }}", entry_fun, @link)
        assert Floki.find(Floki.parse_fragment!(html), "a") == [], kind

        # `raw` is how a template opts in to a plain field's markup
        assert render_row(template, "{{ r.text | raw }}", entry_fun, @link) ==
                 render("{{ entry.title | raw }}", %{
                   entry_fun.(nil)
                   | title: @link
                 }),
               kind
      end
    end

    test "prints as sanitized markup when the default form draws it as rich text" do
      # A feature's text is rich text in the default form and plain text in
      # the `:plain` form
      entry = %Disagreeing{title: "T", feature: %Feature{text: @safe}}
      assert render("{{ entry.feature.text }}", entry) == @safe

      entry = %Disagreeing{title: "T", feature: %Feature{text: @stored_unsafe}}
      refute render("{{ entry.feature.text }}", entry) =~ "<"
    end

    test "prints as text when the default form does not draw it" do
      # A note's credit is rich text in the `:aside` form and plain text in
      # the `:plain` form
      entry = %Disagreeing{title: "T", notes: [%Quote{credit: @link}]}
      assert render("{% for n in entry.notes %}{{ n.credit }}{% endfor %}", entry) =~ "&lt;a href"
    end
  end

  describe "a row field only named forms draw, all as rich text" do
    # A note's text is drawn by the `:plain` and `:aside` forms, each as rich
    # text, and not by the default form
    test "prints as sanitized markup" do
      entry = %Disagreeing{title: "T", notes: [%Quote{text: @safe}]}
      assert render("{% for n in entry.notes %}{{ n.text }}{% endfor %}", entry) == @safe

      entry = %Disagreeing{title: "T", notes: [%Quote{text: @stored_unsafe}]}
      html = render("{% for n in entry.notes %}{{ n.text | raw }}{% endfor %}", entry)
      refute html =~ "onclick"
      assert html =~ "Old"
    end
  end

  test "the rows' rule for printing names the fields of each kind of row" do
    expected = [quotes: [], feature: [:text], notes: [:text], items: [], lead: []]

    assert for({relation, _} <- expected, do: {relation, Brando.RichText.row_fields_for_printing(Disagreeing, relation)}) ==
             expected

    assert Brando.RichText.row_fields_for_printing(Entry, :quotes) == [:text]
    assert Brando.RichText.row_fields_for_printing(Brando.SyncTest.Article, :quotes) == []
  end

  test "a save checks rows by the form in use and the default form, as before" do
    unsafe = ~s{<p onclick="alert(1)">text</p>}

    changeset =
      %Disagreeing{}
      |> Changeset.change()
      |> Changeset.put_embed(:quotes, [%{text: unsafe}])
      |> Changeset.put_embed(:notes, [%{text: unsafe}])

    # The default form draws neither a quote's nor a note's text as rich text
    assert Brando.RichText.validate_subform_rows(changeset, Disagreeing, [:quotes, :notes]).valid?

    for {form, relation} <- [plain: :quotes, plain: :notes, aside: :notes] do
      refused = Brando.RichText.validate_subform_rows(changeset, Disagreeing.__form__(form), [relation])
      refute refused.valid?, "#{form} #{relation}"
      assert [%{errors: [text: _]}] = Changeset.get_change(refused, relation)
    end

    # The default form draws a feature's text as rich text, the `:plain`
    # form as plain text
    changeset = %Disagreeing{} |> Changeset.change() |> Changeset.put_embed(:feature, %{text: unsafe})
    refute Brando.RichText.validate_subform_rows(changeset, Disagreeing, [:feature]).valid?
    assert Brando.RichText.validate_subform_rows(changeset, Disagreeing.__form__(:plain), [:feature]).valid?
  end

  describe "a has_many row whose own form draws the field as rich text" do
    # The owner's default form draws a checked item's text as plain text;
    # CheckedItem's own default form draws it as rich text.
    defmodule PlainOwner do
      @moduledoc false
      use Brando.Blueprint,
        application: "Brando",
        domain: "RichTextRows",
        schema: "PlainOwner",
        singular: "plain_owner",
        plural: "plain_owners",
        gettext_module: Brando.Gettext

      identifier "{{ entry.title }}"
      persist_identifier false

      attributes do
        attribute :title, :string
      end

      relations do
        relation :checked_items, :has_many,
          module: Brando.RichTextRows.CheckedItem,
          foreign_key: :entry_id,
          on_replace: :delete,
          cast: true,
          sort_param: :sort_checked_items_ids,
          drop_param: :drop_checked_items_ids
      end

      forms do
        form do
          tab "Content" do
            fieldset do
              input :title, :text
            end

            fieldset do
              inputs_for :checked_items do
                cardinality :many
                style :inline
                default %{}

                input :text, :textarea
              end
            end
          end
        end
      end
    end

    test "is checked by the row's own changeset when saved through the owner" do
      changeset = PlainOwner.changeset(%PlainOwner{}, %{checked_items: [%{text: ~s{<p onclick="x()">A</p>}}]}, :system)
      refute changeset.valid?
      assert [%{errors: [text: _]}] = Changeset.get_change(changeset, :checked_items)
    end

    # A link typed in the owner's textarea passes the row's check and prints
    # live, and a typed quote ends the attribute it is printed in. Not fixed
    # here: the owner's rule would print it as text, which changes what such
    # sites print today (#3807).
    @tag skip: "prints by the row's own form, not the owner's: Brando.Villain.TemplateView.read_text/3 (#3807)"
    test "prints typed markup as text, as the owner's form draws it" do
      entry = %PlainOwner{title: "T", checked_items: [%CheckedItem{text: ~s(<a href="/help">Help</a>)}]}

      assert render("{% for r in entry.checked_items %}{{ r.text }}{% endfor %}", entry) ==
               "&lt;a href=&quot;/help&quot;&gt;Help&lt;/a&gt;"

      typed = ~s[x" onmouseover="alert(1)]
      entry = %PlainOwner{title: "T", checked_items: [%CheckedItem{text: typed}]}
      html = render(~s(<div title="{{ entry.checked_items[0].text }}"></div>), entry)
      assert [{"div", [{"title", ^typed}], []}] = Floki.parse_fragment!(html)
    end
  end
end
