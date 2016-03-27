defmodule Brando.Utils.Model do
  @moduledoc """
  Common model utility functions
  """

  @doc """
  Updates a field on `model`.
  `coll` should be [field_name: value]

  ## Example:

      {:ok, model} = update_field(model, [field_name: "value"])

  """

  def update_field(model, coll) do
    changeset = Ecto.Changeset.change(model, coll)
    {:ok, Brando.repo.update!(changeset)}
  end

  @doc """
  Puts `id` from `user` in the `params` map.
  """
  def put_creator(params, user) do
    key = is_atom(List.first(Map.keys(params))) && :creator_id || "creator_id"
    Map.put(params, key, user.id)
  end
end
