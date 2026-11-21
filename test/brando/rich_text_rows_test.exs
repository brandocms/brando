defmodule Brando.RichTextRowsTest do
  # A rich-text input in a subform row is saved as a top-level one is
  # (Brando.RichText.validate_fields/2): sanitized, and refused with an
  # error on the row's field when it holds unsafe markup. Each case saves
  # through the parent's changeset, which the admin form's save uses too.
  use ExUnit.Case, async: true

  alias Brando.Pages.Page
  alias Brando.RichTextRows.Entry
  alias Brando.RichTextRows.Feature
  alias Brando.RichTextRows.Item
  alias Brando.RichTextRows.Quote
  alias Ecto.Changeset

  @unsafe [
    ~s{<p><a href="javascript:alert(1)">link</a></p>},
    ~s{<p onclick="alert(1)">text</p>},
    "<p>text</p><script>alert(1)</script>"
  ]
  @safe ~s(<p>A <strong>quote</strong> with <a href="https://example.com/">a link</a></p>)
  @commented "<p>A quote</p><!-- note -->"
  @sanitized "<p>A quote</p>"

  defp changeset(entry \\ %Entry{}, params), do: Entry.changeset(entry, params, :system)

  defp errors(changeset), do: Changeset.traverse_errors(changeset, fn {message, _} -> message end)

  defp row_text(%Changeset{} = row), do: Changeset.get_field(row, :text)

  describe "an embeds_many row" do
    # The rows the entry keeps: a row sent without its id replaces the stored one
    defp quotes(changeset), do: changeset |> Changeset.get_change(:quotes, []) |> Enum.reject(&(&1.action == :replace))

    test "is refused with unsafe markup, the error on the row's text" do
      for html <- @unsafe do
        changeset = changeset(%{quotes: [%{text: "<p>Kept</p>"}, %{text: html}]})
        refute changeset.valid?, html
        assert [kept, refused] = quotes(changeset)
        assert kept.errors == []
        assert Keyword.has_key?(refused.errors, :text)
      end
    end

    test "stores safe markup as it is, and sanitized markup sanitized" do
      changeset = changeset(%{quotes: [%{text: @safe}, %{text: @commented}]})
      assert changeset.valid?
      assert Enum.map(quotes(changeset), &row_text/1) == [@safe, @sanitized]
    end
  end

  describe "an embeds_one row" do
    test "is refused with unsafe markup, the error on the row's text" do
      for html <- @unsafe do
        changeset = changeset(%{feature: %{text: html}})
        refute changeset.valid?, html
        assert %{feature: %{text: [_]}} = errors(changeset)
      end
    end

    test "stores safe markup as it is, and sanitized markup sanitized" do
      for {html, stored} <- [{@safe, @safe}, {@commented, @sanitized}] do
        changeset = changeset(%{feature: %{text: html}})
        assert changeset.valid?
        assert changeset |> Changeset.get_change(:feature) |> row_text() == stored
      end
    end
  end

  describe "a has_many row cast with its parent" do
    defp items(changeset), do: Changeset.get_change(changeset, :items, [])

    test "is refused with unsafe markup, the error on the row's text" do
      for html <- @unsafe do
        changeset = changeset(%{items: [%{label: "A", text: html}]})
        refute changeset.valid?, html
        assert %{items: [%{text: [_]}]} = errors(changeset)
      end
    end

    test "stores safe markup as it is, and sanitized markup sanitized" do
      changeset = changeset(%{items: [%{label: "A", text: @safe}, %{label: "B", text: @commented}]})
      assert changeset.valid?
      assert Enum.map(items(changeset), &row_text/1) == [@safe, @sanitized]
    end
  end

  test "a has_many row whose own form checks the text has the error once" do
    changeset = changeset(%{checked_items: [%{text: hd(@unsafe)}]})
    refute changeset.valid?
    assert [%{errors: [text: _]}] = Changeset.get_change(changeset, :checked_items)
  end

  describe "a rich-text page variable" do
    defp var_params(value), do: %{type: "rich_text", key: "intro", label: %{"en" => "Intro"}, value: value}

    test "is refused with unsafe markup, the error on the variable's value" do
      for html <- @unsafe do
        changeset = Page.changeset(%Page{}, %{vars: [var_params(html)]}, :system)
        refute changeset.valid?, html
        assert [%{value: [_]}] = errors(changeset).vars
      end
    end

    test "stores safe markup as it is, and sanitized markup sanitized" do
      changeset = Page.changeset(%Page{}, %{vars: [var_params(@safe), var_params(@commented)]}, %{id: 0})
      assert [safe, sanitized] = Changeset.get_change(changeset, :vars)
      assert {safe.valid?, sanitized.valid?} == {true, true}
      assert Enum.map([safe, sanitized], &Changeset.get_field(&1, :value)) == [@safe, @sanitized]
    end
  end

  describe "a row stored before the check" do
    @stored ~s{<p onclick="x()">Old</p>}

    test "an unchanged embeds_many row keeps its text while the entry changes" do
      quote_row = %Quote{id: Ecto.UUID.generate(), text: @stored, credit: "A"}
      entry = %Entry{title: "Old", quotes: [quote_row]}

      # Sent back as the form sends it, with and without the row's id
      for row <- [%{id: quote_row.id, text: @stored, credit: "A"}, %{text: @stored, credit: "A"}] do
        changeset = changeset(entry, %{title: "New", quotes: [row, %{text: "<p>New</p>"}]})
        assert changeset.valid?, inspect(errors(changeset))
        assert [%{} = kept, _] = quotes(changeset)
        assert row_text(kept) == @stored
      end

      # The stored text in a row that changes is checked
      refute changeset(entry, %{quotes: [%{text: @stored, credit: "B"}]}).valid?
    end

    test "a stored row keeps the text of one copy sent without its id, not of two" do
      entry = %Entry{title: "Old", quotes: [%Quote{id: Ecto.UUID.generate(), text: @stored, credit: "A"}]}
      copy = %{text: @stored, credit: "A"}

      changeset = changeset(entry, %{quotes: [copy, copy]})
      refute changeset.valid?
      assert [kept, checked] = quotes(changeset)
      assert kept.errors == []
      assert Keyword.has_key?(checked.errors, :text)
    end

    test "an unchanged embeds_one row keeps its text while the entry changes" do
      entry = %Entry{title: "Old", feature: %Feature{id: Ecto.UUID.generate(), text: @stored}}

      for row <- [%{id: entry.feature.id, text: @stored}, %{text: @stored}] do
        assert changeset(entry, %{title: "New", feature: row}).valid?
      end
    end

    test "an unchanged has_many row keeps its text while the entry changes" do
      entry = %Entry{id: 1, title: "Old", items: [%Item{id: 1, entry_id: 1, label: "A", text: @stored}]}

      changeset = changeset(entry, %{title: "New", items: [%{id: 1, label: "B", text: @stored}]})
      assert changeset.valid?, inspect(errors(changeset))

      refute changeset(entry, %{items: [%{id: 1, label: "B", text: "<p onclick=\"y()\">New</p>"}]}).valid?
    end
  end

  describe "a transformer subform's rows" do
    # The admin form puts these rows on the entry's changeset after the
    # entry's changeset ran (its save's assoc_all_transformer_fields/2), so
    # they are checked there: built and collected by the transformer, put on
    # the changeset, then Brando.RichText.validate_subform_rows/3.
    alias Brando.Blueprint.Forms.Subform
    alias BrandoAdmin.Components.Form.Transformer
    alias Phoenix.Component

    defp transformer_socket(items) do
      %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}}
      |> Component.assign(:items, items)
      |> Component.assign(:form_id, "entry_form")
      |> Component.assign(:relation_key, :items)
      |> Component.assign(:relation_module, Item)
      |> Component.assign(:image_field, nil)
      |> Component.assign(:video_field, nil)
      |> Component.assign(:subform, Enum.find(subforms(), &(&1.name == :items)))
      |> Phoenix.LiveView.stream(:transformer_items, [])
    end

    defp subforms do
      for tab <- Entry.__form__().tabs, fieldset <- tab.fields, %Subform{} = subform <- fieldset.fields, do: subform
    end

    # The rows the form's save puts on `entry`'s changeset after the editor
    # typed `text` into the row `dom_id`
    defp saved_with_edit(entry, items, dom_id, text) do
      {:noreply, socket} =
        Transformer.handle_event(
          "update_field",
          %{"dom_id" => dom_id, "field" => "text", "value" => text},
          transformer_socket(items)
        )

      {:ok, _} = Transformer.update(%{event: "fetch_transformer_data", tag: "save"}, socket)

      assert_receive {:phoenix, :send_update, {_, %{event: "provide_transformer_data", transformer_data: rows}}}

      entry
      |> changeset(%{title: "New"})
      |> Changeset.put_assoc(:items, rows)
      |> Brando.RichText.validate_subform_rows(Entry, [:items])
    end

    @entry %Entry{id: 1, title: "Old", items: [%Item{id: 1, entry_id: 1, label: "A", text: "<p>Old</p>"}]}

    test "an edited stored row is refused with unsafe markup, the error on its text" do
      item = Transformer.new_item("item-1", hd(@entry.items), is_new: false)

      for html <- @unsafe do
        changeset = saved_with_edit(@entry, [item], "item-1", html)
        refute changeset.valid?, html
        assert %{items: [%{text: [_]}]} = errors(changeset)
      end

      changeset = saved_with_edit(@entry, [item], "item-1", @commented)
      assert changeset.valid?
      assert [row] = Changeset.get_change(changeset, :items)
      assert row_text(row) == @sanitized
    end

    test "a new row is refused with unsafe markup, the error on its text" do
      stored = Transformer.new_item("item-1", hd(@entry.items), is_new: false)
      new = Transformer.new_item("item-new", %{label: "B", text: nil})

      for html <- @unsafe do
        changeset = saved_with_edit(@entry, [stored, new], "item-new", html)
        refute changeset.valid?, html
        assert %{items: [%{}, %{text: [_]}]} = errors(changeset)
      end

      changeset = saved_with_edit(@entry, [stored, new], "item-new", @commented)
      assert changeset.valid?
      assert [_, row] = Changeset.get_change(changeset, :items)
      assert row_text(row) == @sanitized
    end
  end

  test "rows are checked by the form that draws them, not only by the default form" do
    # The article's default form draws a quote's text as plain text; its
    # `rich_quotes` form draws it as rich text.
    article = Brando.SyncTest.Article

    changeset =
      article
      |> struct()
      |> Changeset.change()
      |> Changeset.put_embed(:quotes, [%{text: hd(@unsafe)}])

    assert Brando.RichText.validate_subform_rows(changeset, article, [:quotes]).valid?

    refused = Brando.RichText.validate_subform_rows(changeset, article.__form__(:rich_quotes), [:quotes])
    refute refused.valid?
    assert [%{errors: [text: _]}] = Changeset.get_change(refused, :quotes)
  end

  describe "the form in use" do
    # The article's `notes` form draws its subtitle as rich text and its
    # `rich_quotes` form a quote's text; the default form draws both as
    # plain text. The admin form checks the form it saves from
    # (Brando.RichText.validate_form/2) after the schema's changeset, which
    # checks by the default form.
    alias Brando.SyncTest.Article

    @article %{title: "Article", slug: "article", language: "en", status: "published", creator_id: 1}

    defp article_changeset(params, form) do
      %Article{}
      |> Article.changeset(Map.merge(@article, params), :system)
      |> Brando.RichText.validate_form(form)
    end

    test "a top-level rich-text input only a named form declares is refused with unsafe markup" do
      for html <- @unsafe do
        changeset = article_changeset(%{subtitle: html}, Article.__form__(:notes))
        refute changeset.valid?, html
        assert Keyword.has_key?(changeset.errors, :subtitle)
      end

      changeset = article_changeset(%{subtitle: @commented}, Article.__form__(:notes))
      assert changeset.valid?
      assert Changeset.get_change(changeset, :subtitle) == @sanitized
    end

    test "a subform row's rich-text input only a named form declares is refused with unsafe markup" do
      for html <- @unsafe do
        changeset = article_changeset(%{quotes: [%{text: "<p>Kept</p>"}, %{text: html}]}, Article.__form__(:rich_quotes))
        refute changeset.valid?, html
        assert [kept, refused] = Changeset.get_change(changeset, :quotes)
        assert kept.errors == []
        assert Keyword.has_key?(refused.errors, :text)
      end

      changeset = article_changeset(%{quotes: [%{text: @commented}]}, Article.__form__(:rich_quotes))
      assert changeset.valid?
      assert [row] = Changeset.get_change(changeset, :quotes)
      assert row_text(row) == @sanitized
    end

    test "the same fields saved from the default form, where they are plain text, are stored as typed" do
      for html <- [@commented | @unsafe] do
        changeset = article_changeset(%{subtitle: html, quotes: [%{text: html}]}, Article.__form__())
        assert changeset.valid?, html
        assert Changeset.get_change(changeset, :subtitle) == html
        assert [row] = Changeset.get_change(changeset, :quotes)
        assert row_text(row) == html
      end
    end

    test "an untouched field or row holding old unsafe text does not block the save" do
      stored = ~s{<p onclick="x()">Old</p>}

      article = %Article{
        subtitle: stored,
        quotes: [%Brando.SyncTest.ArticleQuote{id: Ecto.UUID.generate(), text: stored}]
      }

      [quote_row] = article.quotes

      changeset =
        article
        |> Article.changeset(
          Map.merge(@article, %{subtitle: stored, quotes: [%{id: quote_row.id, text: stored}]}),
          :system
        )
        |> Brando.RichText.validate_form(Article.__form__(:notes))
        |> Brando.RichText.validate_form(Article.__form__(:rich_quotes))

      assert changeset.errors == []
      assert Enum.all?(Changeset.get_change(changeset, :quotes, []), &(&1.errors == []))
    end
  end

  test "the entry's own rich text is still checked" do
    refute changeset(%{intro: hd(@unsafe)}).valid?
    assert changeset(%{intro: @safe}).valid?
  end

  test "rows of a module without a form are not checked" do
    assert Quote.changeset(%Quote{}, %{text: hd(@unsafe)}, :system).valid?
  end
end
