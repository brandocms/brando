defmodule Brando.Upload.Utils do
  @moduledoc """
  Helper functions for ImageField and FileField
  """
  import Ecto.Changeset
  @doc """
  Checks changeset if `field_name` is changed.
  Returns :unchanged, or {:ok, change}
  """
  @spec field_has_changed(Ecto.Changeset.t, atom) :: {:ok, Ecto.Changeset.t} | :unchanged
  def field_has_changed(changeset, field_name) do
    case get_change(changeset, field_name) do
      nil    -> :unchanged
      change -> {:ok, change}
    end
  end

  @doc """
  Checks changeset for errors.
  No need to process upload if there are other errors.
  """
  @spec changeset_has_no_errors(Ecto.Changeset.t) :: {:ok, Ecto.Changeset.t} | :has_errors
  def changeset_has_no_errors(changeset) do
    case changeset.errors do
      [] -> {:ok, changeset}
      _  -> :has_errors
    end
  end
end
