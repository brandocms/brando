defmodule Brando.Pages.Page do
  @moduledoc """
  Ecto schema for the Page schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Villain.Schema

  import Brando.HTML, only: [truncate: 2]

  alias Brando.Type.Status
  alias Brando.JSONLD

  @max_meta_description_length 155
  @max_meta_title_length 60

  @required_fields ~w(key language slug title data status creator_id)a
  @optional_fields ~w(parent_id meta_description html css_classes)a
  @derived_fields ~w(
    id
    key
    language
    title
    slug
    data
    html
    status
    css_classes
    creator_id
    parent_id
    meta_description
    inserted_at
    updated_at
  )a

  json_ld_schema JSONLD.Schema.Article do
    field :author, {:references, :identity}
    field :copyrightHolder, {:references, :identity}
    field :copyrightYear, :string, [:inserted_at], & &1.year
    field :creator, {:references, :creator}
    field :dateModified, :string, [:updated_at], &JSONLD.to_datetime(&1)
    field :datePublished, :string, [:inserted_at], &JSONLD.to_datetime(&1)
    field :description, :string, [:meta_description]
    field :headline, :string, [:title]
    field :inLanguage, :string, [:language]
    field :mainEntityOfPage, :string, & &1.__meta__.current_url
    field :name, :string, [:title]
    field :publisher, {:references, :creator}
    field :url, :string, & &1.__meta__.current_url
  end

  meta_schema do
    field ["description", "og:description"],
          [:meta_description],
          &truncate(&1, @max_meta_description_length)

    field ["title", "og:title"],
          [:title],
          &truncate(&1, @max_meta_title_length)

    field "og:locale", [:language], &Brando.Meta.Utils.encode_locale/1
  end

  @derive {Jason.Encoder, only: @derived_fields}
  schema "pages_pages" do
    field :key, :string
    field :language, :string
    field :title, :string
    field :slug, :string
    villain()
    field :status, Status
    field :css_classes, :string
    field :meta_description, :string

    belongs_to :creator, Brando.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :fragments, Brando.Pages.PageFragment

    timestamps()
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, :create | :update, Keyword.t() | Options.t()) :: Ecto.Changeset.t()
  def changeset(schema, action, params \\ %{})

  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> put_slug()
    |> validate_required(@required_fields)
    |> avoid_slug_collision()
    |> generate_html()
  end

  def changeset(schema, :update, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> put_slug()
    |> validate_required(@required_fields)
    |> avoid_slug_collision()
    |> generate_html()
  end

  @doc """
  Encodes `data` in `params` if not a binary.
  """
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
  def order(query) do
    from m in query,
      order_by: [
        asc: m.language,
        asc: m.status,
        desc: m.key,
        desc: m.inserted_at
      ]
  end

  @doc """
  Only gets schemas that are parents
  """
  def only_parents(query) do
    from m in query,
      where: is_nil(m.parent_id)
  end

  @doc """
  Get schema with children from DB by `id`
  """
  def with_children(query) do
    from m in query,
      left_join: c in assoc(m, :children),
      left_join: p in assoc(m, :parent),
      left_join: cu in assoc(c, :creator),
      join: u in assoc(m, :creator),
      preload: [children: {c, creator: cu}, creator: u, parent: p],
      select: m
  end

  @doc """
  Gets schema with parents and children
  """
  def with_parents_and_children(query) do
    children_query =
      from c in query,
        order_by: [asc: c.status, asc: c.key, desc: c.updated_at],
        preload: [:creator]

    from m in query,
      left_join: c in assoc(m, :children),
      left_join: cu in assoc(c, :creator),
      join: u in assoc(m, :creator),
      where: is_nil(m.parent_id),
      preload: [children: ^children_query, creator: u],
      select: m
  end

  @doc """
  Search pages for `q`
  """
  def search(language, query) do
    from p in __MODULE__,
      where: p.language == ^language,
      where: ilike(p.html, ^"%#{query}%")
  end

  defimpl Phoenix.HTML.Safe, for: Brando.Pages.Page do
    def to_iodata(page) do
      page.html
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end

  defimpl Phoenix.HTML.Safe, for: Brando.Pages.PageFragment do
    def to_iodata(page) do
      page.html
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end
end
