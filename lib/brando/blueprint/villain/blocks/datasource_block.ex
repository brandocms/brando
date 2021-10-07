defmodule Brando.Blueprint.Villain.Blocks.DatasourceBlock do
  defmodule Data do
    defmodule Test do
      use Brando.Trait
      @changeset_phase :before_validate_required

      def changeset_mutator(_module, _config, changeset, _user, _opts) do
        changeset
      end
    end

    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "DatasourceBlockData",
      singular: "datasource_block_data",
      plural: "datasource_block_datas",
      gettext_module: Brando.Gettext

    trait __MODULE__.Test

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
