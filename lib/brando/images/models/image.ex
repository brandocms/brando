defmodule Brando.Images.Model.Image do
  @moduledoc """
  Ecto schema for the Image model
  and helper functions for dealing with the model.
  """
  @type t :: %__MODULE__{}

  use Ecto.Model
  import Ecto.Query, only: [from: 2]
  alias Brando.Utils
  alias Brando.Users.Model.User
  alias Brando.Images.Model.ImageSeries

  schema "images" do
    field :title, :string
    field :credits, :string
    field :order, :integer
    field :optimized, :boolean
    belongs_to :creator, User
    belongs_to :series, ImageSeries
    timestamps
  end
end