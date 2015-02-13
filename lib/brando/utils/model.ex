defmodule Brando.Utils.Model do
  @moduledoc """
  Common model utility functions
  """

  @doc """
  Checkbox values from forms come with value => "on". This transforms
  them into bool values if params[key] is in keys.

  # Example:

      transform_checkbox_vals(params, ~w(administrator editor))

  """
  def transform_checkbox_vals(params, keys) do
    Enum.into(Enum.map(params, fn({k, v}) ->
      case k in keys and v == "on" do
        true  -> {k, true}
        false -> {k, v}
      end
    end), %{})
  end

  @doc """
  Updates a field on `model`.
  `coll` should be [field_name: value]

  ## Example:

      {:ok, model} = update_field(model, [field_name: "value"])

  """
  def update_field(model, coll) do
    changeset = Ecto.Changeset.change(model, coll)
    {:ok, Brando.get_repo.update(changeset)}
  end
end