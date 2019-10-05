defmodule Brando.Gallery.Migration do
  @moduledoc """
  Macro for adding field to migration.
  """

  @doc """
  Add soft delete field to migration
  """
  defmacro gallery(field \\ :image_series) do
    field =
      field
      |> to_string
      |> Kernel.<>("_id")
      |> String.to_atom()

    quote do
      add unquote(field), references(:images_series, on_delete: :delete_all)
    end
  end
end
