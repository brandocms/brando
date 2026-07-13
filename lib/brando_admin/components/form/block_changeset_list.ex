defmodule BrandoAdmin.Components.Form.BlockChangesetList do
  @moduledoc """
  Helpers for managing `[{uid, changeset | nil}]` lists used by
  `BlockField` (root changesets) and `Block` (child changesets).
  """

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
end
