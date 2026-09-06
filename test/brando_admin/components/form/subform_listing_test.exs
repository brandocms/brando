defmodule BrandoAdmin.Components.Form.SubformListingTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.Subform
  alias Ecto.Changeset

  defmodule Item do
    use Ecto.Schema

    embedded_schema do
      field :title, :string
    end
  end

  defp form(item, key, changes \\ %{}) do
    item
    |> Changeset.change(changes)
    |> Phoenix.Component.to_form()
    |> Map.put(:params, %{"_persistent_id" => key})
  end

  test "persisted rows start collapsed and new rows start open" do
    refute Subform.entry_open?(form(%Item{id: "saved"}, "0"), %{})
    assert Subform.entry_open?(form(%Item{}, "1"), %{})
    refute Subform.entry_open?(form(%Item{}, "1"), %{"1" => false})
  end

  test "the disclosure follows the persistent form key through reordered indices" do
    moved = %{form(%Item{id: "saved"}, "original") | index: 3}
    assert Subform.entry_open?(moved, %{"original" => true, "3" => false})
  end

  test "invalid submitted rows reveal their errors even after being collapsed" do
    invalid =
      %Item{id: "saved"}
      |> Changeset.change()
      |> Changeset.validate_required([:title])
      |> Map.put(:action, :validate)
      |> Phoenix.Component.to_form()
      |> Map.put(:params, %{"_persistent_id" => "0"})

    assert Subform.entry_open?(invalid, %{"0" => false})
  end
end
