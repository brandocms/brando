defmodule BrandoAdmin.Components.Form.Preview do
  @moduledoc "Coalesces preview requests without using the save/share collection state."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [send_update: 2, send_update_after: 3]

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.BlockField

  @coalesce_ms 25
  # A full render re-sends the whole document and morphs it into the iframe.
  # Entry-field validates arrive one per typing pause, so without a floor every
  # pause paid for one. The first request after a quiet spell still renders
  # within the coalescing window; later ones wait for this much time since the
  # previous render and then render the latest state once.
  @min_interval_ms 1000
  @priority %{live_preview_update: 0, live_preview_full_rerender: 1, live_preview_reload: 2}

  def queue(%{assigns: %{live_preview_active?: false}} = socket, _mode, _delay), do: socket

  def queue(socket, mode, delay) do
    pending = socket.assigns[:preview_update]
    now = System.monotonic_time(:millisecond)
    wait = Enum.max([delay, @coalesce_ms, interval_left(socket, now)])
    deadline = now + wait
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
          wait
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

  # A heavy entry's blocks are still loading (a preview recovered after a
  # reconnect, Refresh): the request waits for them, see `resume/1`.
  def flush(
        %{assigns: %{blocks_ready?: false, preview_update: %{token: token, parts: nil} = pending}} = socket,
        token,
        _
      ),
      do: assign(socket, :preview_update, %{pending | timer: nil})

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

  @doc "Sends a request that waited for the blocks (`flush/3`), now they are there."
  def resume(%{assigns: %{preview_update: %{token: token, timer: nil, parts: nil}}} = socket) do
    send_update(Form, id: socket.assigns.id, event: "flush_live_preview", token: token)
    socket
  end

  def resume(socket), do: socket

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
      socket
      |> assign(:preview_update, nil)
      |> render.(pending.mode, pending.parts)
      |> assign(:preview_rendered_at, System.monotonic_time(:millisecond))
    end
  end

  defp interval_left(%{assigns: %{preview_rendered_at: at}}, now) when is_integer(at), do: at + @min_interval_ms - now
  defp interval_left(_socket, _now), do: 0

  defp strongest(left, right) do
    if Map.fetch!(@priority, left) >= Map.fetch!(@priority, right), do: left, else: right
  end
end
