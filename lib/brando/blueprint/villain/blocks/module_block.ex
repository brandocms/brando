defmodule Brando.Blueprint.Villain.Blocks.ModuleBlock do
  alias Brando.Blueprint.Villain.Blocks.ModuleBlock
  alias Brando.Blueprint.Villain.Blocks
  alias Brando.Villain.Module

  # TODO: Split into ModuleBlock and MultiModuleBlock?

  # defmodule Ref do
  #   use Brando.Blueprint,
  #     application: "Brando",
  #     domain: "Villain",
  #     schema: "ModuleBlockRef",
  #     singular: "module_block_ref",
  #     plural: "module_blocks_refs",
  #     gettext_module: Brando.Gettext

  #   @primary_key false
  #   data_layer :embedded
  #   identifier "{{ entry.type }}"

  #   trait Brando.Trait.CastPolymorphicEmbeds

  #   attributes do
  #     attribute :name, :text, required: true
  #     attribute :description, :text
  #     attribute :deleted, :boolean, default: false

  #     attribute :data, PolymorphicEmbed,
  #       types: Blocks.list_blocks(),
  #       type_field: :type,
  #       on_type_not_found: :raise,
  #       on_replace: :update
  #   end
  # end

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

    attributes do
      attribute :module_id, :integer, required: true
      attribute :sequence, :integer
      attribute :multi, :boolean, default: false
    end

    relations do
      relation :refs, :embeds_many, module: Module.Ref, on_replace: :delete
      relation :vars, :embeds_many, module: Module.Var, on_replace: :delete
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
    attribute :type, :string, required: true
    attribute :hidden, :boolean, default: false
  end

  relations do
    relation :data, :embeds_one, module: __MODULE__.Data
  end
end
