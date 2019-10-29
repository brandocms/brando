defmodule Brando.I18n.Helpers do
  @moduledoc """
  A helper for localizing path helpers.

  ## Usage:

      use Brando.I18n.Helpers, helpers: MyApp.Router.Helpers


  You can then call

      <a href="<%= localized(@language, :page_path, [@conn, :about]) %>"><%= gettext("About") %>

  """
  defmacro __using__(opts) do
    helpers = Keyword.fetch!(opts, :helpers)

    quote do
      def localized(locale, fun, args) do
        apply(unquote(helpers), :"#{locale}_#{fun}", args)
      end
    end
  end
end
