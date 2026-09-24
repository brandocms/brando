defmodule Brando.Type.I18nString do
  @moduledoc """
  Text in several languages, stored as a jsonb map of language → text.

  Loading returns the map. Read one language with `get/2`, which falls back
  to the default content language. A plain string — older data, a transfer
  bundle, a form that sent one value — is cast under the default content
  language.
  """
  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(string) when is_binary(string) do
    {:ok, %{default_language() => string}}
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
  def load(string) when is_binary(string), do: {:ok, %{default_language() => string}}

  @impl true
  def dump(string) when is_binary(string) do
    {:ok, %{default_language() => string}}
  end

  def dump(nil), do: {:ok, nil}

  def dump(map) when is_map(map) do
    # Go through map values and set to nil if empty string
    map =
      Map.new(map, fn {key, value} -> {key, if(value == "", do: nil, else: value)} end)

    # Check if all map values are empty strings
    if Enum.all?(map, fn {_key, value} -> is_nil(value) end) do
      {:ok, nil}
    else
      {:ok, map}
    end
  end

  def dump(_), do: :error

  @doc """
  The text for `language`: that language's, else the default content
  language's, else `nil`. Blank text counts as none. A plain string is
  returned as it is, so values that were never translated still read.
  """
  @spec get(map() | String.t() | nil, String.t() | atom() | nil) :: String.t() | nil
  def get(nil, _language), do: nil
  def get(value, _language) when is_binary(value), do: present(value)

  def get(map, language) when is_map(map) do
    present(language && Map.get(map, to_string(language))) || present(Map.get(map, default_language()))
  end

  def get(_value, _language), do: nil

  defp default_language, do: to_string(Brando.config(:default_language) || "en")

  defp present(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp present(_), do: nil
end
