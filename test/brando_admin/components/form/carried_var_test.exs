defmodule BrandoAdmin.Components.Form.CarriedVarTest do
  # A var the block editor shows no field for still round-trips its
  # definition through hidden inputs while it is unsaved. Its label, and its
  # options' labels, are language maps: one input per language.
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest

  alias Brando.Content.Block
  alias Brando.Content.Var
  alias BrandoAdmin.Components.Form.Block.Render

  defp wrapper(assigns) do
    ~H"""
    <.form :let={f} for={@changeset} as={:block}>
      <.inputs_for :let={var} field={f[:vars]}>
        <Render.carried_var var={var} />
      </.inputs_for>
    </.form>
    """
  end

  test "a label map and option label maps are carried as one input per language" do
    var = %Var{
      key: "size",
      type: :select,
      label: %{"en" => "Size", "no" => "Størrelse"},
      value: "40",
      options: [%Var.Option{label: %{"en" => "Small", "no" => "Liten"}, value: "40"}]
    }

    changeset = Ecto.Changeset.change(%Block{vars: [var]})
    html = render_component(&wrapper/1, changeset: changeset)

    assert html =~ ~s(name="block[vars][0][label][en]" value="Size")
    assert html =~ ~s(name="block[vars][0][label][no]" value="Størrelse")
    assert html =~ ~s(name="block[vars][0][options][0][label][en]" value="Small")
    assert html =~ ~s(name="block[vars][0][options][0][label][no]" value="Liten")
    assert html =~ ~s(name="block[vars][0][options][0][value]" value="40")
  end
end
