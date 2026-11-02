defmodule Brando.Authorization.Operations do
  @moduledoc "Capability checks for site lifecycle operations outside generated contexts."
  alias Brando.Authorization.{Boundary, Engine, Scope}
  alias Brando.Users.User

  def run(action, resource, site_id, opts, fun) do
    actor = opts[:creator] || opts[:actor] || Boundary.current_scope() || actor_id(opts[:creator_id])
    with :ok <- authorize(actor, action, resource, site_id), do: fun.()
  end

  def authorize(:system, _, _, _), do: :ok

  def authorize(actor, action, resource, site_id) do
    if Engine.enabled?() do
      scope = Boundary.actor_scope(actor)

      with false <- scope.kind == :site and scope.site_id != site_id,
           %{id: ^site_id} = site <- Brando.Repo.get(Brando.Sites.Site, site_id) do
        Engine.authorize(Scope.site(%{id: scope.user_id}, site), action, resource)
      else
        _ -> {:error, :forbidden}
      end
    else
      legacy_authorize(actor, resource, site_id)
    end
  end

  # The rule the environment screen and the scheduler already follow: an admin
  # or superuser, a site's manager with several sites. Work with no account
  # behind it runs, as it always has.
  defp legacy_authorize(actor, :environments, site_id) do
    case legacy_user(actor) do
      nil -> :ok
      user -> if legacy_manager?(user, site_id), do: :ok, else: {:error, :forbidden}
    end
  end

  defp legacy_authorize(_actor, _resource, _site_id), do: :ok

  defp legacy_user(%Scope{user_id: id}), do: legacy_user(%{id: id})
  defp legacy_user(%{id: id}) when is_integer(id), do: Brando.Repo.get(User, id)
  defp legacy_user(_actor), do: nil

  defp legacy_manager?(user, site_id) do
    if Brando.Tenant.mode() == :multi do
      case Brando.Repo.get(Brando.Sites.Site, site_id) do
        nil -> false
        site -> Brando.Tenant.Access.can_manage?(user, site)
      end
    else
      user.role in [:admin, :superuser]
    end
  end

  defp actor_id(nil), do: nil
  defp actor_id(id), do: %{id: id}
end
