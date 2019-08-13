defmodule Brando.Sites.Link do
  use Brando.Web, :schema
  use Brando.Sequence, :schema

  @type t :: %__MODULE__{}

  schema "sites_links" do
    field :name, :string
    field :url, :string
    belongs_to :organization, Brando.Sites.Organization

    sequenced()
    timestamps()
  end

  @required_fields ~w(name url)a
  @optional_fields ~w()a

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}, _user \\ :system) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
