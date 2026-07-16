defmodule Brando.I18n.Helpers do
  @moduledoc """
  A helper for localizing path helpers.

  ## Usage:

      import Brando.I18n.Helpers


  You can then call

      <a href={localized_path(@language, :page_path, [@conn, :about])}>{gettext("About")}</a>

  """
  alias Brando.RuntimeConfig

  @doc false
  defmacro __using__(_) do
    raise "using Brando.I18n.Helpers is deprecated. `import Brando.I18n.Helpers` instead"
  end

  @doc "Deprecated alias for `localized_path/3`."
  @deprecated "Use `localized_path/3` instead"
  def localized(locale, fun, args), do: localized_path(locale, fun, args)

  @doc """
  Calls the localized router helper for `locale`, falling back to the unscoped
  helper when the localized route is unavailable.

  Returns `"/<url cannot be localized>"` when neither helper exists with the
  requested arity.
  """
  def localized_path(locale, fun, args) do
    locale = to_string(locale)
    default_language = to_string(RuntimeConfig.get(:default_language))
    helpers_module = RuntimeConfig.router_helpers()

    function_name =
      if RuntimeConfig.get(:scope_default_language_routes) == false && default_language == locale do
        :"#{fun}"
      else
        :"#{locale}_#{fun}"
      end

    arity = length(args)

    cond do
      function_exported?(helpers_module, function_name, arity) ->
        apply(helpers_module, function_name, args)

      function_name != :"#{fun}" && function_exported?(helpers_module, :"#{fun}", arity) ->
        apply(helpers_module, :"#{fun}", args)

      true ->
        "/<url cannot be localized>"
    end
  end
end
