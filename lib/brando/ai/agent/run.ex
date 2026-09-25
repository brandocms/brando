defmodule Brando.AI.Agent.Run do
  @moduledoc """
  One agent turn: the model calls and tool calls answering a user message.

  Token counts are the provider's reported usage summed over the run's calls;
  `reserved_tokens` is held against the budget while a call is in flight.
  `status` is `running`, `completed`, `failed`, `cancelled`,
  `budget_exhausted` or `interrupted`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "public"
  schema "ai_runs" do
    field :conversation_id, :binary_id
    field :scope, :string
    field :status, :string, default: "running"
    field :model, :string
    field :steps, :integer, default: 0
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cached_tokens, :integer, default: 0
    field :reasoning_tokens, :integer, default: 0
    field :reserved_tokens, :integer, default: 0
    field :cost, :float, default: 0.0
    field :error, :string
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
