defmodule Brando.Content.Module.Entry do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "ModuleEntryData",
      singular: "module_entry_data",
      plural: "module_entry_datas",
      gettext_module: Brando.Gettext

    alias Brando.Content.Var
    alias Brando.Content.Module

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    trait Brando.Trait.CastPolymorphicEmbeds

    attributes do
      attribute :sequence, :integer

      attribute :vars, {:array, PolymorphicEmbed},
        types: [
          boolean: Var.Boolean,
          text: Var.Text,
          string: Var.String,
          datetime: Var.Datetime,
          html: Var.Html,
          color: Var.Color
        ],
        type_field: :type,
        on_type_not_found: :raise,
        on_replace: :delete
    end

    relations do
      relation :refs, :embeds_many, module: Module.Ref, on_replace: :delete
    end
  end

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "ModuleEntry",
    singular: "module_entry",
    plural: "module_entries",
    gettext_module: Brando.Gettext

  data_layer :embedded
  @primary_key false

  identifier "{{ entry.label }}"

  attributes do
    attribute :uid, :string
    attribute :type, :string, required: true
    attribute :hidden, :boolean, default: false
  end

  relations do
    relation :data, :embeds_one, module: __MODULE__.Data
  end
end
