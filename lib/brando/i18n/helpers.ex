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
    locale = (is_binary(locale) && locale) || to_string(locale)

    default_language =
      (is_binary(Brando.config(:default_language)) && Brando.config(:default_language)) ||
        to_string(Brando.config(:default_language))

    if Brando.config(:scope_default_language_routes) == false && default_language == locale do
      # if the locale is the default language, we use the regular path
      apply(Brando.helpers(), :"#{fun}", args)
    else
      localized_fun = :"#{locale}_#{fun}"

      if Brando.helpers().__info__(:functions) |> Keyword.has_key?(localized_fun) do
        apply(Brando.helpers(), localized_fun, args)
      else
        # fallback to regular function (mostly used for page_path)
        apply(Brando.helpers(), :"#{fun}", args)
      end
    end
  end
end
