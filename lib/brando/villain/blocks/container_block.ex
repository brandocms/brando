# TODO: PRobably throw this out?
defmodule Brando.Villain.Blocks.ContainerBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "ContainerBlockData",
      singular: "container_block_data",
      plural: "container_block_datas",
      gettext_module: Brando.Gettext

    alias Brando.Villain.Blocks

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    trait Brando.Trait.CastPolymorphicEmbeds

    attributes do
      attribute :target_id, :string
      attribute :palette_id, :id
      attribute :description, :string

      attribute :blocks, {:array, PolymorphicEmbed},
        types: Blocks.list_blocks(),
        type_field: :type,
        default: [],
        on_type_not_found: :raise,
        on_replace: :delete
    end
  end

  use Brando.Villain.Block,
    type: "container"
end
