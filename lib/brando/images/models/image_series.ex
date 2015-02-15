defmodule Brando.Images.Model.ImageSeries do
  @moduledoc """
  Ecto schema for the Image Series model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  alias Brando.Utils
  alias Brando.Users.Model.User
  alias Brando.Images.Model.Image
  alias Brando.Images.Model.ImageCategory

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
    |> Brando.get_repo.all
    |> List.first
  end
end