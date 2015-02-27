defmodule Brando.Images.Model.ImageSeries do
  @moduledoc """
  Ecto schema for the Image Series model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  alias Brando.Users.Model.User
  alias Brando.Images.Model.Image
  alias Brando.Images.Model.ImageCategory

  def __name__(:singular), do: "bildeserie"
  def __name__(:plural), do: "bildeserier"

  def __str__(model) do
    model = Brando.get_repo.preload(model, :images)
    image_count = Enum.count(model.images)
    "#{model.name} – #{image_count} bilde(r)."
  end

  use Linguist.Vocabulary
  locale "no", [
    model: [
      id: "ID",
      name: "Navn",
      slug: "URL-tamp",
      credits: "Kreditering",
      order: "Rekkefølge",
      creator: "Opprettet av",
      images: "Bilder",
      image_category: "Bildekategori",
      inserted_at: "Opprettet",
      updated_at: "Oppdatert"
    ]
  ]

  schema "imageseries" do
    field :name, :string
    field :slug, :string
    field :credits, :string
    field :order, :integer
    belongs_to :creator, User
    belongs_to :image_category, ImageCategory
    has_many :images, Image
    timestamps
  end

  def get(slug: slug) do
    from(m in __MODULE__,
         where: m.slug == ^slug,
         preload: [:images, :image_category],
         limit: 1)
    |> Brando.get_repo.one!
  end

  @doc """
  Get model from DB by `id`
  """
  def get(id: id) do
    from(m in __MODULE__,
         where: m.id == ^id,
         preload: [:creator, :images, :image_category],
         limit: 1)
    |> Brando.get_repo.one!
  end

  @doc """
  Get model by `val` or raise `Ecto.NoResultsError`.
  """
  def get!(val) do
    get(val) || raise Ecto.NoResultsError, queryable: __MODULE__
  end

  @doc """
  Delete `record` from database.
  """
  def delete(record) do
    Brando.get_repo.delete(record)
  end
end