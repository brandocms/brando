defmodule Brando.ListingViews.Default do
  @moduledoc """
  The view a person opens a listing with: one per person and listing. See
  `Brando.ListingViews`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "listing_view_defaults" do
    field :schema, :string
    field :listing, :string
    belongs_to :user, Brando.Users.User
    belongs_to :view, Brando.ListingViews.View

    timestamps(type: :utc_datetime_usec)
  end
end
