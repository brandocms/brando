defmodule Brando.MCP.Setting do
  @moduledoc """
  Whether the remote MCP endpoint is on for one site environment (or for the
  installation, without tenancy), and the Figma access token its tools import
  from. No row means off and no token. See `Brando.MCP` and `Brando.Figma`.

  `figma_token` is encrypted with `Brando.Crypto`; `figma_token_hint` is its
  last four characters, for the admin to show.
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
    timestamps(type: :utc_datetime_usec)
  end
end
