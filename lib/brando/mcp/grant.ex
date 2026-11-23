defmodule Brando.MCP.Grant do
  @moduledoc """
  A connection a person approved: `user` let the client `client_id` (its
  Client ID Metadata Document URL, named `client_name` by that document)
  read content and propose changes in one site environment, through the
  MCP endpoint `resource`. It holds no secret; its tokens
  (`Brando.MCP.Token`) do, hashed. Revoking it ends every token at once.

  `auto_apply` is what the connection may apply without review: `"none"`,
  or `"unpublished_translations"` (proposals that only create unpublished
  translations, `Brando.Content.Proposals.AutoApply`). A site's managers set
  it (`Brando.MCP.set_auto_apply/3`); `auto_apply_set_by` and
  `auto_apply_set_at` say who last changed it, and when. A new connection
  starts at `"none"`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  @auto_apply ~w(none unpublished_translations)

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
    field :auto_apply, :string, default: "none"
    belongs_to :auto_apply_set_by, Brando.Users.User
    field :auto_apply_set_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc "What a connection's `auto_apply` may be."
  @spec auto_apply_kinds() :: [String.t()]
  def auto_apply_kinds, do: @auto_apply
end
