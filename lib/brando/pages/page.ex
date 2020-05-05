defmodule Brando.Pages.Page do
  @moduledoc """
  Ecto schema for the Page schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Field.Image.Schema
  use Brando.Sequence.Schema
  use Brando.SoftDelete.Schema
  use Brando.Villain.Schema

  alias Brando.Type.Status
  alias Brando.JSONLD

  @required_fields ~w(key language slug title data status template creator_id)a
  @optional_fields ~w(parent_id meta_description meta_image html css_classes sequence deleted_at)a
  @derived_fields ~w(
    id
    key
    language
    title
    slug
    data
    html
    template
    status
    css_classes
    creator_id
    parent_id
    meta_description
    meta_image
    sequence
    inserted_at
    updated_at
    deleted_at
  )a

  json_ld_schema JSONLD.Schema.Article do
    field :author, {:references, :identity}
    field :copyrightHolder, {:references, :identity}
    field :copyrightYear, :string, [:inserted_at, :year]
    field :creator, {:references, :identity}
    field :dateModified, :string, [:updated_at], &JSONLD.to_datetime/1
    field :datePublished, :string, [:inserted_at], &JSONLD.to_datetime/1
    field :description, :string, [:meta_description]
    field :headline, :string, [:title]
    field :inLanguage, :string, [:language]
    field :mainEntityOfPage, :string, [:__meta__, :current_url]
    field :name, :string, [:title]
    field :publisher, {:references, :identity}
    field :url, :string, [:__meta__, :current_url]
  end

  meta_schema do
    field ["description", "og:description"], [:meta_description]
    field ["title", "og:title"], [:title]
    field "og:image", [:meta_image]
    field "og:locale", [:language], &Brando.Meta.Utils.encode_locale/1
  end

  @derive {Jason.Encoder, only: @derived_fields}
  schema "pages_pages" do
    field :key, :string
    field :language, :string
    field :title, :string
    field :slug, :string
    field :template, :string
    villain()
    field :status, Status
    field :css_classes, :string
    field :meta_description, :string
    field :meta_image, Brando.Type.Image

    belongs_to :creator, Brando.Users.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :fragments, Brando.Pages.PageFragment

    sequenced()
    timestamps()
    soft_delete()
  end

  has_image_field :meta_image, %{
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: :xlarge,
    upload_path: Path.join(["images", "meta", "pages"]),
    random_filename: true,
    size_limit: 5_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "150x150>", "quality" => 75, "crop" => true},
      "xlarge" => %{"size" => "1200x630", "quality" => 75, "crop" => true}
    }
  }

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, Keyword.t() | Options.t()) :: Ecto.Changeset.t()
  def changeset(schema, params \\ %{}, user \\ :system)

  def changeset(schema, params, user) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> put_creator(user)
    |> put_slug()
    |> validate_required(@required_fields)
    |> unique_constraint(:key)
    |> validate_upload({:image, :meta_image}, user)
    |> avoid_slug_collision()
    |> generate_html()
  end

  @doc """
  Encodes `data` in `params` if not a binary.
  """
  @deprecated "Not in use after conversion to jsonb"
  def encode_data(params) do
    if is_list(params.data) do
      Map.put(params, :data, Jason.encode!(params.data))
    else
      params
    end
  end

  @doc """
  Order by language, status, key and insertion
  """
  @deprecated "Use context functions instead: Brando.Pages.*"
  def order(query) do
    from m in query,
      order_by: [
        asc: m.language,
        asc: m.sequence,
        asc: m.status,
        desc: m.key,
        desc: m.inserted_at
      ]
  end
end
