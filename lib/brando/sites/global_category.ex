defmodule Brando.Sites.GlobalCategory do
  use Brando.Web, :schema
  use Brando.Schema
  alias Brando.Sites.Global

  meta :en, singular: "global category", plural: "global categories"
  meta :no, singular: "globalkategori", plural: "globalkategorier"
  identifier false
  absolute_url false

  @type t :: %__MODULE__{}
  @type changeset :: Ecto.Changeset.t()

  schema "sites_global_categories" do
    field :label, :string
    field :key, :string
    has_many :globals, Global, on_replace: :delete
  end

  @required_fields ~w(label key)a
  @optional_fields ~w()a

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_assoc(:globals)
    |> validate_required(@required_fields)
  end
end
