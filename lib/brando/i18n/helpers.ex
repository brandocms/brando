defmodule Brando.I18n.Helpers do
  @moduledoc """
  A helper for localizing path helpers.

  ## Usage:

      use Brando.I18n.Helpers


  You can then call

      <a href="<%= localized_path(@language, :page_path, [@conn, :about]) %>"><%= gettext("About") %></a>

  """
  defmacro __using__(_) do
    quote do
      @deprecated "Use `localized_path/3` instead"
      def localized(locale, fun, args),
        do: localized_path(locale, fun, args)

      if Brando.config(:scope_default_language_routes) do
        # if the locale is the default language, we use the regular path
        def localized_path(locale, fun, args) when locale == Brando.config(:default_language) do
          apply(Brando.helpers(), :"#{fun}", args)
        end
      end

      def localized_path(locale, fun, args) do
        apply(Brando.helpers(), :"#{locale}_#{fun}", args)
      end
    end
  end
end
