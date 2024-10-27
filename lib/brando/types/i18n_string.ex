defmodule Brando.Type.I18nString do
  @moduledoc """
  Defines a type for casting to i18n string stored as a jsonb field.
  The field contains a map of locales as keys and translated strings as values.
  It automatically returns the string in the current Gettext locale when loaded.
  """
  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(string) when is_binary(string) do
    {:ok, %{"en" => string}}
  end

  def cast(map) when is_map(map) do
    {:ok, map}
  end

  def cast(_), do: :error

  @impl true
  def load(map) when is_map(map) do
    {:ok, map}
  end

  def load(nil), do: {:ok, nil}

  @impl true
  def dump(string) when is_binary(string) do
    {:ok, %{"en" => string}}
  end

  def dump(nil), do: {:ok, nil}

  def dump(map) when is_map(map) do
    # Go through map values and set to nil if empty string
    map =
      map
      |> Enum.map(fn {key, value} -> {key, if(value == "", do: nil, else: value)} end)
      |> Enum.into(%{})

    # Check if all map values are empty strings
    if Enum.all?(map, fn {_key, value} -> is_nil(value) end) do
      {:ok, nil}
    else
      {:ok, map}
    end
  end

  def dump(_), do: :error
end
