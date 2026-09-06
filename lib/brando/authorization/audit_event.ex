defmodule Brando.Authorization.AuditEvent do
  @moduledoc "Immutable history of changes to groups, grants and memberships."
  use Ecto.Schema

  @schema_prefix "public"
  schema "authorization_audit_events" do
    field :actor_id, :id
    field :action, :string
    field :group_id, :id
    field :subject_user_id, :id
    field :site_id, :id
    field :before, :map
    field :after, :map
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
