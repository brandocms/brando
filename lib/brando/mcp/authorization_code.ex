defmodule Brando.MCP.AuthorizationCode do
  @moduledoc """
  A one-time authorization code, hashed: what the person approved on the
  consent screen, bound to the client, its redirect URI, the PKCE challenge,
  the user, the site environment and the resource. It lasts a minute.
  Exchanging it twice revokes the grant the first exchange made.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "mcp_authorization_codes" do
    field :code_hash, :binary, redact: true
    belongs_to :user, Brando.Users.User
    belongs_to :site, Brando.Sites.Site
    belongs_to :environment, Brando.Environments.Environment
    field :resource, :string
    field :client_id, :string
    field :client_name, :string
    field :redirect_uri, :string
    field :code_challenge, :string
    field :scope, :string
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec
    belongs_to :grant, Brando.MCP.Grant
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
