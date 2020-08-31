defmodule Brando.Navigation.Item do
  @moduledoc """
  Ecto schema for the Menu schema.
  """

  @type t :: %__MODULE__{}
  @type user :: Brando.Users.User.t() | :system

  use Brando.Web, :schema
  use Brando.Sequence.Schema

  schema "navigation_items" do
    field :status, Brando.Type.Status
    field :title, :string
    field :key, :string
    field :url, :string
    field :open_in_new_window, :boolean, default: false

    belongs_to :creator, Brando.Users.User
    belongs_to :menu, Brando.Navigation.Menu
    belongs_to :parent, __MODULE__
    has_many :items, __MODULE__, foreign_key: :parent_id

    sequenced()
    timestamps()
  end

  @required_fields ~w(status title key url open_in_new_window creator_id menu_id)a
  @optional_fields ~w(sequence parent_id)a

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, Keyword.t() | Options.t(), user) :: Ecto.Changeset.t()
  def changeset(schema, params \\ %{}, user \\ :system) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> put_creator(user)
    |> validate_required(@required_fields)
    |> unique_constraint([:parent_id, :key])
  end
end
