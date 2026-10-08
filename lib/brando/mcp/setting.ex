defmodule Brando.MCP.Setting do
  @moduledoc """
  Whether the remote MCP endpoint is on for one site environment (or for the
  installation, without tenancy). No row means off. See `Brando.MCP`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "mcp_settings" do
    belongs_to :site, Brando.Sites.Site
    belongs_to :environment, Brando.Environments.Environment
    field :enabled, :boolean, default: false
    belongs_to :changed_by, Brando.Users.User
    timestamps(type: :utc_datetime_usec)
  end
end
