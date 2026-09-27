defmodule BrandoAdmin.Components.Form.Preview do
  @moduledoc "Coalesces preview requests without using the save/share collection state."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [send_update: 2, send_update_after: 3]

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.BlockField

  @coalesce_ms 25
  @priority %{live_preview_update: 0, live_preview_full_rerender: 1, live_preview_reload: 2}

  def queue(%{assigns: %{live_preview_active?: false}} = socket, _mode, _delay), do: socket

  def queue(socket, mode, delay) do
    pending = socket.assigns[:preview_update]
    deadline = System.monotonic_time(:millisecond) + max(delay, @coalesce_ms)
    mode = if pending, do: strongest(pending.mode, mode), else: mode

    if pending && is_nil(pending.parts) && pending.deadline <= deadline do
      assign(socket, :preview_update, %{pending | mode: mode})
    else
      socket = cancel(socket)
      token = make_ref()

      timer =
        send_update_after(
          Form,
          [id: socket.assigns.id, event: "flush_live_preview", token: token],
          max(delay, @coalesce_ms)
        )

      assign(socket, :preview_update, %{token: token, timer: timer, deadline: deadline, mode: mode, parts: nil})
    end
  end

  def cancel(socket) do
    if pending = socket.assigns[:preview_update] do
      if pending.timer, do: Process.cancel_timer(pending.timer)
    end

    assign(socket, :preview_update, nil)
  end

  def flush(
        %{assigns: %{live_preview_active?: true, preview_update: %{token: token, parts: nil} = pending}} = socket,
        token,
        render
      ) do
    parts = Map.new(socket.assigns.block_map, fn {field, _, _, _} -> {field, nil} end)
    socket = assign(socket, :preview_update, %{pending | timer: nil, parts: parts})

    for {field, _} <- parts do
      send_update(BlockField,
        id: "#{socket.assigns.id}-blocks-#{field}",
        event: "fetch_root_blocks",
        tag: {:preview_update, token}
      )
    end

    maybe_render(socket, render)
  end

  def flush(socket, _token, _render), do: socket

  def receive_blocks(
        %{assigns: %{live_preview_active?: true, preview_update: %{token: token, parts: parts} = pending}} = socket,
        token,
        field,
        roots,
        render
      )
      when is_map(parts) and is_map_key(parts, field) do
    changesets = for {_uid, cs} <- roots, not is_nil(cs), do: Brando.Utils.set_action(cs)

    socket
    |> assign(:preview_update, %{pending | parts: Map.put(parts, field, changesets)})
    |> maybe_render(render)
  end

  def receive_blocks(socket, _token, _field, _roots, _render), do: socket

  defp maybe_render(socket, render) do
    pending = socket.assigns.preview_update

    if Enum.any?(pending.parts, fn {_, part} -> is_nil(part) end) do
      socket
    else
      socket |> assign(:preview_update, nil) |> render.(pending.mode, pending.parts)
    end
  end

  defp strongest(left, right) do
    if Map.fetch!(@priority, left) >= Map.fetch!(@priority, right), do: left, else: right
  end
end
