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
    {:ok, %{Gettext.get_locale() => string}}
  end

  def cast(map) when is_map(map) do
    {:ok, map}
  end

  def cast(_), do: :error

  @impl true
  def load(data) when is_map(data) do
    current_locale = Gettext.get_locale()
    fallback_locale = Brando.config(:default_language)

    translated_string = data[current_locale] || data[fallback_locale] || ""
    {:ok, translated_string}
  end

  @impl true
  def dump(string) when is_binary(string) do
    {:ok, %{Gettext.get_locale() => string}}
  end

  def dump(map) when is_map(map) do
    {:ok, map}
  end

  def dump(_), do: :error
end
