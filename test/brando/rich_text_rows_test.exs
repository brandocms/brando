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

  test "the entry's own rich text is still checked" do
    refute changeset(%{intro: hd(@unsafe)}).valid?
    assert changeset(%{intro: @safe}).valid?
  end

  test "rows of a module without a form are not checked" do
    assert Quote.changeset(%Quote{}, %{text: hd(@unsafe)}, :system).valid?
  end
end
