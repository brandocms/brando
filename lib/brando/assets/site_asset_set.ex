defmodule Brando.Assets.SiteAssetSet do
  @moduledoc "Metadata for one persistent frontend asset bundle."

  use Ecto.Schema

  import Ecto.Changeset

  alias Brando.Sites.Site

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{}

  schema "site_asset_sets" do
    belongs_to :site, Site
    field :name, :string
    field :path, :string
    field :active, :boolean, default: false
    field :uploaded_at, :utc_datetime_usec
    field :size, :integer, default: 0
    field :file_count, :integer, default: 0
    field :metadata, :map, default: %{}

    timestamps()
  end

  @doc false
  def changeset(asset_set \\ %__MODULE__{}, attrs) do
    asset_set
    |> cast(attrs, [:site_id, :name, :path, :active, :uploaded_at, :size, :file_count, :metadata])
    |> validate_required([:name, :path, :uploaded_at, :size, :file_count])
    |> validate_number(:size, greater_than_or_equal_to: 0)
    |> validate_number(:file_count, greater_than_or_equal_to: 0)
    |> assoc_constraint(:site)
    |> unique_constraint(:name, name: :site_asset_sets_standalone_name_index)
    |> unique_constraint([:site_id, :name], name: :site_asset_sets_site_name_index)
  end
end
