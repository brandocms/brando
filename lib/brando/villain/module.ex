defmodule Brando.Villain.Module do
  @moduledoc """
  Ecto schema for the Villain Module schema

  A module can hold a setup for multiple blocks.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Pages",
    schema: "Module",
    singular: "module",
    plural: "modules",
    gettext_module: Brando.Gettext

  identifier "{{ entry.name }}"

  @derived_fields ~w(id name sequence namespace help_text multi wrapper class code refs vars svg deleted_at)a
  @derive {Jason.Encoder, only: @derived_fields}

  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped

  attributes do
    attribute :name, :string, required: true
    attribute :namespace, :string, required: true
    attribute :help_text, :text, required: true
    attribute :class, :string, required: true
    attribute :code, :text, required: true
    attribute :refs, {:array, :map}, required: true
    attribute :vars, :map
    attribute :svg, :text
    attribute :multi, :boolean
    attribute :wrapper, :text
  end
end
