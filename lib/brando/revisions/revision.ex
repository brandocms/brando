defmodule Brando.Revisions.Revision do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Revisions",
    schema: "Revision",
    singular: "revision",
    plural: "revisions",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped

  table "revisions"
  primary_key false
  identifier "{{ entry.entry_type }} - {{ entry.entry_id }}"

  attributes do
    attribute :active, :boolean, default: false
    attribute :entry_id, :integer, required: true
    attribute :entry_type, :string, required: true
    attribute :encoded_entry, :string, required: true
    attribute :metadata, :map, required: true
    attribute :revision, :integer, required: true
    attribute :description, :text
    attribute :protected, :boolean, default: false
  end
end
