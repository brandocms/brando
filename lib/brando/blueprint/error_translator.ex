defmodule Brando.Blueprint.ErrorTranslator do
  @moduledoc """
  Translates Blueprint changeset error keys using their configured form labels.

  This form-facing concern is isolated from the helpers imported while schemas
  compile, preventing admin form structures from becoming schema dependencies.
  """

  require Logger

  alias Brando.Blueprint.Forms

  @doc """
  Returns translated labels for `error_keys` in the Blueprint `form`.
  """
  @spec translate_keys([atom()], struct(), module()) :: [String.t()]
  def translate_keys(error_keys, form, schema) do
    gettext_module = schema.__modules__().gettext
    gettext_domain = String.downcase("#{schema.__naming__().domain}_#{schema.__naming__().schema}")

    Enum.map(error_keys, &translate_key(&1, form, gettext_module, gettext_domain))
  end

  defp translate_key(error_key, form, gettext_module, gettext_domain) do
    case Forms.get_field(error_key, form) do
      nil ->
        log_missing_field(error_key, form)
        String.capitalize(to_string(error_key))

      field ->
        Gettext.dgettext(gettext_module, gettext_domain, field_label(field, error_key))
    end
  end

  defp field_label(%{__struct__: Forms.Subform} = field, _error_key) do
    Map.get(field, :label) || String.capitalize(to_string(field.name))
  end

  defp field_label(field, error_key) do
    Keyword.get(field.opts, :label, String.capitalize(to_string(error_key)))
  end

  defp log_missing_field(error_key, form) do
    Logger.error("""
    (!) Could not get field `#{inspect(error_key)}` from form:

    #{inspect(form, pretty: true)}
    """)
  end
end
