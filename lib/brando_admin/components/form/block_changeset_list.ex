defmodule BrandoAdmin.Components.Form.BlockChangesetList do
  @moduledoc """
  Helpers for managing `[{uid, changeset | nil}]` lists used by
  `BlockField` (root changesets) and `Block` (child changesets).
  """

  import Phoenix.Component, only: [assign: 3]

  @doc """
  Updates the changeset for the given `uid` in the list.
  """
  def update_changeset(changesets, uid, new_changeset) do
    Enum.map(changesets, fn
      {^uid, _changeset} -> {uid, new_changeset}
      other -> other
    end)
  end

  @doc """
  Inserts a new `{uid, nil}` entry at `position`.
  """
  def insert_changeset(changesets, uid, position) do
    List.insert_at(changesets, position, {uid, nil})
  end

  @doc """
  Removes the entry for the given `uid` from the list.
  """
  def delete_changeset(changesets, uid) do
    Enum.reject(changesets, fn
      {^uid, _} -> true
      _ -> false
    end)
  end

  @doc """
  Resets the position response tracker based on the current block list.
  """
  def reset_position_response_tracker(socket) do
    block_list = socket.assigns.block_list
    assign(socket, :position_response_tracker, Enum.map(block_list, &{&1, false}))
  end

  @doc """
  Marks `uid` as responded in the position tracker. When all have responded,
  triggers a live preview update.
  """
  def handle_position_response(socket, uid) do
    form_id = socket.assigns.form_id

    position_response_tracker =
      Enum.map(socket.assigns.position_response_tracker, fn
        {^uid, _} -> {uid, true}
        item -> item
      end)

    unless Enum.any?(position_response_tracker, &(elem(&1, 1) == false)) do
      Phoenix.LiveView.send_update(BrandoAdmin.Components.Form, id: form_id, event: "update_live_preview")
    end

    {:ok, assign(socket, :position_response_tracker, position_response_tracker)}
  end
end
