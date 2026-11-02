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

  alias Brando.Authorization.{Boundary, Engine, Scope}

  def list_sites(user) do
    if Engine.enabled?(), do: Engine.accessible_sites(user), else: legacy_list_sites(user)
  end

  # An admin view holds the user it mounted with: the role that counts is stored.
  @spec list_sites(User.t() | nil) :: [Site.t()]
  defp legacy_list_sites(%User{} = user) do
    case Boundary.fresh_role(user) do
      %User{role: :superuser} -> all_active_sites()
      %User{id: user_id} -> assigned_active_sites(user_id)
    end
  end

  defp legacy_list_sites(nil), do: []

  defp all_active_sites do
    from(site in Site,
      where: site.status == :active,
      order_by: [asc: site.name, asc: site.id],
      preload: [:environments]
    )
    |> Repo.all(@public_opts)
  end

  defp assigned_active_sites(user_id) do
    from(site in Site,
      join: user_site in UserSite,
      on: user_site.site_id == site.id,
      where: user_site.user_id == ^user_id and site.status == :active,
      order_by: [asc: site.name, asc: site.id],
      preload: [:environments]
    )
    |> Repo.all(@public_opts)
  end

  # Compatibility display only. Authorization callers use capabilities below.
  def role_for(user, site) do
    if Engine.enabled?() do
      cond do
        not can_access?(user, site) -> nil
        Engine.superuser?(Scope.site(user, site)) -> :superuser
        can_manage?(user, site) -> :admin
        true -> :editor
      end
    else
      legacy_role_for(user, site)
    end
  end

  @spec role_for(User.t(), Site.t()) :: :superuser | :admin | :editor | nil
  defp legacy_role_for(%User{id: nil, role: :superuser}, %Site{status: :active}), do: :superuser

  # One read for the stored role and the assignment: an open view's struct may
  # hold a role since lowered.
  defp legacy_role_for(%User{id: user_id}, %Site{id: site_id, status: :active}) when not is_nil(user_id) do
    from(user in User,
      left_join: user_site in UserSite,
      on: user_site.user_id == user.id and user_site.site_id == ^site_id,
      where: user.id == ^user_id,
      select: {user.role, user_site.role}
    )
    |> Repo.one(@public_opts)
    |> case do
      {:superuser, _site_role} -> :superuser
      {_role, site_role} -> site_role
      nil -> nil
    end
  end

  defp legacy_role_for(%User{}, %Site{}), do: nil

  @spec can_access?(User.t() | nil, Site.t()) :: boolean()
  def can_access?(%User{} = user, %Site{} = site) do
    if Engine.enabled?(),
      do: Engine.can?(Scope.site(user, site), :access, :backend),
      else: not is_nil(legacy_role_for(user, site))
  end

  def can_access?(nil, %Site{}), do: false

  @spec can_manage?(User.t() | nil, Site.t()) :: boolean()
  def can_manage?(%User{} = user, %Site{} = site) do
    if Engine.enabled?(),
      do: Engine.can?(Scope.site(user, site), :update, :environments),
      else: legacy_role_for(user, site) in [:admin, :superuser]
  end

  def can_manage?(nil, %Site{}), do: false

  @doc """
  Whether the account `user_id` may act now, and in the site `site_id` if one
  is given, by what is stored: `{role, enterable?}`, or nil for an account
  inactive or gone. One read, for an open view's every event in legacy mode
  (`BrandoAdmin.Authorization`). `enterable?` answers as `can_access?/2` does.
  """
  @spec legacy_standing(integer(), integer() | nil) :: {atom(), boolean()} | nil
  def legacy_standing(user_id, nil) do
    from(user in User,
      where: user.id == ^user_id and user.active == true and is_nil(user.deleted_at),
      select: user.role
    )
    |> Repo.one(@public_opts)
    |> case do
      nil -> nil
      role -> {role, true}
    end
  end

  def legacy_standing(user_id, site_id) do
    from(user in User,
      left_join: site in Site,
      on: site.id == ^site_id and site.status == :active,
      left_join: user_site in UserSite,
      on: user_site.user_id == user.id and user_site.site_id == site.id,
      where: user.id == ^user_id and user.active == true and is_nil(user.deleted_at),
      select: {user.role, site.id, user_site.id}
    )
    |> Repo.one(@public_opts)
    |> case do
      nil -> nil
      {role, nil, _assignment} -> {role, false}
      {:superuser, _site, _assignment} -> {:superuser, true}
      {role, _site, assignment} -> {role, not is_nil(assignment)}
    end
  end

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
    |> tap(&broadcast_on_success/1)
  end

  @spec revoke(User.t(), Site.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def revoke(%User{} = user, %Site{} = site) do
    case get_assignment(user, site) do
      nil ->
        :ok

      assignment ->
        case Repo.delete(assignment, @public_opts) do
          {:ok, _deleted} = result ->
            broadcast_on_success(result)
            :ok

          {:error, changeset} ->
            {:error, changeset}
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

  # Open lobby channels re-check their site scope; legacy mode has no other signal.
  defp broadcast_on_success({:ok, _record}), do: Brando.Authorization.Realtime.broadcast_changed()
  defp broadcast_on_success(_error), do: :ok

  defp get_assignment(%User{id: user_id}, %Site{id: site_id}) do
    from(user_site in UserSite,
      where: user_site.user_id == ^user_id and user_site.site_id == ^site_id
    )
    |> Repo.one(@public_opts)
  end
end
