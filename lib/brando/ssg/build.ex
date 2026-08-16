defmodule Brando.SSG.Build do
  @moduledoc "Metadata and lifecycle state for one versioned static-site build."

  use Ecto.Schema

  import Ecto.Changeset

  alias Brando.Assets.SiteAssetSet
  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Users.User

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]

  @statuses [:queued, :building, :ready, :deployed, :failed, :archived]

  @type t :: %__MODULE__{}

  schema "ssg_builds" do
    belongs_to :site, Site
    belongs_to :environment, Environment
    belongs_to :asset_set, SiteAssetSet
    belongs_to :creator, User

    field :version, :string
    field :build_number, :integer
    field :environment_name, :string
    field :environment_key, :string
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :build_path, :string
    field :build_log, :string, default: ""
    field :note, :string
    field :file_count, :integer, default: 0
    field :total_size, :integer, default: 0
    field :url_count, :integer, default: 0
    field :processed_urls, :integer, default: 0
    field :failed_urls, {:array, :string}, default: []
    field :auto_deploy, :boolean, default: false
    field :deploy_config, :map, default: %{}
    field :preview_token, :string
    field :preview_expires_at, :utc_datetime_usec
    field :scheduled_at, :utc_datetime_usec
    field :built_at, :utc_datetime_usec
    field :deployed_at, :utc_datetime_usec
    field :pruned_at, :utc_datetime_usec

    timestamps()
  end

  @required_fields [
    :site_id,
    :version,
    :build_number,
    :environment_name,
    :environment_key,
    :status,
    :build_path,
    :preview_token,
    :preview_expires_at
  ]

  @optional_fields [
    :environment_id,
    :asset_set_id,
    :creator_id,
    :build_log,
    :note,
    :file_count,
    :total_size,
    :url_count,
    :processed_urls,
    :failed_urls,
    :auto_deploy,
    :deploy_config,
    :scheduled_at,
    :built_at,
    :deployed_at,
    :pruned_at
  ]

  def changeset(build \\ %__MODULE__{}, attrs) do
    build
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:build_number, greater_than: 0)
    |> validate_number(:file_count, greater_than_or_equal_to: 0)
    |> validate_number(:total_size, greater_than_or_equal_to: 0)
    |> validate_number(:url_count, greater_than_or_equal_to: 0)
    |> validate_number(:processed_urls, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:environment_id)
    |> foreign_key_constraint(:asset_set_id)
    |> foreign_key_constraint(:creator_id)
    |> unique_constraint([:site_id, :build_number])
    |> unique_constraint(:preview_token)
  end

  def statuses, do: @statuses
end
