defmodule BrandoAdmin.Components.Content.ListSelectedRowsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Content.List

  defp rendered(schema) do
    render_component(&List.selected_rows/1,
      schema: schema,
      selected_rows: [1, 2],
      selection_actions: [],
      content_language: "en",
      target: nil
    )
  end

  test "deleting forms asks first, since the last language takes its submissions" do
    html = rendered(Brando.Forms.Form)

    assert html =~ "phx-confirm-click-message"
    assert html =~ ~s(phx-hook="Brando.ConfirmClick")
    assert html =~ "delete_selected"
  end

  test "deleting anything else goes on without asking" do
    html = rendered(Brando.Pages.Page)

    refute html =~ "phx-confirm-click-message"
    assert html =~ ~s(phx-click="delete_selected")
  end
end
