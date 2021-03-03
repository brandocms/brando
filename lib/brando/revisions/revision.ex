defmodule Brando.Revisions.Revision do
  use Brando.Web, :schema
  use Brando.Schema

  @type t :: %__MODULE__{}
  @type user :: Brando.Users.User.t() | :system

  meta :en, singular: "revision", plural: "revisions"
  meta :no, singular: "revisjon", plural: "revisjoner"
  identifier false
  absolute_url false

  @primary_key false
  schema "revisions" do
    field :active, :boolean, default: false
    field :entry_id, :integer
    field :entry_type, :string
    field :encoded_entry, :string
    field :metadata, :map
    field :revision, :integer
    field :protected, :boolean, default: false
    timestamps()
    belongs_to :creator, Brando.Users.User
  end

  @optional_fields ~w(active protected)a
  @required_fields ~w(entry_id entry_type encoded_entry metadata revision creator_id)a

  @spec changeset(t, Keyword.t() | Options.t()) :: Ecto.Changeset.t()
  def changeset(schema, params \\ %{}) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
