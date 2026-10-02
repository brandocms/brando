defmodule Brando.Forms.Field do
  @moduledoc """
  One field of a `Brando.Forms.Form`, in the order editors arranged them.

  A field is laid out like a block variable: `width` claims units of a
  12-unit row and `new_row` starts a new one (see `Brando.Content.Var.Layout`).
  A `:section` field is not an input — it starts a new group of fields, with
  `label` as its heading and `help_text` as its description.

  ## Options

  `:select`, `:radio` and `:checkboxes` fields offer `option_values`, the
  values a submission stores, labelled per language by `option_labels`
  (value → label). A synchronized translation takes the values from its
  source and keeps its own labels, so every language submits the same values.

  The admin posts options as `option_rows` (`%{"0" => %{"value" => …,
  "label" => …}}`) with an `option_rows_present` marker, so an emptied list
  still arrives; `Brando.Forms.Field.Normalize` turns them into the two
  fields.
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Forms",
    schema: "Field",
    singular: "field",
    plural: "fields",
    gettext_module: Brando.Gettext

  @types [
    :text,
    :email,
    :tel,
    :textarea,
    :number,
    :date,
    :select,
    :radio,
    :checkboxes,
    :checkbox,
    :consent,
    :hidden,
    :section
  ]

  @option_types [:select, :radio, :checkboxes]

  trait Brando.Trait.EnsureUID
  trait Brando.Trait.Sequenced
  trait Brando.Forms.Field.Normalize

  identifier false
  persist_identifier false

  attributes do
    attribute :uid, :string
    attribute :key, :string, required: true
    attribute :type, :enum, values: @types, required: true
    attribute :label, :text
    attribute :placeholder, :text
    attribute :help_text, :text
    attribute :default_value, :text
    attribute :required, :boolean, default: false
    attribute :width, :enum, values: [:full, :half, :third, :fourth], default: :full
    attribute :new_row, :boolean, default: false
    attribute :option_values, {:array, :string}, default: []
    attribute :option_labels, :map, default: %{}
  end

  relations do
    relation :form, :belongs_to, module: Brando.Forms.Form
  end

  @doc "Every field type."
  def types, do: @types

  @doc "The field types that offer options."
  def option_types, do: @option_types

  @doc "Whether a field of `type` offers options."
  def options?(%{type: type}), do: options?(type)
  def options?(type), do: type in @option_types

  @doc "Whether a field of `type` is an input a visitor fills in."
  def input?(%{type: type}), do: input?(type)
  def input?(type), do: type not in [:section, :hidden]

  @doc "The field's options as `{value, label}`, labels falling back to the value."
  def options(%{option_values: values, option_labels: labels}) do
    labels = labels || %{}
    Enum.map(values || [], &{&1, blank_to_nil(Map.get(labels, &1)) || &1})
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
