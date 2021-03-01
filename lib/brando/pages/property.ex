defmodule Brando.Pages.Property do
  use Brando.Web, :schema
  use Brando.Schema
  alias Brando.Pages.Page

  @type t :: %__MODULE__{}
  @type changeset :: Ecto.Changeset.t()

  identifier false
  absolute_url false

  schema "pages_properties" do
    field :type, :string
    field :label, :string
    field :key, :string
    field :data, :map
    belongs_to :page, Page
  end

  @required_fields ~w(label key data type)a
  @optional_fields ~w()a

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
