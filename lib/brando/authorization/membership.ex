defmodule Brando.Authorization.Membership do
  @moduledoc "Membership in one group; a user may belong to several groups in each site."
  use Ecto.Schema

  @schema_prefix "public"
  @primary_key false
  schema "authorization_user_groups" do
    field :user_id, :id, primary_key: true
    belongs_to :group, Brando.Authorization.Group, primary_key: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
