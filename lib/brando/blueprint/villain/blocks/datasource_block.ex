defmodule Brando.Blueprint.Villain.Blocks.DatasourceBlock do
  defmodule Data do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :module, :string
      field :type, Ecto.Enum, values: [:list, :single, :selection]
      field :query, :string
      field :code, :string
      field :arg, :string
      field :limit, :string
      field :ids, {:array, :id}
      field :description, :string
      field :module_id, :id
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, ~w(module type query code arg limit ids description module_id)a)
    end
  end

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :uid, :string
    field :type, :string
    field :hidden, :boolean, default: false
    field :marked_as_deleted, :boolean, default: false, virtual: true
    embeds_one :data, __MODULE__.Data
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, ~w(uid type hidden marked_as_deleted)a)
    |> cast_embed(:data)
  end
end
