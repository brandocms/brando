defmodule Brando.Pages.Page do
  @moduledoc """
  Ecto schema for the Page schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Villain, :schema

  alias Brando.Type.Status
  import Brando.Gettext

  @required_fields ~w(key language slug title data status creator_id)a
  @optional_fields ~w(parent_id meta_description meta_keywords html css_classes)a

  @derive {Poison.Encoder, only: ~w(
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
    meta_keywords
    inserted_at
    updated_at
  )a}
  @derive {Jason.Encoder, only: ~w(
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
    meta_keywords
    inserted_at
    updated_at
  )a}

  schema "pages" do
    field :key, :string
    field :language, :string
    field :title, :string
    field :slug, :string
    villain()
    field :status, Status
    field :css_classes, :string
    belongs_to :creator, Brando.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    field :meta_description, :string
    field :meta_keywords, :string
    timestamps()
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t() | Options.t()) :: t
  def changeset(schema, action, params \\ %{})

  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> put_slug()
    |> validate_required(@required_fields)
    |> avoid_slug_collision()
    |> generate_html()
  end

  @spec changeset(t, atom, Keyword.t() | Options.t()) :: t
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
      Map.put(params, :data, Poison.encode!(params.data))
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

  #
  # Meta

  use Brando.Meta.Schema,
    singular: gettext("page"),
    plural: gettext("pages"),
    repr: &"#{&1.title}",
    fields: [
      id: "№",
      status: gettext("Status"),
      language: gettext("Language"),
      key: gettext("Key"),
      title: gettext("Title"),
      slug: gettext("Slug"),
      data: gettext("Data"),
      html: gettext("HTML"),
      parent: gettext("Belongs to"),
      parent_id: gettext("Belongs to"),
      children: gettext("Sub pages"),
      creator: gettext("Creator"),
      css_classes: gettext("Extra CSS classes"),
      meta_description: gettext("META description"),
      meta_keywords: gettext("META keywords"),
      inserted_at: gettext("Inserted"),
      updated_at: gettext("Updated")
    ],
    help: [
      parent_id: gettext("If this page should belong to another, select parent page here.")
    ]
end
