defmodule Brando.Authorization.Group do
  @moduledoc "A named set of permissions within one explicit authorization scope."
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]

  schema "authorization_groups" do
    field :key, :string
    field :name, :string
    field :description, :string
    field :scope_kind, Ecto.Enum, values: [:standalone, :site, :installation]
    field :site_id, :id
    field :preset, Ecto.Enum, values: [:user, :editor, :admin, :superuser]
    field :lock_version, :integer, default: 1
    has_many :grants, Brando.Authorization.Grant
    has_many :memberships, Brando.Authorization.Membership
    timestamps()
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> validate_length(:description, max: 500)
    |> unique_constraint(:key, name: :authorization_groups_scoped_key_index)
  end
end
