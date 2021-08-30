defmodule Brando.Villain.Module.Var do
  @moduledoc """
  Ecto schema for a module ref
  """
  alias Brando.Blueprint.Villain.Blocks

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Villain",
    schema: "Var",
    singular: "var",
    plural: "vars",
    gettext_module: Brando.Gettext

  @primary_key false
  data_layer :embedded
  identifier "{{ entry.name }}"

  attributes do
    attribute :name, :text, required: true
    attribute :value, :text, required: true
    attribute :label, :text, required: true
    attribute :type, :enum, values: [:boolean, :color, :text, :string], required: true
    attribute :important, :boolean, default: false
  end
end
