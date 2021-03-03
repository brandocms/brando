defmodule Brando.Sites.Identity do
  use Brando.Web, :schema
  use Brando.Field.Image.Schema
  use Brando.Schema

  @type t :: %__MODULE__{}
  @type changeset :: Ecto.Changeset.t()

  meta :en, singular: "identity", plural: "identities"
  meta :no, singular: "identitet", plural: "identiteter"
  identifier false
  absolute_url false

  schema "sites_identity" do
    field :type, :string
    field :name, :string
    field :alternate_name, :string
    field :email, :string
    field :phone, :string
    field :address, :string
    field :address2, :string
    field :address3, :string
    field :zipcode, :string
    field :city, :string
    field :country, :string
    field :title_prefix, :string
    field :title, :string
    field :title_postfix, :string
    field :logo, Brando.Type.Image
    field :languages, :map, virtual: true

    embeds_many :metas, Brando.Meta, on_replace: :delete
    embeds_many :links, Brando.Link, on_replace: :delete
    embeds_many :configs, Brando.ConfigEntry, on_replace: :delete

    timestamps()
  end

  has_image_field(
    :logo,
    %{
      allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
      default_size: "xlarge",
      upload_path: Path.join(["images", "sites", "identity", "logo"]),
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{
        "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
        "thumb" => %{"size" => "150x150>", "quality" => 65, "crop" => true},
        "xlarge" => %{"size" => "1920", "quality" => 65}
      }
    }
  )

  @required_fields ~w(name type)a
  @optional_fields ~w(alternate_name phone address address2 address3 zipcode city country logo title title_prefix title_postfix email)a

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}, user) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:links)
    |> cast_embed(:metas)
    |> cast_embed(:configs)
    |> validate_required(@required_fields)
    |> validate_upload({:image, :logo}, user)
  end
end
