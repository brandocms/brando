defmodule Brando.Blueprint.Villain.Blocks.ContainerBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "ContainerBlockData",
      singular: "container_block_data",
      plural: "container_block_datas",
      gettext_module: Brando.Gettext

    alias Brando.Blueprint.Villain.Blocks

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    trait Brando.Trait.CastPolymorphicEmbeds

    attributes do
      attribute :palette_id, :id

      attribute :blocks, {:array, PolymorphicEmbed},
        types: Blocks.list_blocks(),
        type_field: :type,
        on_type_not_found: :raise,
        on_replace: :delete
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "container"
end
