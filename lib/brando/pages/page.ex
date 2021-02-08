defmodule Brando.Pages.Page do
  @moduledoc """
  Ecto schema for the Page schema.
  """

  @type t :: %__MODULE__{}
  @type user :: Brando.Users.User.t() | :system

  use Brando.Web, :schema
  use Brando.Field.Image.Schema
  use Brando.Sequence.Schema
  use Brando.SoftDelete.Schema, obfuscated_fields: [:slug, :key]
  use Brando.Villain.Schema

  alias Brando.JSONLD

  @required_fields ~w(key language slug title data status template creator_id)a
  @optional_fields ~w(parent_id meta_title meta_description meta_image html is_homepage css_classes sequence deleted_at publish_at)a
  @derived_fields ~w(
    id
    key
    language
    title
    slug
    data
    html
    is_homepage
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
    publish_at
  )a

  @derive {Jason.Encoder, only: @derived_fields}
  schema "pages_pages" do
    field :key, :string
    field :language, :string
    field :title, :string
    field :slug, :string
    field :template, :string
    field :is_homepage, :boolean
    villain()
    field :status, Brando.Type.Status
    field :css_classes, :string
    field :meta_title, :string
    field :meta_description, :string
    field :meta_image, Brando.Type.Image
    field :publish_at, :utc_datetime

    belongs_to :creator, Brando.Users.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :fragments, Brando.Pages.PageFragment
    has_many :properties, Brando.Pages.Property, on_replace: :delete

    sequenced()
    timestamps()
    soft_delete()
  end

  has_image_field :meta_image, %{
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "xlarge",
    upload_path: Path.join(["images", "meta", "pages"]),
    random_filename: true,
    size_limit: 5_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "150x150>", "quality" => 75, "crop" => true},
      "xlarge" => %{"size" => "1200x630", "quality" => 75, "crop" => true}
    }
  }

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
    field ["title", "og:title"], &fallback(&1, [:meta_title, :title])
    field "og:image", [:meta_image]
    field "og:locale", [:language], &encode_locale/1
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, Keyword.t() | Options.t(), user) :: Ecto.Changeset.t()
  def changeset(schema, params \\ %{}, user \\ :system) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_assoc(:properties)
    |> put_creator(user)
    |> put_slug()
    |> validate_required(@required_fields)
    |> unique_constraint([:key, :language])
    |> validate_upload({:image, :meta_image}, user)
    |> avoid_field_collision([:slug, :key])
    |> generate_html()
  end
end
