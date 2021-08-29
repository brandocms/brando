defmodule Brando.Blueprint.Villain.Blocks.DatasourceBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "DatasourceBlockData",
      singular: "datasource_block_data",
      plural: "datasource_block_datas",
      gettext_module: Brando.Gettext

    alias Brando.Blueprint.Villain.Blocks
    alias Brando.Images.Focal

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :module, :string
      attribute :type, Ecto.Enum, values: [:list, :single, :selection]
      attribute :query, :string
      attribute :code, :string
      attribute :arg, :string
      attribute :limit, :string
      attribute :ids, {:array, :id}
      attribute :description, :string
      attribute :module_id, :id
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "datasource"
end
