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
end