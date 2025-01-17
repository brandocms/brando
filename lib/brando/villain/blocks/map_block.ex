defmodule Brando.Villain.Blocks.MapBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "map"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "MapBlockData",
      singular: "map_block_data",
      plural: "map_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :embed_url, :string
      attribute :source, :enum, values: [:gmaps]
    end
  end
end
