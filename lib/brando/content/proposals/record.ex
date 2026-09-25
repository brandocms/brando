defmodule Brando.Content.Proposals.Record do
  @moduledoc """
  A stored proposal version.

  Each refinement is a new record with the next `version`; the previous
  version is marked `superseded`, and its approval no longer counts. The
  operations are stored frozen, in `Brando.Content.Proposals.Codec` form, so
  review, preview and apply all build the same content.
  """
  use Ecto.Schema

  @statuses ~w(pending approved applied superseded cancelled)

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @schema_prefix "public"
  schema "content_proposals" do
    field :conversation_id, :binary_id
    field :version, :integer
    field :supersedes_id, :binary_id
    field :scope, :string
    field :actor_id, :integer
    field :summary, :string
    field :operations, {:array, :map}
    field :fingerprints, :map
    field :module_versions, {:array, :map}
    field :problems, {:array, :map}
    field :effects, :map
    field :status, :string, default: "pending"
    field :approved_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses
end
