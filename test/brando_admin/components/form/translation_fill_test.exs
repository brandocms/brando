defmodule BrandoAdmin.Components.Form.TranslationFillTest do
  use ExUnit.Case, async: true

  alias Brando.Forms.Form
  alias Brando.Forms.Recipient
  alias BrandoAdmin.Components.Form.TranslationFill
  alias Ecto.Changeset

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
