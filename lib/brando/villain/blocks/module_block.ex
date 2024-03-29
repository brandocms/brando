defmodule Brando.Villain.Blocks.ModuleBlock do
  alias Brando.Content.Module
  alias Brando.Content.Var

  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "ModuleBlockData",
      singular: "module_block_data",
      plural: "module_blocks_data",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    trait Brando.Trait.CastPolymorphicEmbeds

    attributes do
      attribute :module_id, :integer, required: true
      attribute :sequence, :integer
      attribute :multi, :boolean, default: false
      attribute :datasource, :boolean, default: false
      attribute :datasource_selected_ids, {:array, :id}

      attribute :vars, {:array, Brando.PolymorphicEmbed},
        types: Var.types(),
        type_field: :type,
        on_type_not_found: :raise,
        on_replace: :delete
    end

    relations do
      relation :refs, :embeds_many, module: Module.Ref, on_replace: :delete
      relation :entries, :embeds_many, module: Module.Entry, on_replace: :delete
    end
  end

  use Brando.Blueprint,
    application: "Brando",
    domain: "Villain",
    schema: "ModuleBlock",
    singular: "module_block",
    plural: "module_blocks",
    gettext_module: Brando.Gettext

  @primary_key false
  data_layer :embedded
  identifier "{{ entry.type }}"

  attributes do
    attribute :uid, :string
    attribute :description, :string
    attribute :type, :string, required: true
    attribute :hidden, :boolean, default: false
    attribute :collapsed, :boolean, default: false
  end

  relations do
    relation :data, :embeds_one, module: __MODULE__.Data
  end
end
