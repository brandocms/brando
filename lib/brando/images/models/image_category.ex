defmodule Brando.Images.Model.ImageCategory do
  @moduledoc """
  Ecto schema for the Image Category model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  alias Brando.Utils
  alias Brando.Users.Model.User
  alias Brando.Images.Model.ImageSeries

  schema "imagecategories" do
    field :name, :string
    field :slug, :string
    field :cfg,  :string
    belongs_to :creator, User
    has_many :image_series, ImageSeries
    timestamps
  end

  @doc """
  Get all records. Ordered by `id`.
  """
  def all do
    q = from m in __MODULE__,
        order_by: [asc: m.name],
        preload: [:image_series, image_series: :images]
    Brando.get_repo.all(q)
  end
end