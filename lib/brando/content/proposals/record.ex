defmodule Brando.Content.Proposals.Record do
  @moduledoc """
  A stored proposal version.

  Each refinement is a new record with the next `version`; the previous
  version is marked `superseded`, and its approval no longer counts. The
  operations are stored frozen, in `Brando.Content.Proposals.Codec` form, so
  review, preview and apply all build the same content.

  `origin` says where the proposal came from: `"assistant"` (the admin's
  Assistant, in a conversation) or `"mcp"` (a tool connected over MCP, with
  no conversation). `client` names that tool when it is known, such as
  "Claude Code". Proposals stored before `brando_207` without a
  conversation have no origin.
  """
  use Ecto.Schema

  @statuses ~w(pending approved applied undone superseded cancelled)
  @origins ~w(assistant mcp)

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
    field :origin, :string
    field :client, :string
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
  def origins, do: @origins
end
