defmodule Brando.MCP.Setting do
  @moduledoc """
  Whether the remote MCP endpoint is on for one site environment (or for the
  installation, without tenancy), and how its tools reach Figma. No row
  means off and no Figma. See `Brando.MCP` and `Brando.Figma`.

  `figma_token` is a pasted personal access token, encrypted with
  `Brando.Crypto`; `figma_token_hint` is its last four characters, for the
  admin to show. `figma_token_expires_on` is the expiry date the
  administrator gave when saving it (Figma's API does not tell it), or nil.

  The site environment's Figma app (`figma_client_id`, `figma_client_secret`,
  encrypted) and the OAuth connection made with it (`figma_oauth_*`, the
  tokens encrypted) are `Brando.Figma.OAuth`'s. `figma_oauth_state_hash` and
  `figma_oauth_pending` hold a connection being made, until its callback.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "mcp_settings" do
    belongs_to :site, Brando.Sites.Site
    belongs_to :environment, Brando.Environments.Environment
    field :enabled, :boolean, default: false
    belongs_to :changed_by, Brando.Users.User
    field :figma_token, :binary, redact: true
    field :figma_token_hint, :string
    field :figma_token_set_at, :utc_datetime_usec
    belongs_to :figma_token_set_by, Brando.Users.User
    field :figma_token_expires_on, :date
    field :figma_client_id, :binary, redact: true
    field :figma_client_id_hint, :string
    field :figma_client_secret, :binary, redact: true
    field :figma_app_set_at, :utc_datetime_usec
    belongs_to :figma_app_set_by, Brando.Users.User
    field :figma_oauth_access_token, :binary, redact: true
    field :figma_oauth_refresh_token, :binary, redact: true
    field :figma_oauth_expires_at, :utc_datetime_usec
    field :figma_oauth_handle, :string
    field :figma_oauth_connected_at, :utc_datetime_usec
    belongs_to :figma_oauth_connected_by, Brando.Users.User
    field :figma_oauth_needs_reconnect, :boolean, default: false
    field :figma_oauth_state_hash, :binary, redact: true
    field :figma_oauth_pending, :binary, redact: true
    timestamps(type: :utc_datetime_usec)
  end
end
