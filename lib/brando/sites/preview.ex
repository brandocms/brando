defmodule Brando.Sites.Preview do
  use Brando.Web, :schema
  use Brando.Schema

  @type t :: %__MODULE__{}
  @type changeset :: Ecto.Changeset.t()

  meta :en, singular: "preview", plural: "previews"
  meta :no, singular: "forhåndsvisning", plural: "forhåndsvisninger"

  identifier false

  absolute_url fn router, endpoint, entry ->
    router.preview_url(endpoint, :show, entry.preview_key)
  end

  schema "sites_previews" do
    field :preview_key, :string
    field :expires_at, :utc_datetime
    field :html, :string
    belongs_to :creator, Brando.Users.User
    timestamps()
  end

  @required_fields ~w(creator_id preview_key expires_at html)a
  @optional_fields ~w()a

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}, user) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> put_creator(user)
    |> validate_required(@required_fields)
  end
end
