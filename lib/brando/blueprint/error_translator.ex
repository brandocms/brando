defmodule Brando.Blueprint.ErrorTranslator do
  @moduledoc """
  Translates Blueprint changeset error keys using their configured form labels.

  This form-facing concern is isolated from the helpers imported while schemas
  compile, preventing admin form structures from becoming schema dependencies.
  """

  require Logger

  alias Brando.Blueprint.Forms
  alias Brando.Content.Transfer.Labels
  alias Ecto.Changeset

  @doc """
  Returns translated labels for `error_keys` in the Blueprint `form`.

  Configured string labels are translated through the schema's Gettext domain.
  Hidden, blank, or non-string labels fall back to the humanized form field
  name. This also keeps foreign-key errors tied to their visible relation or
  asset input instead of exposing the generated `_id` field.
  """
  @spec translate_keys([atom() | String.t()], struct(), module()) :: [String.t()]
  def translate_keys(error_keys, form, schema) do
    Enum.map(error_keys, &translate_key(&1, form, schema, fn key -> log_missing_field(key, form) end))
  end

  @doc """
  The fields of `changeset` that carry errors, at any depth: an error in a
  nested changeset (an embed or a relation) is under the field that holds
  it. The changeset's own errors come first, in their order.
  """
  @spec error_fields(Changeset.t()) :: [atom()]
  def error_fields(%Changeset{errors: errors} = changeset) do
    nested = changeset |> Changeset.traverse_errors(& &1) |> Map.keys() |> Enum.sort()
    Enum.uniq(Keyword.keys(errors) ++ nested)
  end

  @doc """
  Describes the errors of a Blueprint `changeset` as `{label, message}`
  pairs, in `error_fields/1`'s order: each field under its label in `form`,
  with its messages, each translated by `translate` (given `{message, opts}`),
  joined. An error in a nested changeset is under the path to it, each step
  under the label the nested schema's form gives it, as "Page variables →
  Label"; an item of a list of several is numbered by its place in the list,
  as "Page variables 2 → Label".

  A field `form` has no input for, any field when `form` is nil, and any field
  of a changeset that is not a Blueprint's (a job, an identifier) goes by its
  humanized name. Unlike `translate_keys/3` this is not logged: the changeset
  is from a save the form did not make (a revision, an import).
  """
  @spec describe(Changeset.t(), struct() | nil, ({String.t(), keyword()} -> String.t())) :: [{String.t(), String.t()}]
  def describe(%Changeset{} = changeset, form, translate) do
    schema = schema_of(changeset)

    changeset
    |> error_fields()
    |> Enum.flat_map(&field_entries(changeset, &1, label(&1, form, schema), translate))
    |> Enum.uniq()
  end

  defp label(field, form, schema) do
    if form && blueprint?(schema),
      do: translate_key(field, form, schema, fn _key -> :ok end),
      else: humanize(field)
  end

  # A field's own messages, then those of the nested changesets under it
  defp field_entries(%Changeset{errors: errors, changes: changes}, field, path, translate) do
    own =
      case for({^field, error} <- errors, do: translate.(error)) do
        [] -> []
        messages -> [{path, Enum.join(messages, ", ")}]
      end

    own ++ nested_entries(Map.get(changes, field), path, translate)
  end

  defp nested_entries(%Changeset{} = nested, path, translate), do: changeset_entries(nested, path, translate)

  # Rows being removed (`:replace`) are not in the form: an item's number is
  # its place among the others
  defp nested_entries(list, path, translate) when is_list(list) do
    items = Enum.filter(list, &match?(%Changeset{action: action} when action not in [:replace, :delete], &1))
    numbered? = length(items) > 1

    items
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {item, n} ->
      changeset_entries(item, if(numbered?, do: "#{path} #{n}", else: path), translate)
    end)
  end

  defp nested_entries(_value, _path, _translate), do: []

  defp changeset_entries(changeset, path, translate) do
    schema = schema_of(changeset)

    changeset
    |> error_fields()
    |> Enum.flat_map(&field_entries(changeset, &1, "#{path} → #{nested_label(schema, &1)}", translate))
  end

  # A nested field under its label in its own schema's form, in the admin's
  # language, else the general label for its name
  defp nested_label(nil, field), do: Labels.field(field)
  defp nested_label(schema, field), do: Labels.field(schema, field)

  defp schema_of(%Changeset{data: %schema{}}), do: schema
  defp schema_of(_changeset), do: nil

  # Only a Blueprint's changeset is labelled from the form: a changeset from
  # inside a save that is not the entry's has no naming to translate with
  defp blueprint?(nil), do: false

  defp blueprint?(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :__naming__, 0) and
      function_exported?(schema, :__modules__, 0)
  end

  # The meta drawer (`Brando.Trait.Meta`) edits these outside the Blueprint
  # form, under these labels in Brando's own catalog.
  @meta_drawer_labels %{
    "meta_title" => "Meta title",
    "meta_description" => "Meta description",
    "meta_canonical_url" => "Canonical URL",
    "meta_nosnippet" => "No snippet",
    "meta_max_snippet" => "Snippet length",
    "meta_image" => "Meta image",
    "meta_image_id" => "Meta image"
  }

  defp translate_key(error_key, form, schema, on_missing) do
    case {Forms.get_field(error_key, form), Map.get(@meta_drawer_labels, to_string(error_key))} do
      {nil, nil} ->
        on_missing.(error_key)
        humanize(error_key)

      {nil, meta_label} ->
        Gettext.dgettext(Brando.Gettext, "default", meta_label)

      {field, _} ->
        gettext_domain = String.downcase("#{schema.__naming__().domain}_#{schema.__naming__().schema}")
        Gettext.dgettext(schema.__modules__().gettext, gettext_domain, field_label(field, error_key))
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
