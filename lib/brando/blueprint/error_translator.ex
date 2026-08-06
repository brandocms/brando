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

  Configured string labels are translated through the schema's Gettext domain.
  Hidden, blank, or non-string labels fall back to the humanized form field
  name. This also keeps foreign-key errors tied to their visible relation or
  asset input instead of exposing the generated `_id` field.
  """
  @spec translate_keys([atom() | String.t()], struct(), module()) :: [String.t()]
  def translate_keys(error_keys, form, schema) do
    gettext_module = schema.__modules__().gettext
    gettext_domain = String.downcase("#{schema.__naming__().domain}_#{schema.__naming__().schema}")

    Enum.map(error_keys, &translate_key(&1, form, gettext_module, gettext_domain))
  end

  defp translate_key(error_key, form, gettext_module, gettext_domain) do
    case Forms.get_field(error_key, form) do
      nil ->
        log_missing_field(error_key, form)
        humanize(error_key)

      field ->
        Gettext.dgettext(gettext_module, gettext_domain, field_label(field, error_key))
    end
  end

  defp field_label(%{__struct__: Forms.Subform} = field, _error_key) do
    normalize_label(Map.get(field, :label), field.name)
  end

  defp field_label(field, _error_key) do
    label = Keyword.get(field.opts || [], :label)
    normalize_label(label, field.name)
  end

  defp normalize_label(label, field_name) when is_binary(label) do
    if String.trim(label) == "", do: humanize(field_name), else: label
  end

  defp normalize_label(_label, field_name), do: humanize(field_name)

  defp humanize(field), do: field |> to_string() |> Phoenix.Naming.humanize()

  # Names the form and the fields it does have, rather than inspecting the whole
  # struct. A `Forms.Form` is tabs → fieldsets → inputs deep and runs to well
  # over a hundred lines pretty-printed, which buried the one line that matters
  # and flooded the test suite's stdout every time an error key had no input.
  # The field list is the thing you actually compare the missing key against.
  defp log_missing_field(error_key, %Forms.Form{name: name} = form) do
    Logger.error(
      "(!) Could not get field #{inspect(error_key)} from form #{inspect(name)}. " <>
        "Fields in this form: #{inspect(Forms.list_fields(form))}"
    )
  end
end
