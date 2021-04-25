defmodule Brando.I18n.Helpers do
  @moduledoc """
  A helper for localizing path helpers.

  ## Usage:

      import Brando.I18n.Helpers


  You can then call

      <a href="<%= localized_path(@language, :page_path, [@conn, :about]) %>"><%= gettext("About") %></a>

  """
  defmacro __using__(_) do
    raise "using Brando.I18n.Helpers is deprecated. `import Brando.I18n.Helpers` instead"
  end

  @deprecated "Use `localized_path/3` instead"
  def localized(locale, fun, args),
    do: localized_path(locale, fun, args)

  def localized_path(locale, fun, args) do
    if Brando.config(:scope_default_language_routes) && Brando.config(:default_language) == locale do
      # if the locale is the default language, we use the regular path
      apply(Brando.helpers(), :"#{fun}", args)
    else
      apply(Brando.helpers(), :"#{locale}_#{fun}", args)
    end
  end
end
