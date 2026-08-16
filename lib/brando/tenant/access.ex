defmodule Brando.Tenant.Access do
  @moduledoc """
  Authorization boundary for entering and managing site tenants.

  A global superuser may access every active site. Other users require a
  `Brando.Users.UserSite` assignment and receive the role stored on that
  assignment. Suspended and archived sites are not enterable, even through a
  stale signed session.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Users.User
  alias Brando.Users.UserSite

  @public_opts [prefix: "public"]

  @spec list_sites(User.t() | nil) :: [Site.t()]
  def list_sites(%User{role: :superuser}) do
    from(site in Site,
      where: site.status == :active,
      order_by: [asc: site.name, asc: site.id],
      preload: [:environments]
    )
    |> Repo.all(@public_opts)
  end

  def list_sites(%User{id: user_id}) do
    from(site in Site,
      join: user_site in UserSite,
      on: user_site.site_id == site.id,
      where: user_site.user_id == ^user_id and site.status == :active,
      order_by: [asc: site.name, asc: site.id],
      preload: [:environments]
    )
    |> Repo.all(@public_opts)
  end

  def list_sites(nil), do: []

  @spec role_for(User.t(), Site.t()) :: :superuser | :admin | :editor | nil
  def role_for(%User{role: :superuser}, %Site{status: :active}), do: :superuser

  def role_for(%User{id: user_id}, %Site{id: site_id, status: :active}) do
    from(user_site in UserSite,
      where: user_site.user_id == ^user_id and user_site.site_id == ^site_id,
      select: user_site.role
    )
    |> Repo.one(@public_opts)
  end

  def role_for(%User{}, %Site{}), do: nil

  @spec can_access?(User.t() | nil, Site.t()) :: boolean()
  def can_access?(%User{} = user, %Site{} = site), do: not is_nil(role_for(user, site))
  def can_access?(nil, %Site{}), do: false

  @spec can_manage?(User.t() | nil, Site.t()) :: boolean()
  def can_manage?(%User{} = user, %Site{} = site), do: role_for(user, site) in [:admin, :superuser]
  def can_manage?(nil, %Site{}), do: false

  @spec grant(User.t(), Site.t(), :editor | :admin) ::
          {:ok, UserSite.t()} | {:error, Ecto.Changeset.t()}
  def grant(%User{} = user, %Site{} = site, role) when role in [:editor, :admin] do
    case get_assignment(user, site) do
      nil -> %UserSite{user_id: user.id, site_id: site.id}
      assignment -> assignment
    end
    |> UserSite.changeset(%{role: role})
    |> then(fn changeset ->
      if changeset.data.id, do: Repo.update(changeset, @public_opts), else: Repo.insert(changeset, @public_opts)
    end)
  end

  @spec revoke(User.t(), Site.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def revoke(%User{} = user, %Site{} = site) do
    case get_assignment(user, site) do
      nil ->
        :ok

      assignment ->
        case Repo.delete(assignment, @public_opts) do
          {:ok, _deleted} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @spec list_assignments(Site.t()) :: [UserSite.t()]
  def list_assignments(%Site{id: site_id}) do
    from(user_site in UserSite,
      where: user_site.site_id == ^site_id,
      order_by: [asc: user_site.id],
      preload: [:user]
    )
    |> Repo.all(@public_opts)
  end

  defp get_assignment(%User{id: user_id}, %Site{id: site_id}) do
    from(user_site in UserSite,
      where: user_site.user_id == ^user_id and user_site.site_id == ^site_id
    )
    |> Repo.one(@public_opts)
  end
end
