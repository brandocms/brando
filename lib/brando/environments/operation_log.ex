defmodule Brando.Environments.OperationLog do
  @moduledoc """
  Immutable public-registry audit record for environment lifecycle operations.

  Source and target references are nilified when an environment is deleted so
  historical operations remain inspectable.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Users.User

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  @operations [:copy, :set_live, :rollback, :create, :delete]

  @type t :: %__MODULE__{}

  schema "environment_operation_logs" do
    belongs_to :site, Site
    belongs_to :source_environment, Environment
    belongs_to :target_environment, Environment
    belongs_to :creator, User

    field :operation, Ecto.Enum, values: @operations
    field :archive_schema, :string
    field :note, :string

    timestamps()
  end

  @required_fields [:site_id, :operation]
  @optional_fields [
    :source_environment_id,
    :target_environment_id,
    :creator_id,
    :archive_schema,
    :note
  ]

  def changeset(log \\ %__MODULE__{}, attrs) do
    log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:source_environment_id)
    |> foreign_key_constraint(:target_environment_id)
    |> foreign_key_constraint(:creator_id)
  end

  def operations, do: @operations
end
