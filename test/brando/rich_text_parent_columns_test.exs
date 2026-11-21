defmodule Brando.RichTextParentColumnsTest do
  # A schema's own column is rich text only when one of its own top-level
  # inputs says so: a subform row's rich-text input named like a plain
  # column of the parent (`text`) does not make that column rich text, when
  # it is saved, printed in a template or shown in a proposal review. The
  # row's own rich text is still treated as rich text.
  use Brando.ConnCase, async: true

  alias Brando.Content.Proposals.Proposal
  alias Brando.Content.Proposals.Review
  alias Brando.Content.Proposals.SetFields
  alias Brando.RichTextRows.CheckedItem
  alias Brando.RichTextRows.Entry
  alias Brando.RichTextRows.Plain
  alias Ecto.Changeset

  @unsafe ~s{<p><a href="javascript:alert(1)">link</a></p>}
  @commented "<p>A text</p><!-- note -->"

  defp render(template, entry), do: Brando.Villain.parse_and_render(template, Brando.Villain.get_base_context(entry))

  describe "saving" do
    test "the parent's plain column is stored as typed" do
      for html <- [@commented, @unsafe] do
        changeset = Plain.changeset(%Plain{}, %{title: "T", text: html}, :system)
        assert changeset.valid?, html
        assert Changeset.get_change(changeset, :text) == html
      end
    end

    test "the row's rich text is still checked" do
      changeset = Plain.changeset(%Plain{}, %{title: "T", quotes: [%{text: @unsafe}]}, :system)
      refute changeset.valid?
      assert [%{errors: [text: _]}] = Changeset.get_change(changeset, :quotes)

      changeset = Plain.changeset(%Plain{}, %{title: "T", quotes: [%{text: @commented}]}, :system)
      assert [row] = Changeset.get_change(changeset, :quotes)
      assert Changeset.get_field(row, :text) == "<p>A text</p>"
    end
  end

  describe "printing" do
    test "the parent's plain column prints escaped" do
      html = render("{{ entry.text }}", %Plain{title: "T", text: "<em>Hi</em>"})
      refute html =~ "<em>"
      assert html =~ "&lt;em&gt;"
    end

    test "a row whose own form draws its text as rich text prints it as markup" do
      entry = %Entry{title: "T", checked_items: [%CheckedItem{text: "<p>A <em>row</em></p>"}]}
      html = render("{% for item in entry.checked_items %}{{ item.text }}{% endfor %}", entry)
      assert html == "<p>A <em>row</em></p>"
    end
  end

  describe "a proposal review" do
    defp field_view(entry, field, value) do
      target = {entry.__struct__, entry.id}

      proposal = %Proposal{
        targets: %{target => entry},
        operations: [%SetFields{target: target, fields: %{field => value}}]
      }

      [%{changes: [%{fields: [view]}]}] = Review.entries(proposal)
      view
    end

    test "shows the parent's plain column as the text it holds" do
      view = field_view(%Plain{id: 1, title: "T", text: "<p>Old</p>"}, "text", "<p>New</p>")
      assert view.value =~ "<p>New</p>"
    end

    # Rows are shown whole, their markup as it is, by no list of rich-text
    # names
    test "shows a subform's rows whole" do
      entry = %Plain{id: 1, title: "T", quotes: [%Brando.RichTextRows.Quote{text: "<p>Old</p>"}]}
      view = field_view(entry, "quotes", [%{"text" => "<p>New <em>row</em></p>"}])
      assert view.value =~ "<p>New <em>row</em></p>"
      assert view.before =~ "<p>Old</p>"
    end

    test "shows a top-level rich-text column as its text" do
      view = field_view(%Entry{id: 1, title: "T", intro: "<p>Old</p>"}, "intro", "<p>New</p>")
      refute view.value =~ "<p>"
      assert view.value =~ "New"
    end
  end
end
