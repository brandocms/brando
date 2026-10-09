defmodule Brando.AI.Agent.Run do
  @moduledoc """
  One agent turn: the model calls and tool calls answering a user message.

  Token counts are the provider's reported usage summed over the run's calls;
  `reserved_tokens` is held against the budget while a call is in flight.
  `status` is `running`, `stopping` (asked to stop, its process not yet
  ended), `completed`, `failed`, `cancelled`,
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
    # The database's clock, not the writing node's: liveness (`updated_at`)
    # is compared across nodes whose clocks may differ.
    timestamps(type: :utc_datetime_usec, autogenerate: {__MODULE__, :now, []})
  end

  @doc "The database's current time, as `updated_at` stores it."
  @spec now() :: DateTime.t()
  def now do
    %{rows: [[now]]} = Ecto.Adapters.SQL.query!(Brando.Repo.repo(), "SELECT clock_timestamp() AT TIME ZONE 'UTC'")
    DateTime.from_naive!(now, "Etc/UTC")
  end
end
