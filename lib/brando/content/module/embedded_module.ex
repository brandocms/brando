defmodule Brando.Content.Module.EmbeddedModule do
  @moduledoc """
  An embedded version of a module. Used as module template for multi modules.
  We need this to set a binary_id as id
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "EmbeddedModule",
    singular: "embedded_module",
    plural: "embedded_modules",
    gettext_module: Brando.Gettext

  import Brando.Gettext
  alias Brando.Content.Var
  alias Brando.Content.Module

  data_layer :embedded
  primary_key :uuid

  identifier "{{ entry.name }}"

  @derived_fields ~w(id name sequence namespace help_text multi wrapper class code refs vars svg deleted_at)a
  @derive {Jason.Encoder, only: @derived_fields}

  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped
  trait Brando.Trait.CastPolymorphicEmbeds

  attributes do
    attribute :name, :string, required: true
    attribute :namespace, :string, required: true
    attribute :help_text, :text, required: true
    attribute :class, :string, required: true
    attribute :code, :text, required: true
    attribute :svg, :text
    attribute :wrapper, :boolean

    attribute :vars, {:array, PolymorphicEmbed},
      types: Var.types(),
      type_field: :type,
      on_type_not_found: :raise,
      on_replace: :delete
  end

  relations do
    # relation :entry_template, :embeds_one, module: Module, on_replace: :delete
    relation :refs, :embeds_many, module: Module.Ref, on_replace: :delete
  end

  translations do
    context :naming do
      translate :singular, t("embedded module")
      translate :plural, t("embedded modules")
    end
  end
end
