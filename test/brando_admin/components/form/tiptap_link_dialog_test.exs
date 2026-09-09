defmodule BrandoAdmin.Components.Form.TipTapLinkDialogTest do
  use ExUnit.Case, async: true
  alias BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog, as: Dialog

  defp open(params \\ %{}) do
    {:ok, socket} = Dialog.mount(%Phoenix.LiveView.Socket{})

    {:ok, socket} =
      Dialog.update(
        Map.merge(
          %{
            event: :open,
            tiptap_id: "body",
            request_id: "request",
            current_href: "/rooms",
            current_class: "extra",
            link_text: "Our rooms"
          },
          params
        ),
        socket
      )

    socket
  end

  test "existing targets are preserved and unsafe destinations keep the dialog open" do
    socket = open(%{current_target: "_blank", current_rel: "sponsored noopener"})
    assert {:ok, %{target: "_blank", rel: rel}} = Dialog.build_link_data(socket.assigns)
    assert rel =~ "sponsored"
    assert rel =~ "noreferrer"
    {:noreply, invalid} = Dialog.handle_event("confirm_link", %{"link" => %{"url" => "javascript:alert(1)"}}, socket)
    assert invalid.assigns.show
    assert invalid.assigns.error
    refute_receive {:tiptap_set_link, _, _}
  end

  test "apply waits for the editor acknowledgment and keeps authored text/classes" do
    socket = open()

    {:noreply, applying} =
      Dialog.handle_event("confirm_link", %{"link" => %{"url" => "example.com", "appearance" => "button"}}, socket)

    assert applying.assigns.show
    assert applying.assigns.applying

    assert_receive {:tiptap_set_link, "body",
                    %{
                      href: "https://example.com",
                      link_text: "Our rooms",
                      class: "extra",
                      mark_type: "button",
                      target: nil,
                      request_id: "request"
                    }}

    {:ok, stale} = Dialog.update(%{event: :applied, request_id: "request", applied: false}, applying)
    assert stale.assigns.show
    assert stale.assigns.error
    {:ok, closed} = Dialog.update(%{event: :applied, request_id: "request", applied: true}, applying)
    refute closed.assigns.show
    assert_receive {:tiptap_set_link, "body", %{closed: true}}
  end

  test "anchor destinations remain readable and empty fragments are rejected" do
    socket = open(%{current_href: "#Getting-here"})
    assert {:ok, %{href: "#Getting-here"}} = Dialog.build_link_data(socket.assigns)
    {:noreply, invalid} = Dialog.handle_event("validate_link", %{"link" => %{"anchor" => "#"}}, socket)
    assert {:error, :invalid_link} = Dialog.build_link_data(invalid.assigns)
  end
end
