defmodule Brando.OptionCompatibility.AttributeMatrix do
  use Brando.Blueprint,
    application: "Brando",
    domain: "OptionCompatibility",
    schema: "AttributeMatrix",
    singular: "attribute_matrix",
    plural: "attribute_matrices",
    gettext_module: Brando.Gettext

  attributes do
    attribute :database_field, :string,
      default: "protected",
      load_in_query: false,
      read_after_writes: true,
      redact: true,
      skip_default_validation: true,
      source: :stored_field,
      writable: :never

    attribute :generated_id, :uuid, autogenerate: true
    attribute :amount, :decimal, null: false, precision: 12, scale: 4

    attribute :required_code, :string,
      constraints: [min_length: 2],
      required: true,
      unique: true

    attribute :renamed, :string, rename_from: :legacy_name
    attribute :scratch, :string, default: "scratch", virtual: true
    attribute :visibility, :enum, embed_as: :dumped, values: [public: "public", private: "private"]
    attribute :language, :language, languages: [[value: "en", text: "English"]]
  end
end
