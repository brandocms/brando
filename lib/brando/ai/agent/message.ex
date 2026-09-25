defmodule Brando.AI.Agent.Message do
  @moduledoc """
  A conversation message: `user`, `assistant` (text and/or `tool_calls`) or
  `tool` (a JSON result for `tool_call_id`). The model's context is rebuilt
  from these rows for every run.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "public"
  schema "ai_messages" do
    field :conversation_id, :binary_id
    field :run_id, :binary_id
    field :role, :string
    field :content, :string
    field :tool_calls, {:array, :map}, default: []
    field :tool_call_id, :string
    field :tool_name, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
