defmodule Brando.Blueprint.Villain.Blocks.MapBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "MapBlockData",
      singular: "map_block_data",
      plural: "map_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :embed_url, :string
      attribute :source, :enum, values: [:gmaps]
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "map"
end
