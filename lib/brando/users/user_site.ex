defmodule Brando.Users.UserSite do
  @moduledoc """
  Grants a global Brando user a role within one site.

  User/site assignments live in `public` because they control which tenant
  schemas a user may enter. The global `:superuser` role bypasses assignments;
  all other multi-tenant access is represented here.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Brando.Sites.Site
  alias Brando.Users.User

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]
  @roles [:editor, :admin]

  @type t :: %__MODULE__{}

  schema "user_sites" do
    belongs_to :user, User
    belongs_to :site, Site
    field :role, Ecto.Enum, values: @roles

    timestamps()
  end

  @doc false
  def changeset(user_site \\ %__MODULE__{}, attrs) do
    user_site
    |> cast(attrs, [:user_id, :site_id, :role])
    |> validate_required([:user_id, :site_id, :role])
    |> assoc_constraint(:user)
    |> assoc_constraint(:site)
    |> unique_constraint([:user_id, :site_id])
  end

  def roles, do: @roles
end
