defmodule BrandoAdmin.Components.Form.TranslationFillTest do
  use ExUnit.Case, async: true

  alias Brando.Forms.Form
  alias Brando.Forms.Recipient
  alias Brando.SyncTest.Article
  alias Brando.SyncTest.ArticleItem
  alias BrandoAdmin.Components.Form.TranslationFill
  alias Ecto.Changeset

  describe "fillable/1" do
    setup do
      article = %Article{items: [%ArticleItem{uid: "i1", label: "Punkt"}]}

      assigns = %{
        schema: Article,
        form_blueprint: Article.__form__(:default),
        current_user: %Brando.Users.User{role: :superuser},
        form: Phoenix.Component.to_form(Changeset.change(article))
      }

      %{fillable: TranslationFill.fillable(assigns)}
    end

    test "an address is not filled: it stays the editor's", %{fillable: fillable} do
      refute fillable.("entry_blocks/s1/vars/link/url", {:block, "b1", "m1", ["vars", "link", "url"]})

      refute fillable.(
               "entry_blocks/s1/rows/r1/vars/link/url",
               {:block, "b1", "m1", ["rows", "r1", "vars", "link", "url"]}
             )
    end

    test "a text is filled", %{fillable: fillable} do
      assert fillable.("title", {:field, "title"})
      assert fillable.("items/i1/label", {:row, "items", "i1", "label"})
      assert fillable.("entry_blocks/s1/vars/link/link_text", {:block, "b1", "m1", ["vars", "link", "link_text"]})
      assert fillable.("entry_blocks/s1/refs/body/text", {:block, "b1", "m1", ["refs", "body", "text"]})
    end

    test "a text the form has no input or row for is not", %{fillable: fillable} do
      refute fillable.("language", {:field, "language"})
      refute fillable.("items/gone/label", {:row, "items", "gone", "label"})
      refute fillable.("notes/s1/refs/body/text", {:block, "b1", "m1", ["refs", "body", "text"]})
    end
  end

  describe "address?/2" do
    test "a link variable's address is one, in a block, a block's table row or a page's variables" do
      assert TranslationFill.address?(Article, {:block, "b1", "m1", ["vars", "link", "url"]})
      assert TranslationFill.address?(Article, {:block, "b1", "m1", ["rows", "r1", "vars", "link", "url"]})
      assert TranslationFill.address?(Brando.Pages.Page, {:row, "vars", "link", "url"})
    end

    test "a text named url that is not a link variable's is not" do
      refute TranslationFill.address?(Article, {:field, "url"})
      refute TranslationFill.address?(Article, {:row, "items", "i1", "url"})
      refute TranslationFill.address?(Article, {:block, "b1", "m1", ["refs", "url", "text"]})
      refute TranslationFill.address?(Brando.Pages.Page, {:row, "vars", "link", "link_text"})
    end
  end

  describe "a row of an embeds_many subform" do
    setup do
      form = %Form{
        recipients: [
          %Recipient{uid: "r1", name: "Ola", email: "ola@example.com"},
          %Recipient{uid: "r2", name: "Kari", email: "kari@example.com"}
        ]
      }

      %{changeset: Changeset.change(form)}
    end

    test "is read by its uid", %{changeset: changeset} do
      assert TranslationFill.field_value(changeset, {:row, "recipients", "r2", "name"}) == "Kari"
      assert TranslationFill.field_value(changeset, {:row, "recipients", "gone", "name"}) == :error
    end

    test "is filled, and the other rows stay", %{changeset: changeset} do
      assert {:ok, filled} = TranslationFill.put_field(changeset, {:row, "recipients", "r2", "name"}, "Kari N.")
      assert TranslationFill.field_value(filled, {:row, "recipients", "r2", "name"}) == "Kari N."
      assert TranslationFill.field_value(filled, {:row, "recipients", "r1", "name"}) == "Ola"
      assert [%{name: "Ola"}, %{name: "Kari N."}] = Changeset.apply_changes(filled).recipients
    end

    test "reads a row changed since as it is now", %{changeset: changeset} do
      rows = Changeset.get_embed(changeset, :recipients, :changeset)
      edited = List.update_at(rows, 0, &Changeset.put_change(&1, :name, "Per"))
      changeset = Changeset.put_embed(changeset, :recipients, edited)

      assert TranslationFill.field_value(changeset, {:row, "recipients", "r1", "name"}) == "Per"
    end
  end
end
