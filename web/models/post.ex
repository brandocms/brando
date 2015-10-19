defmodule Brando.Post do
  @moduledoc """
  Ecto schema for the Post model, as well as image field definitions
  and helper functions for dealing with the post model.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :model
  use Brando.Tag, :model
  use Brando.Villain, :model
  use Brando.Field.ImageField

  alias Brando.Type.Status
  alias Brando.User

  import Brando.Gettext
  import Brando.Utils.Model, only: [put_creator: 2]
  import Ecto.Query, only: [from: 2]

  @required_fields ~w(status header data lead creator_id language featured slug)
  @optional_fields ~w(publish_at tags html)

  schema "posts" do
    field :language, :string
    field :header, :string
    field :slug, :string
    field :lead, :string
    villain
    field :cover, Brando.Type.Image
    field :status, Status
    belongs_to :creator, User
    field :meta_description, :string
    field :meta_keywords, :string
    field :featured, :boolean
    field :published, :boolean
    field :publish_at, Ecto.DateTime
    timestamps
    tags
  end

  has_image_field :cover,
    %{allowed_mimetypes: ["image/jpeg", "image/png"],
      default_size: :medium,
      upload_path: Path.join(["images", "posts", "covers"]),
      random_filename: true,
      size_limit: 10240000,
      sizes: %{
        "small" =>  %{"size" => "300", "quality" => 100},
        "medium" => %{"size" => "500", "quality" => 100},
        "large" =>  %{"size" => "700", "quality" => 100},
        "xlarge" => %{"size" => "900", "quality" => 100},
        "thumb" =>  %{"size" => "150x150", "quality" => 100, "crop" => true},
        "micro" =>  %{"size" => "25x25", "quality" => 100, "crop" => true}
      }
    }

  @doc """
  Casts and validates `params` against `model` to create a valid
  changeset when action is :create.

  ## Example

      model_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t | Options.t | :empty) :: t
  def changeset(model, action, params \\ :empty)
  def changeset(model, :create, params) do
    params = params |> Brando.Tag.split_tags
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
    params = params |> Brando.Tag.split_tags
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
    record.cover |> delete_original_and_sized_images
    Brando.repo.delete!(record)
  end
  def delete(id) do
    record = Brando.repo.get_by!(__MODULE__, id: id)
    delete(record)
  end

  @doc """
  Order posts and preload creator
  """
  def order(query) do
    from m in query,
        order_by: [asc: m.status, desc: m.featured, desc: m.inserted_at]
  end

  @doc """
  Preloads :creator field
  """
  def preload_creator(query) do
    from m in query, preload: [:creator]
  end


  #
  # Meta

  use Brando.Meta.Model, [
    singular: gettext("post"),
    plural: gettext("posts"),
    repr: &("#{&1.header}"),
    fields: [
      id: "№",
      status: gettext("Status"),
      featured: gettext("Featured"),
      language: gettext("Language"),
      cover: gettext("Cover"),
      header: gettext("Header"),
      slug: gettext("Slug"),
      lead: gettext("Lead"),
      data: gettext("Data"),
      html: gettext("HTML"),
      creator: gettext("Creator"),
      meta_description: gettext("META description"),
      meta_keywords: gettext("META keywords"),
      published: gettext("Published"),
      publish_at: gettext("Publish at"),
      tags: gettext("Tags"),
      inserted_at: gettext("Inserted at"),
      updated_at: gettext("Updated at"),
    ]
  ]
end
