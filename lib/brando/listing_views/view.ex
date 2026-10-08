defmodule Brando.ListingViews.View do
  @moduledoc """
  A saved listing view: the URL parameters of one admin listing (filters,
  status, sort and page size) under a name. See `Brando.ListingViews`.

  `schema` and `listing` name the listing (`"Elixir.MyApp.Projects.Project"` and
  `"default"`); `params` holds the parameters as the listing reads them from
  its URL, string keys and string values. A shared view is seen by everyone
  who can open the listing; only its creator, or someone allowed to manage
  shared views, changes it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @name_max 60

  schema "listing_views" do
    field :name, :string
    field :schema, :string
    field :listing, :string
    field :params, :map, default: %{}
    field :shared, :boolean, default: false
    belongs_to :creator, Brando.Users.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The longest name a view takes."
  def name_max, do: @name_max

  @doc "A new view, or a change to a view's name, parameters or sharing."
  def changeset(view, attrs) do
    view
    |> cast(attrs, [:name, :params, :shared])
    # An emptied field casts to nil
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> validate_length(:name, max: @name_max)
    |> validate_params()
    |> unique_constraint(:name, name: :listing_views_creator_name_index)
  end

  # Only flat string pairs, as the listing reads them from the URL
  defp validate_params(changeset) do
    validate_change(changeset, :params, fn :params, params ->
      if Enum.all?(params, &url_param?/1), do: [], else: [params: "must be URL parameters"]
    end)
  end

  defp url_param?({key, value}), do: is_binary(key) and is_binary(value)
end
