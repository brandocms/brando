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

      def localized_path(locale, fun, args),
        do: apply(Brando.helpers(), :"#{locale}_#{fun}", args)
    end
  end
end
