defmodule Brando.Sites.Identity do
  use Brando.Web, :schema
  use Brando.Field.Image.Schema

  @type t :: %__MODULE__{}
  @type changeset :: Ecto.Changeset.t()

  schema "sites_identities" do
    field :type, :string
    field :name, :string
    field :alternate_name, :string
    field :email, :string
    field :phone, :string
    field :address, :string
    field :zipcode, :string
    field :city, :string
    field :country, :string
    field :description, :string
    field :title_prefix, :string
    field :title, :string
    field :title_postfix, :string
    field :image, Brando.Type.Image
    field :logo, Brando.Type.Image
    field :url, :string

    embeds_many :metas, Brando.Meta, on_replace: :delete
    embeds_many :links, Brando.Link, on_replace: :delete
    embeds_many :globals, Brando.Global, on_replace: :delete
    embeds_many :configs, Brando.ConfigEntry, on_replace: :delete

    timestamps()
  end

  has_image_field(
    :image,
    %{
      allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
      default_size: :medium,
      upload_path: Path.join(["images", "sites", "identity", "image"]),
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{
        "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
        "thumb" => %{"size" => "150x150>", "quality" => 65, "crop" => true},
        "xlarge" => %{"size" => "2100", "quality" => 65}
      }
    }
  )

  has_image_field(
    :logo,
    %{
      allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
      default_size: :medium,
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

  @required_fields ~w(name type email description title url)a
  @optional_fields ~w(alternate_name image phone address zipcode city country logo title_prefix title_postfix)a

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
    |> cast_embed(:globals)
    |> validate_required(@required_fields)
    |> validate_upload({:image, :image}, user)
    |> validate_upload({:image, :logo}, user)
  end
end
