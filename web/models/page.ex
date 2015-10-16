defmodule Brando.Page do
  @moduledoc """
  Ecto schema for the Page model.
  """
  @type t :: %__MODULE__{}

  use Brando.Web, :model
  use Brando.Villain.Model
  import Brando.Gettext
  import Brando.Utils.Model, only: [put_creator: 2]
  import Ecto.Query
  alias Brando.Type.Status
  alias Brando.User

  @required_fields ~w(key language title slug data status creator_id)
  @optional_fields ~w(parent_id meta_description meta_keywords html css_classes)

  schema "pages" do
    field :key, :string
    field :language, :string
    field :title, :string
    field :slug, :string
    villain
    field :status, Status
    field :css_classes, :string
    belongs_to :creator, User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    field :meta_description, :string
    field :meta_keywords, :string
    timestamps
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :create.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t | :empty) :: t
  def changeset(model, action, params \\ :empty)
  def changeset(model, :create, params) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :update.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :update, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t) :: t
  def changeset(model, :update, params) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end

  @doc """
  Create a changeset for the model by passing `params`.
  If valid, generate a hashed password and insert model to Brando.repo.
  If not valid, return errors from changeset
  """
  def create(params, current_user) do
    %__MODULE__{}
    |> put_creator(current_user)
    |> changeset(:create, params)
    |> Brando.repo.insert
  end

  @doc """
  Create an `update` changeset for the model by passing `params`.
  If password is in changeset, hash and insert in changeset.
  If valid, update model in Brando.repo.
  If not valid, return errors from changeset
  """
  def update(model, params) do
    model
    |> changeset(:update, params)
    |> Brando.repo.update
  end

  @doc """
  Duplicates `model`
  """
  def duplicate(model) do
    %__MODULE__{}
    |> changeset(:create, model |> Map.drop([:__struct__, :__meta__, :id,
                                             :key, :slug, :title,
                                             :children, :creator, :parent,
                                             :updated_at, :inserted_at]))
    |> Brando.repo.insert
  end

  def encode_data(params) do
    cond do
      is_list(params.data)   ->
        Map.put(params, :data, Poison.encode!(params.data))
      is_binary(params.data) ->
        params
    end
  end

  @doc """
  Delete `id` from database. Also deletes any connected image fields,
  including all generated sizes.
  """
  def delete(record) when is_map(record) do
    Brando.repo.delete!(record)
  end
  def delete(id) do
    record = Brando.repo.get_by!(__MODULE__, id: id)
    delete(record)
  end

  @doc """
  Order by language, status, key and insertion
  """
  def order(query) do
    from m in query,
         order_by: [asc: m.language, asc: m.status, desc: m.key,
                    desc: m.inserted_at]
  end

  @doc """
  Only gets models that are parents
  """
  def with_parents(query) do
    from m in query,
         where: is_nil(m.parent_id)
  end

  @doc """
  Get model with children from DB by `id`
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
  Gets model with parents and children
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
  Preloads :creator field
  """
  def preload_creator(query) do
    from m in query, preload: [:creator]
  end

  @doc """
  Search pages for `q`
  """
  def search(language, q) do
    __MODULE__
    |> where([p], p.language == ^language)
    |> where([p], ilike(p.html, "%#{q}%"))
    |> Brando.repo.all
  end

  #
  # Meta

  use Brando.Meta.Model, [
    singular: gettext("page"),
    plural: gettext("pages"),
    repr: &("#{&1.title}"),
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
      updated_at: gettext("Updated"),
    ]
  ]
end
