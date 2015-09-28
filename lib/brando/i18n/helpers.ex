defmodule Brando.I18n.Helpers do
  @moduledoc """
  A helper for localizing path helpers.

  ## Usage:

      use Brando.I18n.Helpers, helpers: MyApp.Router.Helpers

  """
  defmacro __using__(opts) do
    helpers = Keyword.fetch!(opts, :helpers)
    quote do
      def localized(language, fun, args) do
        apply(unquote(helpers), :"#{language}_#{fun}", args)
      end
    end
  end
end
