defmodule Brando.HTML.I18n do
  @moduledoc """
  Lightweight rendering for translated string maps.

  Resolution uses the current Gettext locale, then the default language
  (`Brando.Languages.default_language/0`, the site's in multi-site mode), and
  finally English.
  """

  use Phoenix.Component

  attr :map, :any, required: true

  @doc "Renders the best available translation from `map`."
  def i18n(%{map: nil} = assigns) do
    ~H"""
    """
  end

  def i18n(assigns) do
    assigns = assign(assigns, :translated_string, translate(assigns.map))

    ~H"""
    {@translated_string}
    """
  end

  @doc "The best available translation from `map`, as `i18n/1` renders it."
  def translate(nil), do: ""

  def translate(map) do
    case map[Gettext.get_locale()] || map[Brando.Languages.default_language()] || "" do
      "" -> map["en"] || ""
      translated -> translated
    end
  end
end
