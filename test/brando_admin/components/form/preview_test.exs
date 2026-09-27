defmodule BrandoAdmin.Components.Form.PreviewTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.Preview
  alias Phoenix.Component

  defp socket(fields \\ [:blocks, :sidebar]) do
    Component.assign(%Phoenix.LiveView.Socket{}, %{
      id: "preview-test",
      live_preview_active?: true,
      block_map: Enum.map(fields, &{&1, nil, nil, nil}),
      block_changesets: %{save: :untouched},
      preview_update: nil
    })
  end

  defp rendered(socket, mode, parts) do
    send(self(), {:rendered, mode, parts})
    socket
  end

  defp flush(socket) do
    token = socket.assigns.preview_update.token
    assert_receive {:phoenix, :send_update, {{Form, "preview-test"}, %{event: "flush_live_preview", token: ^token}}}
    {Preview.flush(socket, token, &rendered/3), token}
  end

  test "a burst collects each field once and renders once without touching save state" do
    socket = Enum.reduce(1..12, socket(), fn _, s -> Preview.queue(s, :live_preview_update, 0) end)
    {socket, token} = flush(socket)

    for field <- [:blocks, :sidebar] do
      id = "preview-test-blocks-#{field}"
      assert_receive {:phoenix, :send_update, {{BlockField, ^id}, %{tag: {:preview_update, ^token}}}}
    end

    socket = Preview.receive_blocks(socket, token, :blocks, [], &rendered/3)
    refute_received {:rendered, _, _}
    socket = Preview.receive_blocks(socket, token, :sidebar, [], &rendered/3)
    assert_received {:rendered, :live_preview_update, %{blocks: [], sidebar: []}}
    assert socket.assigns.block_changesets == %{save: :untouched}
    assert socket.assigns.preview_update == nil
    assert Preview.receive_blocks(socket, token, :sidebar, [], &rendered/3) == socket
    refute_receive {:rendered, _, _}, 35
    refute_received {:phoenix, :send_update, {{Form, _}, %{event: "flush_live_preview"}}}
  end

  test "reload dominates rerender and update, and an immediate request advances a delayed one" do
    socket = Preview.queue(socket([]), :live_preview_full_rerender, 1200)
    previous = socket.assigns.preview_update

    socket =
      socket
      |> Preview.queue(:live_preview_reload, 0)
      |> Preview.queue(:live_preview_update, 0)
      |> Preview.queue(:live_preview_full_rerender, 1200)

    assert socket.assigns.preview_update.token != previous.token
    assert Process.read_timer(previous.timer) == false
    assert Preview.flush(socket, previous.token, &rendered/3) == socket
    {socket, _token} = flush(socket)
    assert_received {:rendered, :live_preview_reload, %{}}
    assert socket.assigns.preview_update == nil
  end

  test "an edit during collection invalidates old replies and uses only the latest generation" do
    {socket, old_token} = socket() |> Preview.queue(:live_preview_update, 0) |> flush()
    socket = Preview.receive_blocks(socket, old_token, :blocks, [], &rendered/3)
    socket = Preview.queue(socket, :live_preview_full_rerender, 0)
    assert Preview.receive_blocks(socket, old_token, :sidebar, [], &rendered/3) == socket
    refute_received {:rendered, _, _}

    {socket, token} = flush(socket)
    cs = Ecto.Changeset.change(%Brando.Pages.Page.Blocks{sequence: 7})
    socket = Preview.receive_blocks(socket, token, :blocks, [{"latest", cs}], &rendered/3)
    Preview.receive_blocks(socket, token, :sidebar, [], &rendered/3)

    assert_received {:rendered, :live_preview_full_rerender, %{blocks: [latest]}}
    assert latest.data.sequence == 7
    refute_received {:rendered, _, _}
  end

  test "cancelled timers and collected replies cannot revive a closed preview" do
    {socket, token} = socket() |> Preview.queue(:live_preview_update, 0) |> flush()
    socket = socket |> Preview.cancel() |> Component.assign(:live_preview_active?, false)
    assert Preview.flush(socket, token, &rendered/3) == socket
    assert Preview.receive_blocks(socket, token, :blocks, [], &rendered/3) == socket
    assert Preview.queue(socket, :live_preview_reload, 0) == socket
    refute_received {:rendered, _, _}
  end
end
