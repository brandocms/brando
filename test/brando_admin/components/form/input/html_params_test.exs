defmodule BrandoAdmin.Components.Form.Input.HtmlParamsTest do
  # The parts of an HTML ref's form. A polymorphic embed is rebuilt from the
  # params, so a form that does not show the template still carries it, and
  # values of keys no parameter declares are carried as they are.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Villain.Blocks.HtmlBlock
  alias BrandoAdmin.Components.Form.Input.Blocks.HtmlParams

  defp form(values) do
    %HtmlBlock.Data{}
    |> HtmlBlock.Data.changeset(%{
      "text" => ~s(<div data-id="{{ checkin_id }}"></div>),
      "params" => [%{"key" => "checkin_id", "label" => "Check-in ID", "type" => "id"}],
      "values" => values
    })
    |> Phoenix.Component.to_form(as: "d")
  end

  test "the values form has one input per parameter and carries other values" do
    html = render_component(&HtmlParams.values_form/1, block_data: form(%{"checkin_id" => "a1", "old" => "kept"}))

    assert html =~ ~s(name="d[values][checkin_id]")
    assert html =~ ~s(value="a1")
    assert html =~ "Check-in ID"
    assert html =~ ~s(type="hidden" name="d[values][old]" value="kept")
  end

  test "an invalid value shows why" do
    html = render_component(&HtmlParams.values_form/1, block_data: form(%{"checkin_id" => "a b"}))
    assert html =~ "Use letters, digits, _ and - only"
  end

  test "the carried template is hidden inputs only" do
    html = render_component(&HtmlParams.carried_template/1, block_data: form(%{}))

    assert html =~ ~s(type="hidden" name="d[text]")
    assert html =~ ~s(name="d[params][0][key]" value="checkin_id")
    assert html =~ ~s(name="d[params][0][type]" value="id")
    refute html =~ "<textarea"
    refute html =~ ~s(type="text")
  end
end
