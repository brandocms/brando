defmodule Brando.HTML.I18n do
  @moduledoc """
  Lightweight rendering for translated string maps.

  Resolution uses the current Gettext locale, then Brando's configured default
  language, and finally English.
  """

  use Phoenix.Component

  alias Brando.RuntimeConfig

  attr :map, :any, required: true

  @doc "Renders the best available translation from `map`."
  def i18n(%{map: nil} = assigns) do
    ~H"""
    """
  end

  def i18n(assigns) do
    current_locale = Gettext.get_locale()
    fallback_locale = RuntimeConfig.get(:default_language)

    translated_string = assigns.map[current_locale] || assigns.map[fallback_locale] || ""

    translated_string =
      if translated_string == "" do
        assigns.map["en"] || ""
      else
        translated_string
      end

    assigns = assign(assigns, :translated_string, translated_string)

    ~H"""
    {@translated_string}
    """
  end
end
