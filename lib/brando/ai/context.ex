defmodule Brando.AI.Context do
  @moduledoc """
  Resolves the entry text an AI prompt is given as context.

  A blueprint declares what an AI action reads through the `:context` option on
  the field — `trait :meta, ai: [meta_description: [context: [:title, :blocks]]]`.
  This module resolves that declaration against an entry: plain attributes are
  formatted as text, and block fields are read from the persisted
  `rendered_<field>` column instead of re-rendering the block tree.

  The admin form keeps its own path for `:blocks`, because there the unsaved
  editor state is what should be summarized. Everything else — and everything
  outside a form, like generating a meta description from the Content SEO tab —
  comes through here.
  """

  alias Brando.Blueprint.Value

  @block_text_length 2000

  @doc """
  Reads `fields` off a persisted `entry`, returning `{field, text}` in the order
  asked for. Fields that are empty, missing, or unreadable are left out.

  `:blocks` means every block field the schema has; a block field's own name
  means just that one. Both read `rendered_<field>`, so an entry saved before
  its blocks were last rendered reports what the site currently serves.

  ## Options

    * `:length` — characters of block text per field. Defaults to `2000`.
  """
  @spec for_entry(map() | nil, [atom()] | atom() | nil, keyword()) :: [{atom(), String.t()}]
  def for_entry(entry, fields, opts \\ [])
  def for_entry(nil, _fields, _opts), do: []

  def for_entry(entry, fields, opts) do
    fields = normalize_fields(fields)
    block_fields = entry |> schema() |> block_fields()

    Enum.flat_map(fields, fn field ->
      field
      |> value(entry, block_fields, opts)
      |> case do
        value when value in [nil, ""] -> []
        value -> [{field, value}]
      end
    end)
  end

  @doc """
  Every block field of `entry` as one run of plain text.

  ## Options

    * `:length` — characters per block field. Defaults to `2000`.
  """
  @spec block_text(map() | nil, keyword()) :: String.t() | nil
  def block_text(entry, opts \\ [])
  def block_text(nil, _opts), do: nil

  def block_text(entry, opts) do
    entry
    |> schema()
    |> block_fields()
    |> Enum.map(&rendered_text(entry, &1, opts))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
    |> case do
      "" -> nil
      text -> text
    end
  end

  @doc "The block field names declared on `schema`."
  @spec block_fields(module() | nil) :: [atom()]
  def block_fields(nil), do: []

  def block_fields(schema) do
    schema
    |> Brando.Blueprint.Relations.__relations__()
    |> Enum.filter(&match?(%{type: :has_many, opts: %{module: :blocks}}, &1))
    |> Enum.map(& &1.name)
  rescue
    _ -> []
  end

  @doc """
  The fields of `schema` worth offering as prompt context: the text the
  blueprint's own form asks an editor to write, plus its block fields.

  Meta fields are left out — they are what a generated description competes
  with, not what describes the entry — as are the fields that carry markup or
  routing rather than prose. A translatable schema also offers `:language`,
  which the shipped prompts read to decide what language to answer in.
  """
  @spec available_fields(module()) :: [atom()]
  def available_fields(schema) do
    columns = schema.__schema__(:fields)

    text_fields =
      schema
      |> Brando.AI.Translation.translatable_text_fields()
      |> Enum.filter(&(&1 in columns))
      |> Enum.reject(&skip_field?/1)

    text_fields ++ block_fields(schema) ++ language_field(schema)
  rescue
    _ -> []
  end

  defp language_field(schema) do
    if schema.has_trait(Brando.Trait.Translatable), do: [:language], else: []
  end

  @doc """
  Normalizes a `:context` declaration into a list of field atoms.

  Strings are accepted so a stored picker selection can be passed straight in;
  a string naming no existing atom is dropped rather than creating one.
  """
  @spec normalize_fields(term()) :: [atom()]
  def normalize_fields(nil), do: []

  def normalize_fields(fields) when is_list(fields) do
    fields
    |> Enum.map(&normalize_field/1)
    |> Enum.reject(&is_nil/1)
  end

  def normalize_fields(field), do: field |> List.wrap() |> normalize_fields()

  @doc """
  Appends a `Context:` block to `prompt`.

  Returns `prompt` unchanged when there is no context to add, so a prompt that
  reads well on its own is not given a dangling heading.
  """
  @spec build_prompt(String.t(), [{atom(), String.t()}]) :: String.t()
  def build_prompt(prompt, context_values) do
    context_values
    |> Enum.map(fn {field, value} -> "#{field}: #{value}" end)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> prompt
      lines -> IO.iodata_to_binary([prompt, "\n\nContext:\n", Enum.join(lines, "\n")])
    end
  end

  @doc "Formats one attribute value as the plain text a prompt can read."
  @spec format_value(term()) :: String.t() | nil
  def format_value(nil), do: nil

  def format_value(value) when is_binary(value),
    do: value |> HtmlSanitizeEx.strip_tags() |> String.trim()

  def format_value(value) when is_integer(value), do: Integer.to_string(value)
  def format_value(value) when is_float(value), do: to_string(value)
  def format_value(value) when is_boolean(value), do: to_string(value)

  def format_value(value) when is_list(value) do
    value
    |> Enum.map(&format_value/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  def format_value(value) when is_map(value), do: inspect(value, pretty: false, limit: :infinity)
  def format_value(value), do: to_string(value)

  defp value(:blocks, entry, block_fields, opts) do
    if :blocks in block_fields do
      rendered_text(entry, :blocks, opts)
    else
      block_text(entry, opts)
    end
  end

  defp value(field, entry, block_fields, opts) do
    if field in block_fields do
      rendered_text(entry, field, opts)
    else
      entry |> Map.get(field) |> format_value()
    end
  end

  defp rendered_text(entry, field, opts) do
    Value.rendered_text(entry, field: field, length: Keyword.get(opts, :length, @block_text_length))
  end

  defp schema(%{__struct__: schema}), do: schema
  defp schema(_), do: nil

  defp skip_field?(field) do
    field in [:slug, :uri, :key, :language, :css_classes, :meta_title, :meta_description]
  end

  defp normalize_field(field) when is_atom(field), do: field

  defp normalize_field(field) when is_binary(field) do
    String.to_existing_atom(field)
  rescue
    ArgumentError -> nil
  end

  defp normalize_field(_), do: nil
end
