defmodule Brando.MCP.Token do
  @moduledoc """
  An access or refresh token of a `Brando.MCP.Grant`. Only the SHA-256 hash
  of the token is stored; the token itself is shown to the client once.

  A refresh token is used once: `rotated_at` marks it, and using it again
  revokes the whole grant (reuse detection).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "mcp_tokens" do
    belongs_to :grant, Brando.MCP.Grant
    field :kind, Ecto.Enum, values: [:access, :refresh]
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    field :rotated_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
