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
  def localized(locale, fun, args), do: localized_path(locale, fun, args)

  def localized_path(locale, fun, args) do
    locale = to_string(locale)
    default_language = to_string(Brando.config(:default_language))
    helpers_module = Brando.helpers()

    # Determine which function to use based on locale and configuration
    function_name =
      if Brando.config(:scope_default_language_routes) == false && default_language == locale do
        # Default language without scoping - use regular path
        :"#{fun}"
      else
        # Either non-default language or scoped default language - use localized path
        :"#{locale}_#{fun}"
      end

    # Try to apply the function directly if it exists as a key in the helper module
    cond do
      # Check if the function exists in the module
      function_exists?(helpers_module, function_name) ->
        apply(helpers_module, function_name, args)

      # Fallback to the regular function if localized version doesn't exist
      function_name != :"#{fun}" && function_exists?(helpers_module, :"#{fun}") ->
        apply(helpers_module, :"#{fun}", args)

      # Cannot localize the URL
      true ->
        "/<url cannot be localized>"
    end
  end

  # Helper function to check if a function exists in a module
  defp function_exists?(module, function_name) do
    functions = module.__info__(:functions)
    Enum.any?(functions, fn {fun, _} -> fun == function_name end)
  end
end
