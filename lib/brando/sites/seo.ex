defmodule Brando.Sites.SEO do
  use Brando.Web, :schema
  use Brando.Schema
  use Brando.Field.Image.Schema

  meta :en, singular: "SEO", plural: "SEO"
  meta :no, singular: "SEO", plural: "SEO"
  identifier false
  absolute_url false

  @type t :: %__MODULE__{}
  @type changeset :: Ecto.Changeset.t()

  schema "sites_seo" do
    field :fallback_meta_description, :string
    field :fallback_meta_title, :string
    field :fallback_meta_image, Brando.Type.Image
    field :base_url, :string
    field :robots, :string

    embeds_many :redirects, Brando.Sites.Redirect, on_replace: :delete

    timestamps()
  end

  has_image_field(
    :fallback_meta_image,
    %{
      allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
      default_size: "xlarge",
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

  @required_fields ~w()a
  @optional_fields ~w(fallback_meta_description fallback_meta_title fallback_meta_image base_url robots)a

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}, user) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:redirects)
    |> validate_required(@required_fields)
    |> validate_upload({:image, :fallback_meta_image}, user)
  end
end
