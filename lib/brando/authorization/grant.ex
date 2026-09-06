defmodule Brando.Authorization.Grant do
  @moduledoc "A registered permission granted by a group."
  use Ecto.Schema

  @schema_prefix "public"
  @primary_key false
  schema "authorization_group_permissions" do
    belongs_to :group, Brando.Authorization.Group, primary_key: true
    field :permission_key, :string, primary_key: true
  end
end
