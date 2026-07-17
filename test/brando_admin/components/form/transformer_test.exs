defmodule BrandoAdmin.Components.Form.TransformerTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Forms.Subform
  alias BrandoAdmin.Components.Form.Transformer

  defmodule Item do
    use Ecto.Schema

    embedded_schema do
      field :title, :string
    end
  end

  test "builds a clean related record when no default is configured" do
    assert Transformer.build_default(%Subform{}, Item, %{title: "Parent"}, nil) == %{title: nil}
  end

  test "passes the parent and asset to an arity-2 default callback" do
    parent = %{title: "Parent"}
    asset = %{id: 42}

    subform = %Subform{
      default: fn received_parent, received_asset ->
        assert received_parent == parent
        assert received_asset == asset
        %Item{title: "Generated"}
      end
    }

    assert Transformer.build_default(subform, Item, parent, asset) == %{title: "Generated"}
  end

  test "retains explicit map defaults" do
    assert Transformer.build_default(%Subform{default: %{title: "Draft"}}, Item, %{}, nil) == %{
             title: "Draft"
           }
  end

  test "reports invalid callback return values" do
    subform = %Subform{default: fn _parent, _asset -> nil end}

    assert_raise ArgumentError, ~r/must return a map or struct, got: nil/, fn ->
      Transformer.build_default(subform, Item, %{}, nil)
    end
  end
end
