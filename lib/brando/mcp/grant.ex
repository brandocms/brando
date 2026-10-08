defmodule Brando.MCP.Grant do
  @moduledoc """
  A connection a person approved: `user` let the client `client_id` (its
  Client ID Metadata Document URL, named `client_name` by that document)
  read content and propose changes in one site environment, through the
  MCP endpoint `resource`. It holds no secret; its tokens
  (`Brando.MCP.Token`) do, hashed. Revoking it ends every token at once.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "mcp_grants" do
    belongs_to :user, Brando.Users.User
    belongs_to :site, Brando.Sites.Site
    belongs_to :environment, Brando.Environments.Environment
    field :resource, :string
    field :client_id, :string
    field :client_name, :string
    field :redirect_uri, :string
    field :scope, :string
    field :last_used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    belongs_to :revoked_by, Brando.Users.User
    field :revoked_reason, :string
    timestamps(type: :utc_datetime_usec)
  end
end
