defmodule Brando.MCP.Token do
  @moduledoc """
  An access or refresh token of a `Brando.MCP.Grant`. Only the SHA-256 hash
  of the token is stored; the token itself is shown to the client once.

  A refresh token is used once: `rotated_at` marks it, and using it again
  revokes the whole grant (reuse detection). For ten seconds after it is
  exchanged it keeps the pair it was exchanged for, encrypted with
  `Brando.Crypto` (`successor_ciphertext`), so a client that refreshes twice
  at once gets the same pair again while that pair is unused.
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
    belongs_to :successor, __MODULE__
    field :successor_ciphertext, :string, redact: true
    field :revoked_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
